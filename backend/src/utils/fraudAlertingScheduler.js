const cron = require('node-cron');
const Admin = require('../models/admin');
const Notification = require('../models/notification');
const { runFraudScan } = require('./fraudDetection');
const { sendFraudAlertSummaryEmail } = require('./adminEmailNotifications');

let systemSenderId = null;
async function getSystemSenderId() {
  if (systemSenderId) return systemSenderId;
  const systemAdmin = (await Admin.findOne({ isSuperAdmin: true })) || (await Admin.findOne());
  systemSenderId = systemAdmin?._id || null;
  return systemSenderId;
}

async function notifyAdmins(newAlerts) {
  if (!newAlerts.length) return;

  const senderId = await getSystemSenderId();
  if (senderId) {
    try {
      await Notification.create({
        sender: senderId,
        senderModel: 'Admin',
        recipientType: 'all-admins',
        recipientModel: 'Admin',
        category: 'system',
        message: `Fraud scan found ${newAlerts.length} new alert${newAlerts.length === 1 ? '' : 's'}. Review them in Manage Disputes & Fraud Alerts.`,
      });
    } catch (err) {
      console.error('Failed to create fraud alert notification:', err);
    }
  }

  try {
    const recipients = await Admin.find({
      $or: [{ isSuperAdmin: true }, { 'permissions.canManageTransactions': true }],
      'notificationSettings.suspiciousTransactionAlerts': true,
      'notificationSettings.emailNotifications': true,
    }).select('email');
    for (const admin of recipients) {
      try {
        await sendFraudAlertSummaryEmail(admin.email, newAlerts);
      } catch (err) {
        console.error(`Failed to email fraud alert summary to ${admin.email}:`, err);
      }
    }
  } catch (err) {
    console.error('Failed to fan out fraud alert emails:', err);
  }
}

async function runScanAndNotify() {
  try {
    const { newAlerts } = await runFraudScan();
    await notifyAdmins(newAlerts);
    return newAlerts;
  } catch (err) {
    console.error('Fraud scan failed:', err);
    return [];
  }
}

function initializeFraudAlertingScheduler() {
  cron.schedule('30 2 * * *', () => {
    runScanAndNotify();
  });
}

module.exports = { initializeFraudAlertingScheduler, runScanAndNotify };
