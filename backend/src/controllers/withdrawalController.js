const crypto = require('crypto');
const mongoose = require('mongoose');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const WithdrawalRequest = require('../models/withdrawalRequest');

const MIN_WITHDRAWAL = 10; // ₹10

const getRazorpay = () => {
  const Razorpay = require('razorpay');
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new Error('Razorpay keys not configured');
  }
  return new Razorpay({ key_id: process.env.RAZORPAY_KEY_ID, key_secret: process.env.RAZORPAY_KEY_SECRET });
};

// Initiate a withdrawal from wallet → bank account or UPI via Razorpay Payouts
exports.initiateWithdrawal = async (req, res) => {
  const { amount, mode, accountHolderName, accountNumber, ifsc, bankName, upiId } = req.body;

  // Input validation
  const parsedAmount = parseFloat(amount);
  if (!parsedAmount || parsedAmount < MIN_WITHDRAWAL) {
    return res.status(400).json({ error: `Minimum withdrawal is ₹${MIN_WITHDRAWAL}` });
  }
  if (!mode || !['bank_account', 'upi'].includes(mode)) {
    return res.status(400).json({ error: 'mode must be bank_account or upi' });
  }
  if (mode === 'bank_account') {
    if (!accountHolderName?.trim() || !accountNumber?.trim() || !ifsc?.trim()) {
      return res.status(400).json({ error: 'accountHolderName, accountNumber, and ifsc are required for bank withdrawal' });
    }
    if (!/^\d{8,18}$/.test(accountNumber.trim())) {
      return res.status(400).json({ error: 'Invalid account number (must be 8–18 digits)' });
    }
    if (!/^[A-Z]{4}0[A-Z0-9]{6}$/i.test(ifsc.trim())) {
      return res.status(400).json({ error: 'Invalid IFSC code format (e.g. HDFC0001234)' });
    }
  }
  if (mode === 'upi') {
    if (!upiId?.trim()) {
      return res.status(400).json({ error: 'upiId is required for UPI withdrawal' });
    }
    if (!upiId.includes('@')) {
      return res.status(400).json({ error: 'Invalid UPI ID format (e.g. name@bank)' });
    }
  }

  const isTestMode = !process.env.RAZORPAY_ACCOUNT_NUMBER ||
    (process.env.RAZORPAY_KEY_ID || '').startsWith('rzp_test_');

  const session = await mongoose.startSession();
  let withdrawal;

  try {
    // ── Phase 1 (always): atomic wallet debit + withdrawal record ───────────────
    await session.withTransaction(async () => {
      const user = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: parsedAmount } },
        { $inc: { walletBalance: -parsedAmount } },
        { new: true, session }
      );
      if (!user) throw Object.assign(new Error('Insufficient wallet balance'), { status: 400 });

      const noteText = mode === 'upi'
        ? `Withdrawal to UPI: ${upiId}`
        : `Withdrawal to bank ****${accountNumber.trim().slice(-4)}`;

      await WalletTransaction.create([{
        user: req.user._id,
        type: 'withdrawal',
        amount: parsedAmount,
        note: noteText,
      }], { session });

      [withdrawal] = await WithdrawalRequest.create([{
        user: req.user._id,
        amount: parsedAmount,
        mode,
        status: isTestMode ? 'processed' : 'processing',
        ...(isTestMode ? { processedAt: new Date(), razorpayPayoutId: `test_sim_${Date.now()}`, razorpayPayoutStatus: 'processed' } : {}),
        ...(mode === 'bank_account' ? {
          accountHolderName: accountHolderName.trim(),
          accountNumber: accountNumber.trim(),
          ifsc: ifsc.trim().toUpperCase(),
          bankName: bankName?.trim() || '',
        } : {}),
        ...(mode === 'upi' ? { upiId: upiId.trim() } : {}),
      }], { session });
    });

    // ── Phase 2 (test mode): skip Razorpay, return simulated success ────────────
    if (isTestMode) {
      return res.json({
        message: `[Test Mode] Withdrawal simulated — ₹${parsedAmount} deducted from your wallet. In production, funds would be sent to your ${mode === 'upi' ? 'UPI ID' : 'bank account'}.`,
        withdrawalId: withdrawal._id,
        status: 'processed',
        amount: parsedAmount,
        mode,
        testMode: true,
      });
    }

    // ── Phase 2 (live mode): Razorpay Payouts ───────────────────────────────────
    const razorpay = getRazorpay();
    const userDoc = await User.findById(req.user._id).select('name email phone');

    const contact = await razorpay.contacts.create({
      name: userDoc.name || accountHolderName || 'LenDen User',
      email: userDoc.email,
      contact: userDoc.phone || '',
      type: 'customer',
      reference_id: `lenden_${req.user._id}`,
    });

    let fundAccount;
    if (mode === 'bank_account') {
      fundAccount = await razorpay.fundAccount.create({
        contact_id: contact.id,
        account_type: 'bank_account',
        bank_account: {
          name: accountHolderName.trim(),
          ifsc: ifsc.trim().toUpperCase(),
          account_number: accountNumber.trim(),
        },
      });
    } else {
      fundAccount = await razorpay.fundAccount.create({
        contact_id: contact.id,
        account_type: 'vpa',
        vpa: { address: upiId.trim() },
      });
    }

    const payout = await razorpay.payouts.create({
      account_number: process.env.RAZORPAY_ACCOUNT_NUMBER,
      fund_account_id: fundAccount.id,
      amount: Math.round(parsedAmount * 100),
      currency: 'INR',
      mode: mode === 'upi' ? 'UPI' : 'IMPS',
      purpose: 'payout',
      queue_if_low_balance: true,
      reference_id: withdrawal._id.toString(),
      narration: 'LenDen Wallet Withdrawal',
    });

    await WithdrawalRequest.findByIdAndUpdate(withdrawal._id, {
      razorpayContactId: contact.id,
      razorpayFundAccountId: fundAccount.id,
      razorpayPayoutId: payout.id,
      razorpayPayoutStatus: payout.status,
      status: payout.status === 'processed' ? 'processed' : 'processing',
      ...(payout.status === 'processed' ? { processedAt: new Date() } : {}),
    });

    return res.json({
      message: payout.status === 'processed'
        ? 'Withdrawal successful — money sent to your account.'
        : 'Withdrawal initiated — funds will arrive within minutes.',
      withdrawalId: withdrawal._id,
      status: payout.status,
      amount: parsedAmount,
      mode,
    });

  } catch (err) {
    if (withdrawal) {
      try {
        await User.findByIdAndUpdate(req.user._id, { $inc: { walletBalance: parsedAmount } });
        await WalletTransaction.create({
          user: req.user._id,
          type: 'credit',
          amount: parsedAmount,
          note: 'Withdrawal failed — auto refund',
        });
        await WithdrawalRequest.findByIdAndUpdate(withdrawal._id, {
          status: 'failed',
          failureReason: err.message,
        });
      } catch (refundErr) {
        console.error('[Withdrawal] Auto-refund failed — manual intervention needed:', refundErr);
      }
    }
    const status = err.status ?? (err.statusCode ?? 500);
    return res.status(status).json({ error: err.error?.description || err.message || 'Withdrawal failed' });
  } finally {
    session.endSession();
  }
};

// Withdrawal history for the current user (masks sensitive fields)
exports.getWithdrawalHistory = async (req, res) => {
  try {
    const withdrawals = await WithdrawalRequest.find({ user: req.user._id })
      .sort({ createdAt: -1 })
      .limit(30)
      .lean();

    const safe = withdrawals.map(w => ({
      _id: w._id,
      amount: w.amount,
      mode: w.mode,
      status: w.status,
      failureReason: w.failureReason,
      processedAt: w.processedAt,
      createdAt: w.createdAt,
      // Mask bank account number — show last 4 digits only
      accountNumber: w.accountNumber ? `****${w.accountNumber.slice(-4)}` : null,
      accountHolderName: w.accountHolderName,
      ifsc: w.ifsc,
      bankName: w.bankName,
      upiId: w.upiId,
    }));

    res.json({ withdrawals: safe });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Razorpay webhook — updates withdrawal status when Razorpay notifies us
// Handles: payout.processed, payout.failed, payout.reversed
exports.handlePayoutWebhook = async (req, res) => {
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (webhookSecret) {
    const sig = req.headers['x-razorpay-signature'];
    const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from(JSON.stringify(req.body));
    const expected = crypto.createHmac('sha256', webhookSecret).update(raw).digest('hex');
    if (sig !== expected) return res.status(400).json({ error: 'Invalid signature' });
  }

  let event;
  try {
    event = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
  } catch {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  const payoutEvents = new Set(['payout.processed', 'payout.failed', 'payout.reversed']);
  if (payoutEvents.has(event.event)) {
    const payout = event.payload?.payout?.entity;
    if (payout?.id) {
      try {
        const withdrawal = await WithdrawalRequest.findOne({ razorpayPayoutId: payout.id });
        if (withdrawal && withdrawal.status === 'processing') {
          const newStatus = event.event === 'payout.processed' ? 'processed'
            : event.event === 'payout.reversed' ? 'reversed' : 'failed';

          await WithdrawalRequest.findByIdAndUpdate(withdrawal._id, {
            status: newStatus,
            razorpayPayoutStatus: payout.status,
            ...(payout.failure_reason ? { failureReason: payout.failure_reason } : {}),
            ...(newStatus === 'processed' ? { processedAt: new Date() } : {}),
          });

          // Refund the wallet if the payout was reversed or failed after it was initially accepted
          if (newStatus === 'failed' || newStatus === 'reversed') {
            await User.findByIdAndUpdate(withdrawal.user, { $inc: { walletBalance: withdrawal.amount } });
            await WalletTransaction.create({
              user: withdrawal.user,
              type: 'credit',
              amount: withdrawal.amount,
              note: `Withdrawal ${newStatus} — refund`,
            });
          }
        }
      } catch (e) {
        console.error('[Payout Webhook] Error processing event:', e);
      }
    }
  }

  res.json({ status: 'ok' });
};
