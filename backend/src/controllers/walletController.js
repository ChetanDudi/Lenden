const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const SubscriptionPlan = require('../models/subscriptionPlan');
const Subscription = require('../models/subscription');
const RazorpayCapturedPayment = require('../models/razorpayCapturedPayment');
const Admin = require('../models/admin');
const { sendWalletPayOTP, sendWalletPinSetupOTP } = require('../utils/walletPayOtp');
const Notification = require('../models/notification');

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
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip = (page - 1) * limit;
    const { type, startDate, endDate, search } = req.query;

    const filter = { user: req.user._id };
    if (type && type !== 'all') filter.type = type;
    if (startDate || endDate) {
      filter.createdAt = {};
      if (startDate) filter.createdAt.$gte = new Date(startDate);
      if (endDate) filter.createdAt.$lte = new Date(endDate);
    }
    if (search && search.trim()) {
      const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      filter.$or = [{ note: sr }, { description: sr }, { fromEmail: sr }, { toEmail: sr }];
    }

    const [txns, total, user] = await Promise.all([
      WalletTransaction.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean(),
      WalletTransaction.countDocuments(filter),
      User.findById(req.user._id).select('walletBalance'),
    ]);

    // Compute running balance for this page. txns is newest-first.
    // balanceAfter for txns[0] = wallet balance minus net change of ALL
    // transactions newer than txns[0] (regardless of type filter so the
    // balance is always the true wallet state at that moment).
    const currentBalance = user?.walletBalance ?? 0;
    let startingBalance = currentBalance;
    if (txns.length > 0) {
      const newerAgg = await WalletTransaction.aggregate([
        { $match: { user: req.user._id, createdAt: { $gt: txns[0].createdAt } } },
        { $group: { _id: null, net: { $sum: {
          $cond: [{ $in: ['$type', ['credit', 'topup']] }, '$amount', { $multiply: ['$amount', -1] }]
        } } } },
      ]);
      startingBalance = currentBalance - (newerAgg[0]?.net ?? 0);
    }

    let runningBalance = startingBalance;
    const withBalance = txns.map(txn => {
      const balanceAfter = runningBalance;
      if (txn.type === 'credit' || txn.type === 'topup') {
        runningBalance -= txn.amount;
      } else {
        runningBalance += txn.amount;
      }
      return { ...txn, balanceAfter };
    });

    res.json({
      transactions: withBalance,
      total,
      page,
      totalPages: Math.ceil(total / limit),
      limit,
    });
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

  const session = await mongoose.startSession();
  let addedAmount, newBalance;
  try {
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

    // Fire-and-forget: notify sender and receiver after successful transfer
    Promise.all([
      User.findById(req.user._id).select('notificationSettings'),
      User.findById(receiver._id).select('notificationSettings'),
    ]).then(([senderUser, receiverUser]) => {
      const notifs = [];
      if (senderUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
          message: `Payment of ₹${amount} sent to ${receiver.email} successfully.`,
        }));
      }
      if (receiverUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [receiver._id], recipientModel: 'User', category: 'transaction',
          message: `You received ₹${amount} from ${req.user.email}.`,
        }));
      }
      return Promise.all(notifs);
    }).catch(() => {});

    res.json({ message: 'Payment successful', balance: newBalance });
  } catch (err) {
    if (err.message === 'Insufficient wallet balance') {
      User.findById(req.user._id).select('notificationSettings').then(u => {
        if (u?.notificationSettings?.transactionNotifications !== false) {
          return Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
            message: 'Payment failed: Insufficient LenDen wallet balance.',
          });
        }
      }).catch(() => {});
    }
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

    // 60-second cooldown
    if (user.walletPayOTP?.sentAt) {
      const elapsed = (now - new Date(user.walletPayOTP.sentAt)) / 1000;
      if (elapsed < 60) {
        return res.status(429).json({
          error: `Please wait ${Math.ceil(60 - elapsed)} seconds before requesting another OTP.`,
        });
      }
    }

    // 5 sends per hour cap
    const windowStart = user.walletPayOTP?.windowStart;
    const withinWindow = windowStart && (now - new Date(windowStart)) < 60 * 60 * 1000;
    const attemptCount = withinWindow ? (user.walletPayOTP.attemptCount || 0) : 0;
    if (attemptCount >= 5) {
      return res.status(429).json({ error: 'Too many OTP requests. Please try again later.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpExpiry = new Date(Date.now() + 2 * 60 * 1000);

    user.walletPayOTP = {
      code: otp,
      expiry: otpExpiry,
      sentAt: now,
      attemptCount: attemptCount + 1,
      windowStart: withinWindow ? windowStart : now,
    };
    await user.save();

    await sendWalletPayOTP(user.email, otp, user.name);

    res.json({ message: 'OTP sent to your registered email', email: user.email });
  } catch (err) {
    console.error('Error sending wallet pay OTP:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Generic OTP send for wallet payment auth (no recipient validation — just
// sends a fresh OTP to the logged-in user's own email so they can prove they
// are the one initiating the payment). Used by _PaymentSheet and any other
// outgoing-payment UI that doesn't already have a dedicated send-otp route.
exports.sendWalletAuthOtp = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    const now = new Date();

    // 60-second cooldown
    if (user.walletPayOTP?.sentAt) {
      const elapsed = (now - new Date(user.walletPayOTP.sentAt)) / 1000;
      if (elapsed < 60) {
        return res.status(429).json({
          error: `Please wait ${Math.ceil(60 - elapsed)} seconds before requesting another OTP.`,
        });
      }
    }

    // 5 sends per hour cap
    const windowStart = user.walletPayOTP?.windowStart;
    const withinWindow = windowStart && (now - new Date(windowStart)) < 60 * 60 * 1000;
    const attemptCount = withinWindow ? (user.walletPayOTP.attemptCount || 0) : 0;
    if (attemptCount >= 5) {
      return res.status(429).json({ error: 'Too many OTP requests. Please try again later.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpExpiry = new Date(Date.now() + 2 * 60 * 1000);

    user.walletPayOTP = {
      code: otp,
      expiry: otpExpiry,
      sentAt: now,
      attemptCount: attemptCount + 1,
      windowStart: withinWindow ? windowStart : now,
    };
    await user.save();

    await sendWalletPinSetupOTP(user.email, otp, user.name);
    res.json({ message: 'OTP sent to your registered email', email: user.email });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// ── Wallet Transaction PIN management ────────────────────────────────────────
// PIN lets users skip the email OTP wait on every outgoing payment. Set once
// in Settings; verified server-side via bcrypt on each payment.

exports.getWalletPinStatus = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('walletPin walletPinLockedUntil');
    if (!user) return res.status(404).json({ error: 'User not found' });
    const lockedUntil = user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()
      ? user.walletPinLockedUntil : null;
    res.json({ hasPin: !!user.walletPin, lockedUntil });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

const validateWalletOtp = (user, otp) => {
  if (!otp) {
    return { ok: false, error: 'Email OTP is required.' };
  }
  if (!user.walletPayOTP?.code) {
    return { ok: false, error: 'No OTP is pending. Please request a new OTP first.' };
  }
  if (user.walletPayOTP.code !== String(otp)) {
    return { ok: false, error: 'Invalid OTP.' };
  }
  if (new Date() > new Date(user.walletPayOTP.expiry)) {
    return { ok: false, error: 'OTP has expired. Please request a new one.' };
  }
  return { ok: true };
};

exports.verifyWalletOtp = async (req, res) => {
  try {
    const { otp } = req.body;
    const user = await User.findById(req.user._id).select('walletPayOTP');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const validation = validateWalletOtp(user, otp);
    if (!validation.ok) {
      return res.status(400).json({ error: validation.error });
    }

    // Mark the pending walletPayOTP as verified so the subsequent PIN set
    // request can consume it. We avoid removing the OTP here because the
    // frontend flow verifies the code first then calls /wallet/pin/set — if
    // the OTP is removed on verify, the later set call will find no pending
    // OTP and fail with "No OTP is pending". Keep the code+expiry and add
    // a verified flag which setWalletPin will accept.
    user.walletPayOTP = {
      ...(user.walletPayOTP || {}),
      verified: true,
    };
    await user.save();
    res.json({ verified: true, message: 'OTP verified successfully.' });
  } catch (err) {
    console.error('Error verifying wallet OTP:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Set or change the wallet transaction PIN.
//
// Three distinct paths — never mixing PIN + OTP in the same request:
//   1. First time (no existing PIN): email OTP only → set new PIN
//   2. Normal change (knows current PIN): current PIN only → set new PIN
//   3. Forgot PIN reset: email OTP only → overwrite PIN (no current PIN needed)
exports.setWalletPin = async (req, res) => {
  try {
    const { newPin, currentPin, otp } = req.body;
    if (!newPin || !/^\d{6}$/.test(newPin)) {
      return res.status(400).json({ error: 'PIN must be exactly 6 digits.' });
    }

    const user = await User.findById(req.user._id).select(
      'walletPin walletPinAttempts walletPinLockedUntil walletPayOTP'
    );
    if (!user) return res.status(404).json({ error: 'User not found' });

    if (!user.walletPin) {
      // ── Path 1: first time — email OTP required ───────────────────────
      const validation = validateWalletOtp(user, otp);
      if (!validation.ok) {
        return res.status(400).json({ error: validation.error || 'Email OTP is required to set your PIN for the first time.' });
      }
    } else if (currentPin) {
      // ── Path 2: normal change — current PIN only ──────────────────────
      if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
        const mins = Math.ceil((user.walletPinLockedUntil - Date.now()) / 60000);
        return res.status(423).json({ error: `PIN is locked. Try again in ${mins} minute${mins === 1 ? '' : 's'}.` });
      }
      const valid = await bcrypt.compare(String(currentPin), user.walletPin);
      if (!valid) {
        const newAttempts = (user.walletPinAttempts || 0) + 1;
        const lockUpdate = newAttempts >= 5
          ? { walletPinAttempts: 0, walletPinLockedUntil: new Date(Date.now() + 15 * 60 * 1000) }
          : { walletPinAttempts: newAttempts };
        await User.updateOne({ _id: user._id }, { $set: lockUpdate });
        const left = 5 - newAttempts;
        if (left <= 0) return res.status(423).json({ error: 'Too many wrong PINs. Locked for 15 minutes.' });
        return res.status(400).json({ error: `Incorrect PIN. ${left} attempt${left === 1 ? '' : 's'} remaining.` });
      }
    } else if (otp) {
      // ── Path 3: forgot PIN — email OTP only ──────────────────────────
      const validation = validateWalletOtp(user, otp);
      if (!validation.ok) {
        return res.status(400).json({ error: validation.error || 'Email OTP is required to reset your PIN.' });
      }
    } else {
      return res.status(400).json({ error: 'Either your current PIN or an email OTP is required.' });
    }

    user.walletPin = await bcrypt.hash(String(newPin), 10);
    user.walletPinAttempts = 0;
    user.walletPinLockedUntil = null;
    user.walletPayOTP = undefined;
    await user.save();

    res.json({ message: 'Transaction PIN updated successfully.' });

    User.findById(req.user._id).select('privacySettings').then(u => {
      if (u?.privacySettings?.loginNotifications !== false) {
        return Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'system',
          message: "Your transaction PIN was updated. If this wasn't you, contact support immediately.",
        });
      }
    }).catch(() => {});
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Remove the wallet PIN. Requires the current PIN only — no OTP needed since
// the user must already know their PIN to remove it. (If they forgot it, they
// should use the "Forgot PIN" reset flow to set a new one first.)
exports.removeWalletPin = async (req, res) => {
  try {
    const { currentPin } = req.body;
    if (!currentPin) {
      return res.status(400).json({ error: 'Current PIN is required to remove it.' });
    }

    const user = await User.findById(req.user._id).select(
      'walletPin walletPinAttempts walletPinLockedUntil'
    );
    if (!user) return res.status(404).json({ error: 'User not found' });
    if (!user.walletPin) {
      return res.status(400).json({ error: 'No PIN is currently set.' });
    }
    if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
      const mins = Math.ceil((user.walletPinLockedUntil - Date.now()) / 60000);
      return res.status(423).json({ error: `PIN is locked. Try again in ${mins} minute${mins === 1 ? '' : 's'}.` });
    }
    const valid = await bcrypt.compare(String(currentPin), user.walletPin);
    if (!valid) {
      return res.status(400).json({ error: 'PIN is incorrect.' });
    }

    user.walletPin = null;
    user.walletPinAttempts = 0;
    user.walletPinLockedUntil = null;
    await user.save();
    res.json({ message: 'Transaction PIN removed.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Performs the wallet-to-wallet transfer for "Pay User". Auth (OTP or PIN) has
// already been verified and cleared by walletAuthMiddleware before this runs.
exports.payToUserWithOtp = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { to, amount, note } = req.body;
    if (!to || !amount || amount <= 0) {
      return res.status(400).json({ error: 'to (email) and a positive amount are required' });
    }

    const senderDoc = await User.findById(req.user._id);
    if (!senderDoc) return res.status(404).json({ error: 'User not found' });

    const receiver = await validateRecipient(to, senderDoc);

    let newBalance;
    await session.withTransaction(async () => {
      const sender = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount } },
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

    // Fire-and-forget: notify sender and receiver after successful transfer
    Promise.all([
      User.findById(req.user._id).select('notificationSettings'),
      User.findById(receiver._id).select('notificationSettings'),
    ]).then(([senderUser, receiverUser]) => {
      const notifs = [];
      if (senderUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
          message: `Payment of ₹${amount} sent to ${receiver.email} successfully.`,
        }));
      }
      if (receiverUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [receiver._id], recipientModel: 'User', category: 'transaction',
          message: `You received ₹${amount} from ${senderDoc.email}.`,
        }));
      }
      return Promise.all(notifs);
    }).catch(() => {});

    res.json({ message: 'Payment successful', balance: newBalance });
  } catch (err) {
    if (err.message === 'Insufficient wallet balance') {
      User.findById(req.user._id).select('notificationSettings').then(u => {
        if (u?.notificationSettings?.transactionNotifications !== false) {
          return Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
            message: 'Payment failed: Insufficient LenDen wallet balance.',
          });
        }
      }).catch(() => {});
    }
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

    // Fire-and-forget: notify sender and receiver after successful QR transfer
    Promise.all([
      User.findById(req.user._id).select('notificationSettings'),
      User.findById(receiver._id).select('notificationSettings'),
    ]).then(([senderUser, receiverUser]) => {
      const notifs = [];
      if (senderUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
          message: `QR payment of ₹${parsedAmount} sent to ${receiver.email} successfully.`,
        }));
      }
      if (receiverUser?.notificationSettings?.transactionNotifications !== false) {
        notifs.push(Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [receiver._id], recipientModel: 'User', category: 'transaction',
          message: `You received ₹${parsedAmount} from ${req.user.email} via QR.`,
        }));
      }
      return Promise.all(notifs);
    }).catch(() => {});

    res.json({ message: 'QR payment successful', balance: newBalance });
  } catch (err) {
    if (err.message === 'Insufficient wallet balance') {
      User.findById(req.user._id).select('notificationSettings').then(u => {
        if (u?.notificationSettings?.transactionNotifications !== false) {
          return Notification.create({
            sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
            recipients: [req.user._id], recipientModel: 'User', category: 'transaction',
            message: 'QR payment failed: Insufficient LenDen wallet balance.',
          });
        }
      }).catch(() => {});
    }
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

    Promise.resolve().then(async () => {
      const u = await User.findById(req.user._id).select('notificationSettings').lean();
      if (u?.notificationSettings?.subscriptionNotifications !== false) {
        await Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [req.user._id], recipientModel: 'User', category: 'subscription',
          message: `Your "${plan.name}" subscription is now active.`,
        });
      }
    }).catch(() => {});
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || 'Server error' });
  } finally {
    session.endSession();
  }
};
