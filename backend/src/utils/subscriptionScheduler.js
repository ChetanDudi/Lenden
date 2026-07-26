const cron = require('node-cron');
const mongoose = require('mongoose');
const Admin = require('../models/admin');
const Notification = require('../models/notification');
const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');

let systemSenderId = null;
async function getSystemSenderId() {
  if (systemSenderId) return systemSenderId;
  const systemAdmin = (await Admin.findOne({ isSuperAdmin: true })) || (await Admin.findOne());
  systemSenderId = systemAdmin?._id || null;
  return systemSenderId;
}

async function notifyUser(senderId, userId, message) {
  if (!senderId) return;
  try {
    const u = await User.findById(userId).select('notificationSettings').lean();
    if (u?.notificationSettings?.subscriptionNotifications === false) return;
    await Notification.create({
      sender: senderId,
      senderModel: 'Admin',
      recipientType: 'specific-users',
      recipients: [userId],
      recipientModel: 'User',
      category: 'subscription',
      message,
    });
  } catch (err) {
    console.error(`Failed to create subscription notification for user ${userId}:`, err);
  }
}

// Carries the same wallet-debit + rollover logic as walletController.paySubscription,
// but driven by the cron job instead of a user tapping "renew".
async function attemptWalletRenewal(subscription) {
  const plan = await SubscriptionPlan.findOne({ name: subscription.subscriptionPlan, isAvailable: true });
  if (!plan) return { ok: false, reason: 'plan_unavailable' };

  const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
  const session = await mongoose.startSession();
  try {
    let result = { ok: false, reason: 'insufficient_balance' };
    await session.withTransaction(async () => {
      const user = await User.findOneAndUpdate(
        { _id: subscription.user, walletBalance: { $gte: actualPrice } },
        { $inc: { walletBalance: -actualPrice } },
        { new: true, session }
      );
      if (!user) return;

      await WalletTransaction.create([{
        user: subscription.user,
        type: 'debit',
        amount: actualPrice,
        note: `${plan.name} Subscription Auto-Renewal via LenDen Wallet`,
      }], { session });

      const endDate = new Date(subscription.endDate);
      endDate.setDate(endDate.getDate() + plan.duration + (plan.free || 0));

      const [created] = await Subscription.create([{
        user: subscription.user,
        subscribed: true,
        subscriptionPlan: plan.name,
        duration: plan.duration,
        price: plan.price,
        discount: plan.discount || 0,
        actualPrice,
        free: plan.free || 0,
        subscribedDate: new Date(),
        endDate,
        status: 'active',
        paymentMethod: 'wallet',
        autoRenew: true,
      }], { session });

      await Subscription.updateMany(
        { user: subscription.user, status: 'active', _id: { $ne: created._id } },
        { $set: { status: 'expired' } },
        { session }
      );

      result = { ok: true, plan, endDate };
    });
    return result;
  } finally {
    session.endSession();
  }
}

async function runSubscriptionMaintenance() {
  try {
    const now = new Date();

    // Cleanup sweep: rows whose endDate has already passed shouldn't keep
    // reporting as 'active' just because no one re-fetched their status today.
    await Subscription.updateMany(
      { status: 'active', endDate: { $lt: now } },
      { $set: { status: 'expired' } }
    );

    const senderId = await getSystemSenderId();

    // Auto-resume paused bridging subscriptions whose blocking plan has now expired.
    // This ensures users get their queued plan resumed even if they never open the app.
    const pausedBridging = await Subscription.find({ status: 'paused', pausedByBridging: true });
    for (const paused of pausedBridging) {
      const blockingActive = await Subscription.findOne({
        user: paused.user,
        status: 'active',
        _id: { $ne: paused._id },
      });
      if (!blockingActive && paused.pausedRemainingDays > 0) {
        const newEndDate = new Date(Date.now() + paused.pausedRemainingDays * 24 * 60 * 60 * 1000);
        await Subscription.findByIdAndUpdate(paused._id, {
          $set: { status: 'active', pausedByBridging: false, pausedAt: null, endDate: newEndDate },
        });
        if (senderId) {
          await notifyUser(
            senderId,
            paused.user,
            `Your "${paused.subscriptionPlan}" subscription has been automatically resumed with ${paused.pausedRemainingDays} day${paused.pausedRemainingDays === 1 ? '' : 's'} remaining.`,
          );
        }
      }
    }
    if (!senderId) {
      console.error('Skipping subscription reminders: no admin account exists to attribute system notifications to.');
      return;
    }

    const activeSubs = await Subscription.find({ status: 'active', subscribed: true, endDate: { $gte: now } });

    for (const subscription of activeSubs) {
      const daysLeft = Math.ceil((subscription.endDate - now) / (1000 * 60 * 60 * 24));

      if (subscription.autoRenew && daysLeft <= 1) {
        const result = await attemptWalletRenewal(subscription);
        if (result.ok) {
          await notifyUser(
            senderId,
            subscription.user,
            `Your "${result.plan.name}" subscription auto-renewed successfully and is now active until ${result.endDate.toDateString()}.`
          );
        } else {
          const reason = result.reason === 'plan_unavailable'
            ? 'the plan is no longer available'
            : 'your LenDen wallet balance was insufficient';
          await notifyUser(
            senderId,
            subscription.user,
            `We couldn't auto-renew your "${subscription.subscriptionPlan}" subscription because ${reason}. Please renew manually to keep your premium features.`
          );
        }
        continue;
      }

      if ([3, 1, 0].includes(daysLeft)) {
        const message = daysLeft === 0
          ? `Your "${subscription.subscriptionPlan}" subscription expires today. Renew now to keep your premium features.`
          : `Your "${subscription.subscriptionPlan}" subscription expires in ${daysLeft} day${daysLeft === 1 ? '' : 's'}. Renew now to avoid losing premium features.`;
        await notifyUser(senderId, subscription.user, message);
      }
    }
  } catch (error) {
    console.error('Error running subscription maintenance:', error);
  }
}

function initializeSubscriptionScheduler() {
  // Once a day, ahead of the existing midnight payment-reminder job.
  cron.schedule('0 1 * * *', () => {
    runSubscriptionMaintenance();
  });
}

module.exports = { initializeSubscriptionScheduler, runSubscriptionMaintenance };
