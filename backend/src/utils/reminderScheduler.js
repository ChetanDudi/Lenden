const cron = require('node-cron');
const User = require('../models/user');
const Admin = require('../models/admin');
const Transaction = require('../models/transaction');
const Notification = require('../models/notification');

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

