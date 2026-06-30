const mongoose = require('mongoose');

const quickTransactionSchema = new mongoose.Schema({
  amount: {
    type: Number,
    required: true,
  },
  currency: {
    type: String,
    required: true,
  },
  date: {
    type: Date,
    required: true,
  },
  time: {
    type: String,
    required: true,
  },
  users: [{
    type: String,
    required: true,
  }],
  favourite: {
    type: [String],
    default: [],
  },
  creatorEmail: {
    type: String,
    required: true,
  },
  role: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  cleared: {
    type: Boolean,
    default: false,
  },
  settlementStatus: {
    type: String,
    enum: ['none', 'pending', 'accepted', 'rejected'],
    default: 'none',
  },
  settlementRequestedBy: {
    type: String,
    default: null,
  },
  settlementRequestedAt: {
    type: Date,
    default: null,
  },
  settlementRespondedBy: {
    type: String,
    default: null,
  },
  settlementRespondedAt: {
    type: Date,
    default: null,
  },
  settledViaPayment: { type: Boolean, default: false },
  paymentMethod: { type: String, enum: ['wallet', null], default: null },
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
});

quickTransactionSchema.index({ creatorEmail: 1, createdAt: -1 });
quickTransactionSchema.index({ users: 1 });
quickTransactionSchema.index({ cleared: 1, users: 1 });

quickTransactionSchema.pre('save', function (next) {
  this.updatedAt = Date.now();
  next();
});

const QuickTransaction = mongoose.model('QuickTransaction', quickTransactionSchema);

module.exports = QuickTransaction;
