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
}, { timestamps: true });

module.exports = mongoose.model('RazorpayCapturedPayment', razorpayCapturedPaymentSchema);
