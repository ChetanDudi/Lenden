const crypto = require('crypto');
const mongoose = require('mongoose');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const SubscriptionPlan = require('../models/subscriptionPlan');
const Subscription = require('../models/subscription');

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

// Create Razorpay order for wallet top-up
exports.createTopUpOrder = async (req, res) => {
  try {
    const { amount } = req.body; // amount in paise
    if (!amount || amount < 100) {
      return res.status(400).json({ error: 'Minimum top-up amount is ₹1' });
    }
    const razorpay = getRazorpay();
    const order = await razorpay.orders.create({
      amount,
      currency: 'INR',
      receipt: `wallet_${Date.now()}`,
      notes: { userId: req.user._id.toString(), type: 'wallet_topup' },
    });
    res.json({ orderId: order.id, amount: order.amount, currency: order.currency, keyId: process.env.RAZORPAY_KEY_ID });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Verify Razorpay top-up and credit wallet
// ACID: replay prevention via unique index on razorpayPaymentId (DB enforces, no separate read needed)
exports.verifyTopUp = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { razorpayOrderId, razorpayPaymentId, razorpaySignature } = req.body;
    if (!razorpayOrderId || !razorpayPaymentId || !razorpaySignature) {
      return res.status(400).json({ error: 'Missing payment fields' });
    }

    // Signature verification is pure crypto — no DB, safe outside transaction
    const expected = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpayOrderId}|${razorpayPaymentId}`)
      .digest('hex');
    if (expected !== razorpaySignature) {
      return res.status(400).json({ error: 'Signature mismatch' });
    }

    const razorpay = getRazorpay();
    const payment = await razorpay.payments.fetch(razorpayPaymentId);
    const amountInRupees = payment.amount / 100;

    let addedAmount;
    await session.withTransaction(async () => {
      // Insert transaction record first — unique index on razorpayPaymentId prevents replay atomically.
      // If the same paymentId is submitted twice concurrently, one will get a duplicate-key error here.
      await WalletTransaction.create([{
        user: req.user._id,
        type: 'topup',
        amount: amountInRupees,
        note: 'Wallet top-up via Razorpay',
        razorpayOrderId,
        razorpayPaymentId,
      }], { session });

      // Credit the wallet only after the record is safely inserted
      await User.findByIdAndUpdate(
        req.user._id,
        { $inc: { walletBalance: amountInRupees } },
        { session }
      );
      addedAmount = amountInRupees;
    });

    const updated = await User.findById(req.user._id).select('walletBalance');
    res.json({ message: 'Wallet topped up', addedAmount, balance: updated?.walletBalance ?? 0 });
  } catch (err) {
    // Duplicate key = already applied
    if (err.code === 11000) {
      return res.status(409).json({ error: 'Payment already applied to wallet' });
    }
    res.status(500).json({ error: 'Server error' });
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
        throw Object.assign(new Error('Insufficient wallet balance'), { status: 400 });
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
      if (!user) throw Object.assign(new Error('Insufficient wallet balance'), { status: 400 });

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
