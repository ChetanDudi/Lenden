const crypto = require('crypto');
const mongoose = require('mongoose');
const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');
const RazorpayCapturedPayment = require('../models/razorpayCapturedPayment');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');

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

const getRazorpay = () => {
  const Razorpay = require('razorpay');
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new Error('Razorpay keys not configured. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in .env');
  }
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
};

// Non-secret payment config the app needs at runtime (e.g. the Payment Handle
// link for the manual-verification flow) — kept server-side so it can be
// changed without an app rebuild/store resubmission.
exports.getPaymentConfig = async (req, res) => {
  if (!process.env.RAZORPAY_PAYMENT_LINK) {
    return res.status(500).json({ error: 'Razorpay payment link not configured' });
  }
  res.json({ razorpayPaymentLink: process.env.RAZORPAY_PAYMENT_LINK });
};

// Create a Razorpay order for a subscription plan
exports.createOrder = async (req, res) => {
  const { planId } = req.body;

  if (!planId) return res.status(400).json({ error: 'planId is required' });

  try {
    const plan = await SubscriptionPlan.findById(planId);
    if (!plan || !plan.isAvailable) {
      return res.status(404).json({ error: 'Plan not found or unavailable' });
    }

    const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
    const amountInPaise = Math.round(actualPrice * 100);

    if (amountInPaise < 100) {
      return res.status(400).json({ error: 'Minimum payment amount is ₹1' });
    }

    const razorpay = getRazorpay();
    const order = await razorpay.orders.create({
      amount: amountInPaise,
      currency: 'INR',
      receipt: `lenden_${Date.now()}`,
      notes: {
        planId: plan._id.toString(),
        userId: req.user._id.toString(),
        planName: plan.name,
      },
    });

    res.json({
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: process.env.RAZORPAY_KEY_ID,
      plan: {
        id: plan._id.toString(),
        name: plan.name,
        duration: plan.duration,
        free: plan.free || 0,
        price: plan.price,
        discount: plan.discount || 0,
        actualPrice,
      },
    });
  } catch (error) {
    console.error('Error creating Razorpay order:', error);
    res.status(500).json({ error: 'Failed to create payment order' });
  }
};

// Verify Razorpay payment signature and activate subscription
exports.verifyPayment = async (req, res) => {
  const { razorpayOrderId, razorpayPaymentId, razorpaySignature, planId } = req.body;
  const userId = req.user._id;

  if (!razorpayOrderId || !razorpayPaymentId || !razorpaySignature || !planId) {
    return res.status(400).json({ error: 'Missing required payment verification fields' });
  }
  if (!process.env.RAZORPAY_KEY_SECRET) {
    return res.status(500).json({ error: 'Payment verification not configured' });
  }

  // Signature verification is pure crypto — safe outside the session
  const expectedSignature = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpayOrderId}|${razorpayPaymentId}`)
    .digest('hex');
  if (expectedSignature !== razorpaySignature) {
    return res.status(400).json({ error: 'Payment verification failed: signature mismatch' });
  }

  const plan = await SubscriptionPlan.findById(planId);
  if (!plan) return res.status(404).json({ error: 'Plan not found' });

  const session = await mongoose.startSession();
  let created;
  try {
    await session.withTransaction(async () => {
      // Fast-path replay check — catches the common case (same ID submitted
      // twice, not concurrently) without waiting on a duplicate-key error.
      // The actual race-proof guard is the partial unique index on
      // razorpayPaymentId (see models/subscription.js): if two requests for
      // the same payment ID run at the same instant, this check can pass for
      // both, but the loser's Subscription.create below will fail with a
      // duplicate-key error, caught below and mapped to the same 409.
      const alreadyUsed = await Subscription.findOne({ razorpayPaymentId }).session(session);
      if (alreadyUsed) throw Object.assign(new Error('Payment already applied'), { code: 'ALREADY_USED' });

      const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
      const subscribedDate = new Date();
      // Preserve remaining days if the user renews before their current sub expires
      const endDate = await calcEndDate(userId, plan, session);

      // Create first — if this fails (e.g. concurrent duplicate), nothing is expired
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
        razorpayOrderId,
        razorpayPaymentId,
        paymentMethod: 'razorpay',
      }], { session });

      // Expire old active subscriptions only after new one is safely inserted
      await Subscription.updateMany(
        { user: userId, status: 'active', _id: { $ne: created._id } },
        { $set: { status: 'expired' } },
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
  } catch (err) {
    if (err.code === 'ALREADY_USED' || err.code === 11000) return res.status(409).json({ error: 'Payment already applied' });
    console.error('Error verifying payment:', err);
    res.status(500).json({ error: 'Failed to activate subscription' });
  } finally {
    session.endSession();
  }
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
  } catch (err) {
    if (err.code === 'ALREADY_USED' || err.code === 11000) return res.status(409).json({ error: 'This payment has already been used to activate a subscription.' });
    console.error('Error verifying manual payment:', err);
    res.status(500).json({ error: 'Failed to activate subscription' });
  } finally {
    session.endSession();
  }
};

// Create Razorpay order for P2P settlement — payer pays LenDen, we credit recipient's wallet on verify
exports.createP2POrder = async (req, res) => {
  try {
    const { toEmail, amount, description, quickTransactionId, secureTransactionId } = req.body;
    if (!toEmail || !amount || amount < 100) {
      return res.status(400).json({ error: 'toEmail and amount (in paise, min 100) are required' });
    }
    const recipient = await User.findOne({ email: toEmail.toLowerCase().trim() });
    if (!recipient) {
      return res.status(404).json({ error: 'Recipient not found on LenDen' });
    }
    const razorpay = getRazorpay();
    const order = await razorpay.orders.create({
      amount,
      currency: 'INR',
      receipt: `p2p_${Date.now()}`,
      notes: {
        fromEmail: req.user.email,
        toEmail: toEmail.toLowerCase().trim(),
        type: 'p2p_payment',
        quickTransactionId: quickTransactionId || '',
        secureTransactionId: secureTransactionId || '',
        description: description || '',
      },
    });
    res.json({ orderId: order.id, amount: order.amount, currency: order.currency, keyId: process.env.RAZORPAY_KEY_ID });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Verify P2P payment — credits recipient's wallet and optionally clears the quick/secure transaction
exports.verifyP2PPayment = async (req, res) => {
  const { razorpayOrderId, razorpayPaymentId, razorpaySignature, quickTransactionId, secureTransactionId } = req.body;

  if (!razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
    return res.status(400).json({ error: 'Missing payment verification fields' });
  }

  // ── Step 1: verify Razorpay signature (before touching DB) ──────────────────
  const expected = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(`${razorpayOrderId}|${razorpayPaymentId}`)
    .digest('hex');
  if (expected !== razorpaySignature) {
    return res.status(400).json({ error: 'Payment verification failed: invalid signature' });
  }

  // ── Step 2: fetch payment details from Razorpay ──────────────────────────────
  const razorpay = getRazorpay();
  const payment = await razorpay.payments.fetch(razorpayPaymentId);
  const notes = payment.notes || {};
  const toEmail = notes.toEmail || req.body.toEmail;
  const amountInRupees = payment.amount / 100;

  const recipient = toEmail ? await User.findOne({ email: toEmail.toLowerCase().trim() }) : null;

  // ── Step 3: atomic DB writes inside a session ────────────────────────────────
  const session = await mongoose.startSession();
  try {
    await session.withTransaction(async () => {
      // Replay check inside the transaction — snapshot isolation prevents concurrent duplicates
      const alreadyUsed = await WalletTransaction.findOne({ razorpayPaymentId }).session(session);
      if (alreadyUsed) throw Object.assign(new Error('Payment already applied'), { code: 'ALREADY_USED' });

      if (recipient) {
        // Credit recipient's wallet
        await User.findByIdAndUpdate(
          recipient._id,
          { $inc: { walletBalance: amountInRupees } },
          { session }
        );
        // Payer debit record — carries razorpayPaymentId for replay prevention
        await WalletTransaction.create([{
          user: req.user._id,
          type: 'debit',
          amount: amountInRupees,
          toEmail: recipient.email,
          note: notes.description || 'P2P payment via Razorpay',
          razorpayOrderId,
          razorpayPaymentId,
        }], { session });
        // Recipient credit record — no razorpayPaymentId to avoid duplicate-key error
        // (the unique sparse index on razorpayPaymentId allows only one doc per payment ID)
        await WalletTransaction.create([{
          user: recipient._id,
          type: 'credit',
          amount: amountInRupees,
          fromEmail: req.user.email,
          note: notes.description || 'P2P payment received via Razorpay',
          razorpayOrderId,
        }], { session });
      }

      // Clear quick transaction
      const qtId = quickTransactionId || notes.quickTransactionId;
      if (qtId) {
        const qt = await QuickTransaction.findById(qtId).session(session);
        if (qt && qt.users.map(u => u.toLowerCase()).includes((req.user.email || '').toLowerCase())) {
          qt.cleared = true;
          qt.settlementStatus = 'accepted';
          qt.settlementRespondedBy = req.user.email;
          qt.settlementRespondedAt = new Date();
          qt.settledViaPayment = true;
          qt.paymentMethod = 'razorpay';
          await qt.save({ session });
        }
      }

      // Clear secure transaction
      const stId = secureTransactionId || notes.secureTransactionId;
      if (stId) {
        const st = await Transaction.findOne({ transactionId: stId }).session(session);
        if (st) {
          const payerEmail = (req.user.email || '').toLowerCase().trim();
          const payerIsUser = st.userEmail.toLowerCase() === payerEmail;
          const payerIsCounterparty = st.counterpartyEmail.toLowerCase() === payerEmail;
          if (payerIsUser || payerIsCounterparty) {
            let paidBy = 'borrower';
            if (st.role === 'lender') {
              paidBy = payerIsCounterparty ? 'borrower' : 'lender';
            } else {
              paidBy = payerIsUser ? 'borrower' : 'lender';
            }
            st.partialPayments.push({
              amount: amountInRupees,
              paidBy,
              paidAt: new Date(),
              description: 'Payment via Razorpay',
            });
            st.isPartiallyPaid = true;
            const totalPaid = st.partialPayments.reduce((sum, p) => sum + p.amount, 0);
            st.remainingAmount = Math.max(0, (st.amount || 0) - totalPaid);
            st.userCleared = true;
            st.counterpartyCleared = true;
            await st.save({ session });
          }
        }
      }
    });

    res.json({ message: 'Payment verified and settled', amount: amountInRupees });
  } catch (err) {
    if (err.code === 'ALREADY_USED') return res.status(409).json({ error: 'Payment already applied' });
    console.error('Error verifying P2P payment:', err);
    res.status(500).json({ error: 'Server error' });
  } finally {
    session.endSession();
  }
};

// Razorpay webhook endpoint — for server-side reliability (payment captured, failed, etc.)
exports.razorpayWebhook = async (req, res) => {
  // req.body is a raw Buffer here (express.raw middleware is applied in app.js before express.json)
  const rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.from(JSON.stringify(req.body));
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;

  if (webhookSecret) {
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
  }

  let event;
  try {
    event = JSON.parse(rawBody.toString('utf8'));
  } catch (_) {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  // Handle payment.captured — fallback if app-side verify call was lost
  if (event.event === 'payment.captured') {
    const payment = event.payload?.payment?.entity;
    if (payment) {
      const { order_id, id: paymentId } = payment;
      const notes = payment.notes || {};
      const { planId, userId } = notes;

      // Cache every captured payment so payments made via the no-notes Payment
      // Handle link (razorpay.me/@...) can later be looked up by verifyManualPayment
      // without needing the Payments Fetch API (which requires Live API keys).
      try {
        await RazorpayCapturedPayment.findOneAndUpdate(
          { paymentId },
          {
            paymentId,
            amount: payment.amount,
            currency: payment.currency,
            capturedAt: new Date(payment.created_at * 1000),
          },
          { upsert: true }
        );
      } catch (e) {
        console.error('[Webhook] Failed to cache captured payment:', e);
      }

      if (planId && userId) {
        const session = await mongoose.startSession();
        try {
          await session.withTransaction(async () => {
            const alreadyUsed = await Subscription.findOne({ razorpayPaymentId: paymentId }).session(session);
            if (alreadyUsed) return; // already applied, nothing to do

            const plan = await SubscriptionPlan.findById(planId).session(session);
            if (!plan) return;

            const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
            const subscribedDate = new Date();
            const endDate = await calcEndDate(userId, plan, session);

            const [created] = await Subscription.create([{
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
              razorpayOrderId: order_id,
              razorpayPaymentId: paymentId,
              paymentMethod: 'razorpay',
            }], { session });

            await Subscription.updateMany(
              { user: userId, status: 'active', _id: { $ne: created._id } },
              { $set: { status: 'expired' } },
              { session }
            );
          });
        } catch (e) {
          console.error('[Webhook] Failed to activate subscription via webhook:', e);
        } finally {
          session.endSession();
        }
      }
    }
  }

  res.json({ status: 'ok' });
};
