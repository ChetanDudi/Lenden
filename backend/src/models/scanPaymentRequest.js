const mongoose = require('mongoose');

// Manual-review queue for UPI QR ("Scan & Pay") payments — mirrors WithdrawalRequest.
// Wallet is debited immediately when the user submits; an admin then manually pays
// the shop's UPI ID outside the app and marks this as processed (or rejects it,
// which auto-refunds the wallet).
const scanPaymentRequestSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  amount: { type: Number, required: true },
  upiId: { type: String, required: true },
  payeeName: { type: String, default: '' },
  note: { type: String, default: '' },
  status: {
    type: String,
    enum: ['processing', 'processed', 'failed'],
    default: 'processing',
  },
  failureReason: { type: String, default: null },
  processedAt: { type: Date, default: null },
}, { timestamps: true });

scanPaymentRequestSchema.index({ user: 1, createdAt: -1 });
scanPaymentRequestSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('ScanPaymentRequest', scanPaymentRequestSchema);
