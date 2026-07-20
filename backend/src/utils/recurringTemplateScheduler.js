const cron = require('node-cron');
const RecurringQuickTransactionTemplate = require('../models/recurringQuickTransactionTemplate');
const QuickTransaction = require('../models/quickTransaction');
const User = require('../models/user');
const Admin = require('../models/admin');
const Notification = require('../models/notification');

let systemSenderId = null;
async function getSystemSenderId() {
  if (systemSenderId) return systemSenderId;
  const systemAdmin = (await Admin.findOne({ isSuperAdmin: true })) || (await Admin.findOne());
  systemSenderId = systemAdmin?._id || null;
  return systemSenderId;
}

const isBlockedBy = (user, otherId) =>
  (user.blockedUsers || []).some((id) => id.toString() === otherId.toString());

function advanceNextRun(template) {
  const next = new Date(template.nextRunAt);
  if (template.frequency === 'weekly') {
    next.setDate(next.getDate() + 7);
  } else {
    next.setMonth(next.getMonth() + 1);
    const daysInMonth = new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate();
    next.setDate(Math.min(template.dayOfMonth || next.getDate(), daysInMonth));
  }
  return next;
}

async function notifyCreator(senderId, userId, message) {
  if (!senderId) return;
  try {
    await Notification.create({
      sender: senderId,
      senderModel: 'Admin',
      recipientType: 'specific-users',
      recipients: [userId],
      recipientModel: 'User',
      category: 'transaction',
      message,
    });
  } catch (err) {
    console.error('Failed to send recurring-template notification:', err);
  }
}

async function runDueTemplates() {
  const senderId = await getSystemSenderId();
  const due = await RecurringQuickTransactionTemplate.find({
    isActive: true,
    nextRunAt: { $lte: new Date() },
  });

  for (const template of due) {
    try {
      const user = await User.findOne({ email: template.creatorEmail }).select('_id email blockedUsers notificationSettings');
      const counterparty = await User.findOne({ email: template.counterpartyEmail }).select('_id blockedUsers notificationSettings');

      if (!user || !counterparty || isBlockedBy(user, counterparty._id) || isBlockedBy(counterparty, user._id)) {
        template.isActive = false;
        template.pausedReason = 'Counterparty no longer available or has blocked this account.';
        await template.save();
        if (user) {
          await notifyCreator(senderId, user._id,
            `Your recurring quick transaction template (${template.description || template.amount}) was paused: ${template.pausedReason}`);
        }
        continue;
      }

      const now = new Date();
      const quickTransaction = await QuickTransaction.create({
        amount: template.amount,
        currency: template.currency,
        date: now,
        time: now.toTimeString().slice(0, 5),
        description: template.description || 'Recurring quick transaction',
        users: [template.creatorEmail, template.counterpartyEmail],
        creatorEmail: template.creatorEmail,
        role: template.role,
      });

      template.lastRunAt = now;
      template.nextRunAt = advanceNextRun(template);
      await template.save();

      if (user.notificationSettings?.transactionNotifications !== false) {
        await notifyCreator(senderId, user._id,
          `Recurring quick transaction of ${template.amount} ${template.currency} with ${template.counterpartyEmail} was auto-created.`);
      }

      // Notify counterparty too
      if (counterparty.notificationSettings?.transactionNotifications !== false) {
        await Notification.create({
          sender: senderId, senderModel: 'Admin', recipientType: 'specific-users',
          recipients: [counterparty._id], recipientModel: 'User', category: 'transaction',
          message: `A recurring quick transaction of ${template.amount} ${template.currency} with ${template.creatorEmail} was auto-created.`,
        });
      }
    } catch (err) {
      console.error(`Failed to run recurring template ${template._id}:`, err);
    }
  }
}

function initializeRecurringTemplateScheduler() {
  cron.schedule('0 6 * * *', () => {
    runDueTemplates().catch((err) => console.error('Recurring template run failed:', err));
  });
}

module.exports = { initializeRecurringTemplateScheduler, runDueTemplates };
