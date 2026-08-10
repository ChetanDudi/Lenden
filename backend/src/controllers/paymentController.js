const crypto = require('crypto');
const mongoose = require('mongoose');
const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');
const RazorpayCapturedPayment = require('../models/razorpayCapturedPayment');
const User = require('../models/user');
const Notification = require('../models/notification');
const { sendToUser } = require('../services/notificationService');

// Returns the endDate for a new subscription, preserving any remaining days
// if the user renews before their current subscription expires.
async function calcEndDate(userId, plan, sessionArg) {
  const opts = sessionArg ? { session: sessionArg } : {};
  const currentActive = await Subscription.findOne({ user: userId, status: 'active' }, null, opts);
  const now = new Date();
  const startFrom = (currentActive && currentActive.endDate > now) ? currentActive.endDate : now;
  const end = new Date(startFrom);
  end.setDate(end.getDate() + plan.duration + (plan.free || 0));
  return end;
}

// Non-secret payment config the app needs at runtime (e.g. the Payment Handle
// link for the manual-verification flow) — kept server-side so it can be
// changed without an app rebuild/store resubmission.
exports.getPaymentConfig = async (req, res) => {
  if (!process.env.RAZORPAY_PAYMENT_LINK) {
    return res.status(500).json({ error: 'Razorpay payment link not configured' });
  }
  res.json({ razorpayPaymentLink: process.env.RAZORPAY_PAYMENT_LINK });
};

// Verify a payment made directly via the standalone Razorpay Payment Handle
// link (razorpay.me/@...) instead of the in-app Checkout flow. There is no
// order/signature for this product and no Fetch API access without Live
// keys, so instead we check the webhook-populated capture cache for this
// payment's amount/currency/age before activating — same replay-protected
// create pattern as verifyPayment above.
exports.verifyManualPayment = async (req, res) => {
  const { paymentId, planId } = req.body;
  const userId = req.user._id;

  if (!paymentId || !planId) {
    return res.status(400).json({ error: 'paymentId and planId are required' });
  }

  const plan = await SubscriptionPlan.findById(planId);
  if (!plan || !plan.isAvailable) {
    return res.status(404).json({ error: 'Plan not found or unavailable' });
  }

  const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
  const expectedAmountInPaise = Math.round(actualPrice * 100);

  // The Payment Handle link (razorpay.me/@...) has no API/notes support, so we
  // can't call payments.fetch (it also needs Live API keys, which individual
  // accounts may not be able to obtain). Instead we rely on the Razorpay
  // webhook having already cached this payment as captured — see
  // razorpayWebhook below, which upserts every payment.captured event.
  const payment = await RazorpayCapturedPayment.findOne({ paymentId: paymentId.trim() });
  if (!payment) {
    return res.status(404).json({ error: 'We have not received confirmation of this payment from Razorpay yet. Please wait a few seconds after paying and try again.' });
  }
  if (payment.currency !== 'INR') {
    return res.status(400).json({ error: 'Unexpected payment currency.' });
  }
  if (payment.amount !== expectedAmountInPaise) {
    return res.status(400).json({ error: `Payment amount does not match the ₹${actualPrice} plan price.` });
  }
  // The Payment Handle link has no notes tying a payment to a user, so a
  // captured ID is redeemable by whoever submits it first. Cap how long it stays
  // claimable after capture to shrink the window for someone else's ID being reused.
  const paymentAgeSeconds = (Date.now() - payment.capturedAt.getTime()) / 1000;
  if (paymentAgeSeconds > 30 * 60) {
    return res.status(400).json({ error: 'This payment is too old to verify. Please make a new payment and submit its ID right away.' });
  }

  const session = await mongoose.startSession();
  let created;
  try {
    await session.withTransaction(async () => {
      // Fast-path check for the common case; the partial unique index on
      // razorpayPaymentId (models/subscription.js) is what actually closes
      // the race if two requests for the same ID land at the same instant —
      // see the catch block below for the duplicate-key (code 11000) case.
      const alreadyUsed = await Subscription.findOne({ razorpayPaymentId: paymentId }).session(session);
      if (alreadyUsed) throw Object.assign(new Error('Payment already applied'), { code: 'ALREADY_USED' });

      const subscribedDate = new Date();
      const endDate = await calcEndDate(userId, plan, session);

      [created] = await Subscription.create([{
        user: userId,
        subscribed: true,
        subscriptionPlan: plan.name,
        duration: plan.duration,
        price: plan.price,
        discount: plan.discount || 0,
        actualPrice,
        free: plan.free || 0,
        subscribedDate,
        endDate,
        status: 'active',
        razorpayPaymentId: paymentId,
        paymentMethod: 'razorpay_manual',
      }], { session });

      await Subscription.updateMany(
        { user: userId, status: 'active', _id: { $ne: created._id } },
        { $set: { status: 'expired' } },
        { session }
      );

      // Mark the capture as claimed so it can't also be redeemed for a wallet top-up.
      await RazorpayCapturedPayment.updateOne(
        { paymentId: payment.paymentId },
        { $set: { claimed: true, claimedBy: userId, claimedFor: 'subscription', claimedAt: new Date() } },
        { session }
      );
    });

    res.json({
      message: 'Payment verified and subscription activated',
      subscription: {
        subscriptionPlan: created.subscriptionPlan,
        subscribedDate: created.subscribedDate,
        endDate: created.endDate,
        duration: created.duration,
        free: created.free,
        paymentMethod: created.paymentMethod,
      },
    });

    Promise.resolve().then(async () => {
      const u = await User.findById(userId).select('name email notificationSettings').lean();
      if (u?.notificationSettings?.subscriptionNotifications !== false) {
        await Notification.create({
          sender: userId, senderModel: 'User', recipientType: 'specific-users',
          recipients: [userId], recipientModel: 'User', category: 'subscription',
          message: `Your "${created.subscriptionPlan}" subscription is now active until ${created.endDate.toLocaleDateString()}.`,
        });
        sendToUser(User, userId, {
          title: 'Subscription Activated 🎉',
          body: `Your "${created.subscriptionPlan}" plan is now active.`,
          data: { type: 'subscription_activated' },
        });
      }
      // Also notify all admins
      await Notification.create({
        sender: userId, senderModel: 'User',
        recipientType: 'all-admins', recipientModel: 'Admin',
        category: 'subscription',
        message: `New subscription: "${created.subscriptionPlan}" purchased by ${u?.name || u?.email || 'a user'} for ₹${created.actualPrice} (Payment ID: ${paymentId}).`,
        deliveryStatus: 'sent',
        sentAt: new Date(),
      });
    }).catch(() => {});
  } catch (err) {
    if (err.code === 'ALREADY_USED' || err.code === 11000) return res.status(409).json({ error: 'This payment has already been used to activate a subscription.' });
    console.error('Error verifying manual payment:', err);
    res.status(500).json({ error: 'Failed to activate subscription' });
  } finally {
    session.endSession();
  }
};

// Razorpay webhook endpoint — for server-side reliability (payment captured, failed, etc.)
exports.razorpayWebhook = async (req, res) => {
  // req.body is a raw Buffer here (express.raw middleware is applied in app.js before express.json)
  const rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.from(JSON.stringify(req.body));
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!webhookSecret) {
    console.error('[Webhook] RAZORPAY_WEBHOOK_SECRET is not set — rejecting unsigned webhook');
    return res.status(500).json({ error: 'Webhook secret not configured' });
  }

  const signature = req.headers['x-razorpay-signature'];
  if (!signature) {
    return res.status(400).json({ error: 'Missing x-razorpay-signature header' });
  }
  const expectedSignature = crypto
    .createHmac('sha256', webhookSecret)
    .update(rawBody)
    .digest('hex');
  if (signature !== expectedSignature) {
    return res.status(400).json({ error: 'Invalid webhook signature' });
  }

  let event;
  try {
    event = JSON.parse(rawBody.toString('utf8'));
  } catch (_) {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  // Cache every captured payment so payments made via the no-notes Payment
  // Handle link (razorpay.me/@...) can later be looked up by verifyManualPayment
  // / the wallet top-up verify endpoint, without needing the Payments Fetch API
  // (Live keys only).
  if (event.event === 'payment.captured') {
    const payment = event.payload?.payment?.entity;
    if (payment) {
      try {
        // setDefaultsOnInsert is required here: without it, a brand-new document
        // is inserted with only the $set fields below, so schema defaults like
        // claimed:false are never physically written. Mongoose still *displays*
        // claimed:false on read (hydration applies the default in memory), which
        // masks the gap — but a raw query filter like { claimed: false } used by
        // the wallet top-up's atomic claim won't match a document where the field
        // is genuinely absent, so it falsely looks "already used" on first verify.
        await RazorpayCapturedPayment.findOneAndUpdate(
          { paymentId: payment.id },
          {
            $set: {
              paymentId: payment.id,
              amount: payment.amount,
              currency: payment.currency,
              capturedAt: new Date(payment.created_at * 1000),
            },
            $setOnInsert: { claimed: false },
          },
          { upsert: true, setDefaultsOnInsert: true }
        );
      } catch (e) {
        console.error('[Webhook] Failed to cache captured payment:', e);
      }
    }
  }

  res.json({ status: 'ok' });
};
