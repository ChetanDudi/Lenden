const mongoose = require('mongoose');

const disputeSchema = new mongoose.Schema({
  transactionType: {
    type: String,
    enum: ['secure', 'quick', 'group'],
    required: true,
  },
  transactionId: {
    type: String,
    required: true,
    index: true,
  },
  raisedBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  raisedByEmail: {
    type: String,
    required: true,
  },
  respondentEmail: {
    type: String,
    required: true,
  },
  reason: {
    type: String,
    required: true,
    trim: true,
  },
  description: {
    type: String,
    required: true,
    trim: true,
  },
  evidence: [{ type: String }], // base64-encoded images, same pattern as Transaction.photos
  status: {
    type: String,
    enum: ['open', 'under_review', 'resolved', 'rejected'],
    default: 'open',
    index: true,
  },
  resolution: {
    type: String,
    default: null,
  },
  resolvedBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    default: null,
  },
  resolvedAt: {
    type: Date,
    default: null,
  },
}, { timestamps: true });

disputeSchema.index({ raisedByEmail: 1 });
disputeSchema.index({ respondentEmail: 1 });

module.exports = mongoose.model('Dispute', disputeSchema);
