const cron = require('node-cron');
const Admin = require('../models/admin');
const User = require('../models/user');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const SupportQuery = require('../models/supportQuery');
const Dispute = require('../models/dispute');
const FraudAlert = require('../models/fraudAlert');
const { sendAdminDigestEmail } = require('./email/adminEmailNotifications');

const PERIOD_SETTINGS_KEY = {
  daily: 'dailyTransactionSummary',
  weekly: 'weeklyTransactionSummary',
  monthly: 'monthlyTransactionSummary',
};

const PERIOD_WINDOW_MS = {
  daily: 24 * 60 * 60 * 1000,
  weekly: 7 * 24 * 60 * 60 * 1000,
  monthly: 30 * 24 * 60 * 60 * 1000,
};

async function gatherDigestStats(since) {
  const [
    newUsers,
    newSecureTx,
    secureVolumeAgg,
    newQuickTx,
    quickVolumeAgg,
    newGroups,
    openSupportQueries,
    newDisputes,
    openDisputes,
    newFraudAlerts,
    openFraudAlerts,
  ] = await Promise.all([
    User.countDocuments({ createdAt: { $gte: since } }),
    Transaction.countDocuments({ createdAt: { $gte: since } }),
    Transaction.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: null, total: { $sum: '$amount' } } },
    ]),
    QuickTransaction.countDocuments({ createdAt: { $gte: since } }),
    QuickTransaction.aggregate([
      { $match: { createdAt: { $gte: since } } },
      { $group: { _id: null, total: { $sum: '$amount' } } },
    ]),
    GroupTransaction.countDocuments({ createdAt: { $gte: since } }),
    SupportQuery.countDocuments({ status: { $in: ['open', 'in_progress'] } }),
    Dispute.countDocuments({ createdAt: { $gte: since } }),
    Dispute.countDocuments({ status: { $in: ['open', 'under_review'] } }),
    FraudAlert.countDocuments({ createdAt: { $gte: since } }),
    FraudAlert.countDocuments({ status: { $in: ['open', 'reviewing'] } }),
  ]);

  return {
    newUsers,
    newSecureTx,
    secureVolume: secureVolumeAgg[0]?.total || 0,
    newQuickTx,
    quickVolume: quickVolumeAgg[0]?.total || 0,
    newGroups,
    openSupportQueries,
    newDisputes,
    openDisputes,
    newFraudAlerts,
    openFraudAlerts,
  };
}

async function sendDigest(period) {
  const settingsKey = PERIOD_SETTINGS_KEY[period];
  const since = new Date(Date.now() - PERIOD_WINDOW_MS[period]);
  const stats = await gatherDigestStats(since);

  const recipients = await Admin.find({
    [`notificationSettings.${settingsKey}`]: true,
    'notificationSettings.emailNotifications': true,
  }).select('email');

  for (const admin of recipients) {
    try {
      await sendAdminDigestEmail(admin.email, period, stats);
    } catch (err) {
      console.error(`Failed to send ${period} digest to ${admin.email}:`, err);
    }
  }
  return { period, recipientCount: recipients.length, stats };
}

function initializeAdminDigestScheduler() {
  cron.schedule('0 7 * * *', () => {
    sendDigest('daily').catch((err) => console.error('Daily admin digest failed:', err));
  });
  cron.schedule('0 7 * * 1', () => {
    sendDigest('weekly').catch((err) => console.error('Weekly admin digest failed:', err));
  });
  cron.schedule('0 7 1 * *', () => {
    sendDigest('monthly').catch((err) => console.error('Monthly admin digest failed:', err));
  });
}

module.exports = { initializeAdminDigestScheduler, sendDigest };
