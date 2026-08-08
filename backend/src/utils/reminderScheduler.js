const cron = require('node-cron');
const User = require('../models/user');
const Admin = require('../models/admin');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const Notification = require('../models/notification');
const { sendReminderEmail } = require('./lendingborrowingotp');
const { sendToUser } = require('../services/notificationService');

// Quiet hours use simple 'HH:mm' string comparison, same format the
// notificationSettings fields are stored in.
function isWithinQuietHours(settings) {
  if (!settings?.quietHoursEnabled) return false;
  const start = settings.quietHoursStart || '22:00';
  const end = settings.quietHoursEnd || '08:00';
  const now = new Date();
  const current = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  if (start <= end) {
    return current >= start && current < end;
  }
  // Overnight window (e.g. 22:00 -> 08:00) wraps past midnight.
  return current >= start || current < end;
}

let systemSenderId = null;
async function getSystemSenderId() {
  if (systemSenderId) return systemSenderId;
  const systemAdmin =
    (await Admin.findOne({ isSuperAdmin: true })) || (await Admin.findOne());
  systemSenderId = systemAdmin?._id || null;
  return systemSenderId;
}

// Schedule a job to run every day at midnight
cron.schedule('0 0 * * *', async () => {
  try {
    const senderId = await getSystemSenderId();
    if (!senderId) {
      console.error('Skipping payment reminders: no admin account exists to attribute system notifications to.');
      return;
    }

    const users = await User.find({
      'notificationSettings.paymentReminders': true,
    });

    for (const user of users) {
      if (isWithinQuietHours(user.notificationSettings)) continue;
      const { reminderFrequency } = user.notificationSettings;

      const transactionsToRemind = await Transaction.find({
        $or: [{ userEmail: user.email }, { counterpartyEmail: user.email }],
        $and: [
            {
                $or: [
                    { userCleared: false },
                    { counterpartyCleared: false }
                ]
            }
        ],
        expectedReturnDate: { $ne: null }
      });

      for (const transaction of transactionsToRemind) {
        const today = new Date();
        const expectedReturnDate = new Date(transaction.expectedReturnDate);
        const daysDifference = Math.ceil((expectedReturnDate - today) / (1000 * 60 * 60 * 24));

        let shouldSendReminder = false;
        if (reminderFrequency === 'daily' && daysDifference <= 7) { // Daily for the last week
          shouldSendReminder = true;
        } else if (reminderFrequency === 'weekly' && (daysDifference % 7 === 0 || daysDifference < 0)) { // Weekly on the day, or if overdue
          shouldSendReminder = true;
        } else if (reminderFrequency === 'monthly' && (expectedReturnDate.getDate() === today.getDate() || daysDifference < 0)) { // Monthly on the day, or if overdue
          shouldSendReminder = true;
        }

        if (shouldSendReminder) {
          const reminderMessage = `Reminder: Payment for transaction of amount ${transaction.amount} is due on ${expectedReturnDate.toDateString()}.`;

          // Email reminder — sendReminderEmail checks emailNotifications + paymentReminders internally
          sendReminderEmail(user.email, transaction, daysDifference).catch(e =>
            console.error(`Failed to send reminder email for user ${user._id}, transaction ${transaction._id}:`, e)
          );

          try {
            const notification = new Notification({
              sender: senderId,
              senderModel: 'Admin',
              recipientType: 'specific-users',
              recipients: [user._id],
              recipientModel: 'User',
              category: 'transaction',
              message: reminderMessage,
            });
            await notification.save();
          } catch (notifyError) {
            // Don't let one bad notification abort reminders for everyone else.
            console.error(`Failed to save payment reminder for user ${user._id}, transaction ${transaction._id}:`, notifyError);
          }
        }
      }
    }
  } catch (error) {
    console.error('Error sending payment reminders:', error);
  }
});

// Birthday notifications — runs every day at 8am
cron.schedule('0 8 * * *', async () => {
  try {
    const now   = new Date();
    const month = now.getMonth() + 1; // 1-12
    const day   = now.getDate();

    // Find users whose birthday is today by month+day match
    const todayBirthdays = await User.find({
      birthday: { $ne: null },
      $expr: {
        $and: [
          { $eq: [{ $month: '$birthday' }, month] },
          { $eq: [{ $dayOfMonth: '$birthday' }, day] },
        ],
      },
    }).select('_id name email').lean();

    if (todayBirthdays.length === 0) return;

    const birthdayEmailSet = new Set(todayBirthdays.map(u => u.email));
    const birthdayIdMap    = new Map(todayBirthdays.map(u => [u._id.toString(), u.name]));

    // For each birthday person, find all users who have them as a friend or counterparty
    for (const bUser of todayBirthdays) {
      // Friends: users whose friends array contains this person
      const friendUsers = await User.find({
        _id: { $ne: bUser._id },
        friends: bUser._id,
        'notificationSettings.friendNotifications': { $ne: false },
      }).select('_id name notificationSettings').lean();

      // Counterparty users: users who share a QuickTransaction with the birthday person
      const qtRecipients = await QuickTransaction.distinct('users', { users: bUser.email });
      const counterpartyEmails = qtRecipients.filter(e => e !== bUser.email && !birthdayEmailSet.has(e));

      const counterpartyUsers = counterpartyEmails.length > 0
        ? await User.find({
            email: { $in: counterpartyEmails },
            'notificationSettings.friendNotifications': { $ne: false },
          }).select('_id notificationSettings').lean()
        : [];

      // Merge and deduplicate recipients (friends + counterparties)
      const recipientMap = new Map();
      for (const u of [...friendUsers, ...counterpartyUsers]) {
        recipientMap.set(u._id.toString(), u);
      }
      const recipients = [...recipientMap.values()];

      if (recipients.length === 0) continue;

      const title   = `🎂 It's ${bUser.name}'s Birthday!`;
      const message = `Today is ${bUser.name}'s birthday. Send them a wish!`;

      for (const recipient of recipients) {
        if (isWithinQuietHours(recipient.notificationSettings)) continue;
        try {
          await Notification.create({
            sender:        bUser._id,
            senderModel:   'User',
            recipientType: 'specific-users',
            recipients:    [recipient._id],
            recipientModel:'User',
            title,
            message,
            category:      'system',
            deliveryStatus:'sent',
            sentAt:        new Date(),
            metadata:      { type: 'birthday', birthdayUserId: bUser._id.toString(), birthdayUserName: bUser.name },
          });
          await sendToUser(User, recipient._id, { title, body: message,
            data: { type: 'birthday', birthdayUserId: bUser._id.toString() } });
        } catch (err) {
          console.error(`[BirthdayNotif] Failed for recipient ${recipient._id}:`, err.message);
        }
      }
    }
  } catch (error) {
    console.error('[BirthdayNotif] Error sending birthday notifications:', error);
  }
});
