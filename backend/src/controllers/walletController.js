const crypto = require('crypto');
const mongoose = require('mongoose');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const SubscriptionPlan = require('../models/subscriptionPlan');
const Subscription = require('../models/subscription');
const RazorpayCapturedPayment = require('../models/razorpayCapturedPayment');
const Admin = require('../models/admin');
const { sendWalletPayOTP } = require('../utils/walletPayOtp');

const getRazorpay = () => {
  const Razorpay = require('razorpay');
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new Error('Razorpay keys not configured');
  }
  return new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
};

exports.getBalance = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('walletBalance');
    res.json({ balance: user?.walletBalance ?? 0 });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getHistory = async (req, res) => {
  try {
    const [txns, user] = await Promise.all([
      WalletTransaction.find({ user: req.user._id })
        .sort({ createdAt: -1 })
        .limit(50)
        .lean(),
      User.findById(req.user._id).select('walletBalance'),
    ]);

    // Compute running balance working backwards from current balance.
    // txns is newest-first, so txns[0] is the most recent transaction.
    // balanceAfter for txns[0] = current wallet balance.
    let runningBalance = user?.walletBalance ?? 0;
    const withBalance = txns.map(txn => {
      const balanceAfter = runningBalance;
      if (txn.type === 'credit' || txn.type === 'topup') {
        runningBalance -= txn.amount;
      } else { // debit, withdrawal
        runningBalance += txn.amount;
      }
      return { ...txn, balanceAfter };
    });

    res.json({ transactions: withBalance });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// ── Real-money wallet top-up via the Razorpay Payment Handle link ──────────────
// Exact mirror of paymentController.verifyManualPayment's pattern, for wallet
// credits instead of subscriptions: there is no order/signature for this product
// and no Fetch API access without Live keys, so we check the webhook-populated
// capture cache instead. There is deliberately only ONE verification path here
// (manual paste, same as the subscriptions flow) — an earlier version also had
// a background auto-poll racing against this endpoint, which could silently win
// the claim and leave the user staring at a stale "waiting" screen with no
// feedback, then see a confusing "already used" error if they verified manually.
// Single path = no race, exactly like the subscriptions manual-payment flow.
const MANUAL_TOPUP_MAX_AGE_SECONDS = 30 * 60;

exports.verifyManualTopUp = async (req, res) => {
  const { paymentId, amount } = req.body;
  if (!paymentId || !amount || Number(amount) <= 0) {
    return res.status(400).json({ error: 'paymentId and a positive amount are required' });
  }
  const expectedAmountInPaise = Math.round(Number(amount) * 100);

  // The Payment Handle link (razorpay.me/@...) has no API/notes support, so we
  // can't call payments.fetch (it also needs Live API keys). Instead we rely on
  // the Razorpay webhook having already cached this payment as captured — see
  // razorpayWebhook in paymentController.js, which upserts every payment.captured event.
  const payment = await RazorpayCapturedPayment.findOne({ paymentId: paymentId.trim() });
  if (!payment) {
    return res.status(404).json({ error: 'We have not received confirmation of this payment from Razorpay yet. Please wait a few seconds after paying and try again.' });
  }
  if (payment.currency !== 'INR') {
    return res.status(400).json({ error: 'Unexpected payment currency.' });
  }
  if (payment.amount !== expectedAmountInPaise) {
    return res.status(400).json({ error: `Payment amount does not match ₹${amount}.` });
  }
  // The Payment Handle link has no notes tying a payment to a user, so a
  // captured ID is redeemable by whoever submits it first. Cap how long it stays
  // claimable after capture to shrink the window for someone else's ID being reused.
  const paymentAgeSeconds = (Date.now() - payment.capturedAt.getTime()) / 1000;
  if (paymentAgeSeconds > MANUAL_TOPUP_MAX_AGE_SECONDS) {
    return res.status(400).json({ error: 'This payment is too old to verify. Please make a new payment and submit its ID right away.' });
  }

  const session = await mongoose.startSession();
  let addedAmount, newBalance;
  try {
    await session.withTransaction(async () => {
      // Fast-path check for the common case; the atomic claimed:false filter
      // below is what actually closes the race if two requests for the same
      // ID land at the same instant — see the duplicate-claim case in the catch block.
      const claimed = await RazorpayCapturedPayment.findOneAndUpdate(
        { _id: payment._id, claimed: false },
        { $set: { claimed: true, claimedBy: req.user._id, claimedFor: 'wallet_topup', claimedAt: new Date() } },
        { session }
      );
      if (!claimed) throw Object.assign(new Error('Payment already applied'), { code: 'ALREADY_USED' });

      addedAmount = claimed.amount / 100;
      await WalletTransaction.create([{
        user: req.user._id,
        type: 'topup',
        amount: addedAmount,
        note: 'Wallet top-up via Razorpay',
        razorpayPaymentId: claimed.paymentId,
      }], { session });

      const updatedUser = await User.findByIdAndUpdate(
        req.user._id,
        { $inc: { walletBalance: addedAmount } },
        { new: true, session }
      );
      newBalance = updatedUser.walletBalance;
    });

    res.json({ message: 'Wallet topped up', addedAmount, balance: newBalance });
  } catch (err) {
    if (err.code === 'ALREADY_USED' || err.code === 11000) return res.status(409).json({ error: 'This payment has already been used.' });
    console.error('Error verifying manual top-up:', err);
    res.status(500).json({ error: 'Failed to top up wallet' });
  } finally {
    session.endSession();
  }
};

// Transfer between wallets
// ACID guarantees:
//   Atomicity  — session.withTransaction wraps debit + credit + both records; all or nothing
//   Consistency — conditional debit (walletBalance >= amount) prevents overdraft atomically
//   Isolation  — MongoDB snapshot isolation within the session prevents concurrent reads
//   Durability — committed session writes are persisted before response is sent
exports.pay = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { to, amount, note } = req.body;
    if (!to || !amount || amount <= 0) {
      return res.status(400).json({ error: 'to (email) and a positive amount are required' });
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
      return res.status(400).json({ error: 'Invalid recipient email address' });
    }

    // Resolve recipient outside the transaction — read-only, no consistency risk
    const receiver = await User.findOne({ email: to.toLowerCase().trim() }).select('_id email');
    if (!receiver) return res.status(404).json({ error: 'Recipient not found on LenDen' });

    let newBalance;
    await session.withTransaction(async () => {
      // Atomic check-and-debit: the $gte condition and $inc happen in one document-level operation.
      // If another concurrent request already drained the balance, this returns null instead of
      // executing the $inc, so we never overdraft regardless of request ordering.
      const sender = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount } },
        { new: true, session }
      );
      if (!sender) {
        throw Object.assign(new Error('Insufficient wallet balance'), { status: 400, userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.' });
      }
      if (sender._id.equals(receiver._id)) {
        throw Object.assign(new Error('Cannot pay yourself'), { status: 400 });
      }

      await User.findByIdAndUpdate(receiver._id, { $inc: { walletBalance: amount } }, { session });

      await WalletTransaction.create([
        { user: sender._id, type: 'debit',  amount, toEmail: receiver.email, note: note || 'Wallet transfer' },
        { user: receiver._id, type: 'credit', amount, fromEmail: sender.email, note: note || 'Wallet transfer' },
      ], { session });

      newBalance = sender.walletBalance; // already decremented by findOneAndUpdate with {new:true}
    });

    res.json({ message: 'Payment successful', balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};

// Shared recipient checks for "Pay User" — format, exists on LenDen, isn't the
// sender themselves, and isn't an admin account (Admin is a separate login/
// collection from User, but the same email could in theory be used for both,
// so block by email rather than assuming the two are mutually exclusive).
const validateRecipient = async (toRaw, sender) => {
  const to = (toRaw || '').toLowerCase().trim();
  if (!to || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
    throw Object.assign(new Error('Invalid recipient email'), { status: 400, userMessage: 'Invalid recipient email address' });
  }
  if (to === (sender.email || '').toLowerCase().trim()) {
    throw Object.assign(new Error('Cannot pay yourself'), { status: 400, userMessage: 'You cannot pay yourself.' });
  }
  const [receiver, adminMatch] = await Promise.all([
    User.findOne({ email: to }).select('_id email'),
    Admin.findOne({ email: to }).select('_id'),
  ]);
  if (!receiver) {
    throw Object.assign(new Error('Recipient not found'), { status: 404, userMessage: 'Recipient not found on LenDen' });
  }
  if (adminMatch) {
    throw Object.assign(new Error('Cannot pay an admin'), { status: 400, userMessage: 'This email belongs to an admin account and cannot receive wallet payments.' });
  }
  return receiver;
};

// ── Pay User OTP gate ───────────────────────────────────────────────────────
// The "Pay User" sheet sends an OTP to the logged-in sender's own registered
// email before allowing the transfer, so the wallet can't be drained just from
// a stolen/left-open session. Pattern mirrors settingsController's altEmailOTP.
exports.sendPayOtp = async (req, res) => {
  try {
    const { to } = req.body;
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    try {
      await validateRecipient(to, user);
    } catch (err) {
      return res.status(err.status ?? 400).json({ error: err.userMessage || 'Invalid recipient' });
    }

    const now = new Date();
    const existing = user.walletPayOTP;

    if (existing?.sentAt && (now - existing.sentAt) < 60 * 1000) {
      const secondsLeft = Math.ceil((60 * 1000 - (now - existing.sentAt)) / 1000);
      return res.status(429).json({ error: `Please wait ${secondsLeft} seconds before requesting another OTP` });
    }
    const hourAgo = new Date(now - 60 * 60 * 1000);
    const windowStart = existing?.windowStart && existing.windowStart > hourAgo ? existing.windowStart : now;
    const attemptCount = existing?.windowStart && existing.windowStart > hourAgo ? (existing.attemptCount || 0) : 0;
    if (attemptCount >= 5) {
      return res.status(429).json({ error: 'Too many OTP requests. Please try again in an hour.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpExpiry = new Date(Date.now() + 2 * 60 * 1000);

    user.walletPayOTP = { code: otp, expiry: otpExpiry, sentAt: now, attemptCount: attemptCount + 1, windowStart };
    await user.save();

    await sendWalletPayOTP(user.email, otp, user.name);

    res.json({ message: 'OTP sent to your registered email', email: user.email });
  } catch (err) {
    console.error('Error sending wallet pay OTP:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Verifies the sender's OTP and performs the wallet-to-wallet transfer in one step.
// Mirrors pay()'s ACID transfer logic exactly, with an OTP check gating entry.
exports.payToUserWithOtp = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { to, amount, note, otp } = req.body;
    if (!to || !amount || amount <= 0) {
      return res.status(400).json({ error: 'to (email) and a positive amount are required' });
    }
    if (!otp || !/^\d{6}$/.test(otp)) {
      return res.status(400).json({ error: 'A valid 6-digit OTP is required' });
    }

    const senderDoc = await User.findById(req.user._id);
    if (!senderDoc) return res.status(404).json({ error: 'User not found' });
    if (!senderDoc.walletPayOTP || senderDoc.walletPayOTP.code !== otp) {
      return res.status(400).json({ error: 'Invalid OTP' });
    }
    if (new Date() > senderDoc.walletPayOTP.expiry) {
      return res.status(400).json({ error: 'OTP has expired. Please request a new one.' });
    }

    const receiver = await validateRecipient(to, senderDoc);

    let newBalance;
    await session.withTransaction(async () => {
      const sender = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount }, $unset: { walletPayOTP: 1 } },
        { new: true, session }
      );
      if (!sender) {
        throw Object.assign(new Error('Insufficient wallet balance'), { status: 400, userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.' });
      }

      await User.findByIdAndUpdate(receiver._id, { $inc: { walletBalance: amount } }, { session });

      await WalletTransaction.create([
        { user: sender._id, type: 'debit',  amount, toEmail: receiver.email, note: note || 'Wallet transfer' },
        { user: receiver._id, type: 'credit', amount, fromEmail: sender.email, note: note || 'Wallet transfer' },
      ], { session });

      newBalance = sender.walletBalance;
    });

    res.json({ message: 'Payment successful', balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};

// QR-based wallet payment — same ACID logic as pay() but accepts toUserId instead of email
exports.qrPay = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { toUserId, amount, note } = req.body;
    if (!toUserId) return res.status(400).json({ error: 'toUserId is required.' });
    if (!amount || Number(amount) <= 0) return res.status(400).json({ error: 'A positive amount is required.' });

    const parsedAmount = Number(amount);
    const receiver = await User.findById(toUserId).select('_id email');
    if (!receiver) return res.status(404).json({ error: 'Recipient not found on LenDen.' });

    let newBalance;
    await session.withTransaction(async () => {
      const sender = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: parsedAmount } },
        { $inc: { walletBalance: -parsedAmount } },
        { new: true, session }
      );
      if (!sender) throw Object.assign(new Error('Insufficient wallet balance'), { status: 400, userMessage: 'Insufficient wallet balance.' });
      if (sender._id.equals(receiver._id)) throw Object.assign(new Error('Cannot pay yourself'), { status: 400, userMessage: 'Cannot pay yourself.' });

      await User.findByIdAndUpdate(receiver._id, { $inc: { walletBalance: parsedAmount } }, { session });
      await WalletTransaction.create([
        { user: sender._id, type: 'debit',  amount: parsedAmount, toEmail: receiver.email, note: note || 'QR Payment' },
        { user: receiver._id, type: 'credit', amount: parsedAmount, fromEmail: sender.email, note: note || 'QR Payment' },
      ], { session });

      newBalance = sender.walletBalance;
    });

    res.json({ message: 'QR payment successful', balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};

// ── UPI QR scan payments ──────────────────────────────────────────────────────

// Create Razorpay order when user wants to pay a shop's UPI QR via Razorpay
exports.createQrOrder = async (req, res) => {
  try {
    const { amount, upiId, payeeName } = req.body;
    if (!amount || Number(amount) < 1)
      return res.status(400).json({ error: 'Minimum payment amount is ₹1.' });

    const razorpay = getRazorpay();
    const order = await razorpay.orders.create({
      amount: Math.round(Number(amount) * 100), // paise
      currency: 'INR',
      receipt: `qr_${Date.now()}`,
      notes: {
        userId: req.user._id.toString(),
        upiId: upiId || '',
        payeeName: payeeName || '',
        type: 'qr_scan_payment',
      },
    });
    res.json({
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: process.env.RAZORPAY_KEY_ID,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Verify Razorpay QR payment signature and record the debit transaction
exports.verifyQrPayment = async (req, res) => {
  try {
    const { razorpayOrderId, razorpayPaymentId, razorpaySignature, amount, payeeName, upiId, note } = req.body;
    if (!razorpayOrderId || !razorpayPaymentId || !razorpaySignature)
      return res.status(400).json({ error: 'Missing payment fields.' });

    const expected = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpayOrderId}|${razorpayPaymentId}`)
      .digest('hex');
    if (expected !== razorpaySignature)
      return res.status(400).json({ error: 'Signature mismatch.' });

    await WalletTransaction.create({
      user: req.user._id,
      type: 'debit',
      amount: Number(amount),
      toEmail: upiId || 'external-upi',
      note: note || `QR Payment to ${payeeName || 'Shop'}`,
      razorpayOrderId,
      razorpayPaymentId,
    });

    res.json({ message: 'Payment verified and recorded.' });
  } catch (err) {
    if (err.code === 11000)
      return res.status(409).json({ error: 'Payment already recorded.' });
    res.status(500).json({ error: 'Server error' });
  }
};

// Pay a shop's UPI QR directly from LenDen wallet (balance deducted; no real UPI transfer)
exports.payUpiQr = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { amount, upiId, payeeName, note } = req.body;
    if (!amount || Number(amount) <= 0)
      return res.status(400).json({ error: 'A positive amount is required.' });

    const parsedAmount = Number(amount);
    let newBalance;
    await session.withTransaction(async () => {
      const user = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: parsedAmount } },
        { $inc: { walletBalance: -parsedAmount } },
        { new: true, session }
      );
      if (!user)
        throw Object.assign(new Error('Insufficient balance'), {
          status: 400, userMessage: 'Insufficient wallet balance.',
        });

      await WalletTransaction.create([{
        user: req.user._id,
        type: 'debit',
        amount: parsedAmount,
        toEmail: upiId || 'external-upi',
        note: note || `QR Payment to ${payeeName || 'Shop'}`,
      }], { session });

      newBalance = user.walletBalance;
    });

    res.json({ message: 'Payment successful', balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};

// Pay for a subscription plan using wallet balance
exports.paySubscription = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { planId } = req.body;
    if (!planId) return res.status(400).json({ error: 'planId is required' });

    const plan = await SubscriptionPlan.findById(planId);
    if (!plan || !plan.isAvailable) return res.status(404).json({ error: 'Plan not found or unavailable' });

    const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));

    let newBalance;
    await session.withTransaction(async () => {
      // Atomic check-and-debit — prevents overdraft even under concurrent requests
      const user = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: actualPrice } },
        { $inc: { walletBalance: -actualPrice } },
        { new: true, session }
      );
      if (!user) throw Object.assign(new Error('Insufficient wallet balance'), { status: 400, userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.' });

      await WalletTransaction.create([{
        user: req.user._id,
        type: 'debit',
        amount: actualPrice,
        note: `${plan.name} Subscription via LenDen Wallet`,
      }], { session });

      // Preserve remaining days if renewing before current subscription ends
      const currentActive = await Subscription.findOne({ user: req.user._id, status: 'active' }, null, { session });
      const now = new Date();
      const startFrom = (currentActive && currentActive.endDate > now) ? currentActive.endDate : now;
      const endDate = new Date(startFrom);
      endDate.setDate(endDate.getDate() + plan.duration + (plan.free || 0));

      // Create new subscription first — safe to expire old ones only after this succeeds
      const [created] = await Subscription.create([{
        user: req.user._id,
        subscribed: true,
        subscriptionPlan: plan.name,
        duration: plan.duration,
        price: plan.price,
        discount: plan.discount || 0,
        actualPrice,
        free: plan.free || 0,
        subscribedDate: now,
        endDate,
        status: 'active',
        paymentMethod: 'wallet',
      }], { session });

      await Subscription.updateMany(
        { user: req.user._id, status: 'active', _id: { $ne: created._id } },
        { $set: { status: 'expired' } },
        { session }
      );

      newBalance = user.walletBalance;
    });

    res.json({ message: 'Subscription activated via wallet', balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};
