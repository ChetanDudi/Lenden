const mongoose = require('mongoose');

const fraudAlertSchema = new mongoose.Schema({
  type: {
    type: String,
    enum: ['large_amount_new_account', 'high_velocity', 'shared_device', 'repeated_disputes', 'self_transaction'],
    required: true,
  },
  severity: {
    type: String,
    enum: ['low', 'medium', 'high', 'critical'],
    default: 'medium',
  },
  targetEmail: { type: String, default: '' },
  relatedEmails: { type: [String], default: [] },
  relatedTransactionType: { type: String, enum: ['secure', 'quick', 'group', ''], default: '' },
  relatedTransactionId: { type: mongoose.Schema.Types.ObjectId, default: null },
  description: { type: String, required: true },
  details: { type: mongoose.Schema.Types.Mixed, default: {} },
  status: {
    type: String,
    enum: ['open', 'reviewing', 'resolved', 'dismissed'],
    default: 'open',
  },
  occurrenceCount: { type: Number, default: 1 },
  lastDetectedAt: { type: Date, default: Date.now },
  reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  reviewNote: { type: String, default: '' },
}, { timestamps: true });

fraudAlertSchema.index({ type: 1, targetEmail: 1 });
fraudAlertSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('FraudAlert', fraudAlertSchema);
