const mongoose = require('mongoose');

const recurringTemplateSchema = new mongoose.Schema({
  creatorEmail: { type: String, required: true },
  counterpartyEmail: { type: String, required: true },
  amount: { type: Number, required: true },
  currency: { type: String, required: true },
  role: { type: String, enum: ['lender', 'borrower'], required: true },
  description: { type: String, default: '' },
  frequency: { type: String, enum: ['weekly', 'monthly'], required: true },
  dayOfMonth: { type: Number, default: null },
  weekday: { type: Number, default: null },
  nextRunAt: { type: Date, required: true },
  lastRunAt: { type: Date, default: null },
  isActive: { type: Boolean, default: true },
  pausedReason: { type: String, default: '' },
}, { timestamps: true });

recurringTemplateSchema.index({ creatorEmail: 1, createdAt: -1 });
recurringTemplateSchema.index({ isActive: 1, nextRunAt: 1 });

module.exports = mongoose.model('RecurringQuickTransactionTemplate', recurringTemplateSchema);
