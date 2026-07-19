const cron = require('node-cron');
const QuickTransaction = require('../models/quickTransaction');
const User = require('../models/user');
const Admin = require('../models/admin');
const Notification = require('../models/notification');

let systemSenderId = null;
async function getSystemSenderId() {
  if (systemSenderId) return systemSenderId;
  const admin = (await Admin.findOne({ isSuperAdmin: true })) || (await Admin.findOne());
  systemSenderId = admin?._id || null;
  return systemSenderId;
}

async function activateDueScheduledTransactions() {
  const senderId = await getSystemSenderId();
  const due = await QuickTransaction.find({
    isScheduled: true,
    scheduledStatus: 'pending',
    scheduledAt: { $lte: new Date() },
  });

  for (const qt of due) {
    try {
      qt.scheduledStatus = 'active';
      await qt.save();

      if (!senderId) continue;
      const users = await User.find({ email: { $in: qt.users } }).select('_id email');
      await Promise.all(users.map((u) =>
        Notification.create({
          sender: senderId,
          senderModel: 'Admin',
          recipientType: 'specific-users',
          recipients: [u._id],
          recipientModel: 'User',
          category: 'transaction',
          message: `Your scheduled quick transaction of ${qt.amount} ${qt.currency} (${qt.description || 'no description'}) is now active.`,
        }).catch((err) => console.error('Notification failed for scheduled QT:', err))
      ));
    } catch (err) {
      console.error(`Failed to activate scheduled quick transaction ${qt._id}:`, err);
    }
  }
}

function initializeScheduledTransactionScheduler() {
  // Run every 5 minutes so scheduled transactions activate promptly
  cron.schedule('*/5 * * * *', () => {
    activateDueScheduledTransactions().catch((err) =>
      console.error('Scheduled transaction activation failed:', err)
    );
  });
}

module.exports = { initializeScheduledTransactionScheduler, activateDueScheduledTransactions };
