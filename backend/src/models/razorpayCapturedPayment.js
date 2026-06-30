const mongoose = require('mongoose');

// Mirrors Razorpay 'payment.captured' webhook events so payments made through
// the no-code Payment Handle link (razorpay.me/@...) can be verified without
// calling the Payments Fetch API, which needs Live API keys an individual
// account may not be able to obtain.
const razorpayCapturedPaymentSchema = new mongoose.Schema({
  paymentId: {
    type: String,
    required: true,
    unique: true,
  },
  amount: {
    type: Number,
    required: true,
  },
  currency: {
    type: String,
    required: true,
  },
  capturedAt: {
    type: Date,
    required: true,
  },
  // Subscriptions are claimed via Subscription's own unique index on razorpayPaymentId,
  // but wallet top-ups have no such document to dedupe against, so this cache entry
  // itself must track whether it has already been redeemed.
  claimed: { type: Boolean, default: false },
  claimedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  claimedFor: { type: String, enum: ['subscription', 'wallet_topup'] },
  claimedAt: { type: Date },
}, { timestamps: true });

module.exports = mongoose.model('RazorpayCapturedPayment', razorpayCapturedPaymentSchema);
