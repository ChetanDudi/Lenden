const mongoose = require('mongoose');

const withdrawalRequestSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  amount: { type: Number, required: true },
  mode: { type: String, enum: ['bank_account', 'upi'], required: true },

  // Bank account fields
  accountHolderName: { type: String, default: null },
  accountNumber: { type: String, default: null },   // stored full, masked on response
  ifsc: { type: String, default: null },
  bankName: { type: String, default: null },

  // UPI fields
  upiId: { type: String, default: null },

  // Razorpay Payout details
  razorpayContactId: { type: String, default: null },
  razorpayFundAccountId: { type: String, default: null },
  razorpayPayoutId: { type: String, default: null, index: true },
  razorpayPayoutStatus: { type: String, default: null },

  status: {
    type: String,
    enum: ['processing', 'processed', 'failed', 'reversed'],
    default: 'processing',
  },
  failureReason: { type: String, default: null },
  processedAt: { type: Date, default: null },
}, { timestamps: true });

withdrawalRequestSchema.index({ user: 1, createdAt: -1 });
withdrawalRequestSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('WithdrawalRequest', withdrawalRequestSchema);
