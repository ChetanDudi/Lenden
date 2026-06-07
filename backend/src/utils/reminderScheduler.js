const cron = require('node-cron');
const User = require('../models/user');
const Transaction = require('../models/transaction');
const Notification = require('../models/notification');

// Schedule a job to run every day at midnight
cron.schedule('0 0 * * *', async () => {
  try {
    const users = await User.find({ 
      'notificationSettings.paymentReminders': true
    });

    for (const user of users) {
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
          
          const notification = new Notification({
            sender: null, // System notification
            recipientType: 'specific-users',
            recipients: [user._id],
            recipientModel: 'User',
            message: reminderMessage,
          });
          await notification.save();
        }
      }
    }
  } catch (error) {
    console.error('Error sending payment reminders:', error);
  }
});

