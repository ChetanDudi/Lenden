const mongoose = require('mongoose');
const User = require('../models/user');
const Admin = require('../models/admin');
const WalletTransaction = require('../models/walletTransaction');
const ScanPaymentRequest = require('../models/scanPaymentRequest');
const Notification = require('../models/notification');
const { sendToUser } = require('../services/notificationService');

const MIN_SCAN_PAYMENT = 1; // ₹1

// User scans a shop's UPI QR and pays via LenDen wallet. There is no RazorpayX
// payout account configured, so — exactly like wallet withdrawals — the wallet
// is debited immediately and the payment is queued for an admin to manually
// send to the shop's UPI ID outside the app, then mark as processed.
exports.initiateScanPayment = async (req, res) => {
  const { amount, upiId, payeeName, note } = req.body;
  const parsedAmount = parseFloat(amount);
  if (!parsedAmount || parsedAmount < MIN_SCAN_PAYMENT) {
    return res.status(400).json({ error: `Minimum payment is ₹${MIN_SCAN_PAYMENT}` });
  }
  if (!upiId || !upiId.trim().includes('@')) {
    return res.status(400).json({ error: 'A valid UPI ID is required' });
  }

  const cleanUpiId = upiId.trim();
  const cleanPayeeName = (payeeName || '').trim() || 'Shop';

  const session = await mongoose.startSession();
  let scanPayment, newBalance;
  try {
    await session.withTransaction(async () => {
      const user = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: parsedAmount } },
        { $inc: { walletBalance: -parsedAmount } },
        { new: true, session }
      );
      if (!user) {
        throw Object.assign(new Error('Insufficient wallet balance'), { status: 400, userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.' });
      }
      newBalance = user.walletBalance;

      [scanPayment] = await ScanPaymentRequest.create([{
        user: req.user._id,
        amount: parsedAmount,
        upiId: cleanUpiId,
        payeeName: cleanPayeeName,
        note: (note || '').trim(),
        status: 'processing',
      }], { session });

      await WalletTransaction.create([{
        user: req.user._id,
        type: 'debit',
        amount: parsedAmount,
        toEmail: cleanUpiId,
        note: `QR payment to ${cleanPayeeName} (${cleanUpiId})`,
        scanPaymentRequestId: scanPayment._id,
        status: 'processing',
        sourceType: 'qr_external',
      }], { session });
    });

    // Notify admins a new scan payment needs manual processing — best-effort,
    // doesn't affect the already-committed wallet debit if it fails.
    try {
      await Notification.create({
        sender: req.user._id,
        senderModel: 'User',
        recipientType: 'all-admins',
        recipientModel: 'Admin',
        message: `New QR payment request: ₹${parsedAmount} to ${cleanPayeeName} (${cleanUpiId}). Review in Manage Scan Payments.`,
        category: 'transaction',
        deliveryStatus: 'sent',
        sentAt: new Date(),
      });
    } catch (notifyErr) {
      console.error('[ScanPayment] Failed to notify admins:', notifyErr);
    }

    res.json({
      message: `Payment of ₹${parsedAmount} submitted. Our team will send it to ${cleanPayeeName} within 24–48 hours.`,
      scanPaymentId: scanPayment._id,
      status: 'processing',
      amount: parsedAmount,
      balance: newBalance,
      manualReview: true,
    });
  } catch (err) {
    const status = err.status ?? 500;
    res.status(status).json({ error: err.userMessage || err.message || 'Payment failed' });
  } finally {
    session.endSession();
  }
};

// Scan-payment history for the current user
exports.getScanPaymentHistory = async (req, res) => {
  try {
    const payments = await ScanPaymentRequest.find({ user: req.user._id })
      .sort({ createdAt: -1 })
      .limit(30)
      .lean();
    res.json({ payments });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// ── Admin: manual scan-payment review ─────────────────────────────────────
// Used while no RazorpayX payout account is configured — the admin pays the
// shop's UPI ID outside the app, then marks the request here.

exports.adminGetScanPayments = async (req, res) => {
  try {
    const { status } = req.query;
    const filter = status && status !== 'all' ? { status } : {};
    const payments = await ScanPaymentRequest.find(filter)
      .sort({ createdAt: -1 })
      .limit(200)
      .populate('user', 'name email phone')
      .lean();
    res.json({ payments });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.adminMarkProcessed = async (req, res) => {
  try {
    const scanPayment = await ScanPaymentRequest.findById(req.params.id);
    if (!scanPayment) return res.status(404).json({ error: 'Scan payment request not found' });
    if (scanPayment.status !== 'processing') {
      return res.status(400).json({ error: `Cannot mark a ${scanPayment.status} payment as processed` });
    }
    scanPayment.status = 'processed';
    scanPayment.processedAt = new Date();
    await scanPayment.save();

    await WalletTransaction.updateOne(
      { scanPaymentRequestId: scanPayment._id },
      { $set: { status: 'processed' } }
    );

    try {
      const admin = await Admin.findById(req.user._id).select('_id');
      await Notification.create({
        sender: admin?._id || req.user._id,
        senderModel: 'Admin',
        recipientType: 'specific-users',
        recipients: [scanPayment.user],
        recipientModel: 'User',
        message: `Your QR payment of ₹${scanPayment.amount} to ${scanPayment.payeeName} has been processed and sent.`,
        category: 'transaction',
        deliveryStatus: 'sent',
        sentAt: new Date(),
        estimatedAudience: 1,
      });
      sendToUser(User, scanPayment.user, { title: 'QR Payment Processed ✅', body: `Your QR payment of ₹${scanPayment.amount} has been processed.`, data: { type: 'scan_payment_approved' } });
    } catch (notifyErr) {
      console.error('[ScanPayment] Failed to notify user of processed payment:', notifyErr);
    }

    res.json({ message: 'Scan payment marked as processed', scanPayment });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Rejects a scan payment (e.g. invalid UPI ID) and auto-refunds the wallet.
exports.adminRejectScanPayment = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { reason } = req.body;
    const scanPayment = await ScanPaymentRequest.findById(req.params.id);
    if (!scanPayment) return res.status(404).json({ error: 'Scan payment request not found' });
    if (scanPayment.status !== 'processing') {
      return res.status(400).json({ error: `Cannot reject a ${scanPayment.status} payment` });
    }

    await session.withTransaction(async () => {
      await User.findByIdAndUpdate(scanPayment.user, { $inc: { walletBalance: scanPayment.amount } }, { session });
      await WalletTransaction.create([{
        user: scanPayment.user,
        type: 'credit',
        amount: scanPayment.amount,
        note: `QR payment rejected — refund${reason ? `: ${reason}` : ''}`,
      }], { session });
      await WalletTransaction.updateOne(
        { scanPaymentRequestId: scanPayment._id },
        { $set: { status: 'failed' } },
        { session }
      );
      scanPayment.status = 'failed';
      scanPayment.failureReason = reason || 'Rejected by admin';
      await scanPayment.save({ session });
    });

    try {
      const admin = await Admin.findById(req.user._id).select('_id');
      await Notification.create({
        sender: admin?._id || req.user._id,
        senderModel: 'Admin',
        recipientType: 'specific-users',
        recipients: [scanPayment.user],
        recipientModel: 'User',
        message: `Your QR payment of ₹${scanPayment.amount} to ${scanPayment.payeeName} was rejected and the amount has been refunded to your wallet.${reason ? ` Reason: ${reason}` : ''}`,
        category: 'transaction',
        deliveryStatus: 'sent',
        sentAt: new Date(),
        estimatedAudience: 1,
      });
      sendToUser(User, scanPayment.user, { title: 'QR Payment Rejected ❌', body: `Your QR payment of ₹${scanPayment.amount} was rejected and refunded.`, data: { type: 'scan_payment_rejected' } });
    } catch (notifyErr) {
      console.error('[ScanPayment] Failed to notify user of rejected payment:', notifyErr);
    }

    res.json({ message: 'Scan payment rejected and wallet refunded', scanPayment });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  } finally {
    session.endSession();
  }
};
