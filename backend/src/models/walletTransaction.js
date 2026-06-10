const mongoose = require('mongoose');

const walletTransactionSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  type: { type: String, enum: ['credit', 'debit', 'topup'], required: true },
  amount: { type: Number, required: true },
  fromEmail: { type: String, default: null },
  toEmail: { type: String, default: null },
  note: { type: String, default: '' },
  razorpayOrderId: { type: String, default: null },
  // Unique sparse index: DB enforces that a Razorpay payment ID can only be used once.
  // sparse means null values (non-Razorpay records) are excluded from the uniqueness constraint.
  razorpayPaymentId: { type: String, default: null },
  createdAt: { type: Date, default: Date.now },
});

// Unique sparse index — prevents double-spend without a separate read query
walletTransactionSchema.index({ razorpayPaymentId: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model('WalletTransaction', walletTransactionSchema);
