const mongoose = require('mongoose');

const personalBudgetSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  name: { type: String, required: true, trim: true, maxlength: 80 },
  period: {
    type: String,
    enum: ['daily', 'weekly', 'monthly', 'yearly', 'custom'],
    required: true,
  },
  startDate: { type: Date, required: true },
  endDate:   { type: Date, required: true },
  limit:     { type: Number, required: true, min: 0 },
  currency:  { type: String, default: 'INR' },
  notes:     { type: String, default: '', maxlength: 300 },
  status: {
    type: String,
    enum: ['active', 'completed', 'expired'],
    default: 'active',
  },
  allocations: [{
    name:  { type: String, required: true, trim: true, maxlength: 80 },
    limit: { type: Number, required: true, min: 0 },
    _id:   false,
  }],
  spentAtClose:    { type: Number, default: null },
  notifiedExpiry:  { type: Boolean, default: false },
}, { timestamps: true });

personalBudgetSchema.index({ user: 1, startDate: -1 });
personalBudgetSchema.index({ user: 1, status: 1 });

module.exports = mongoose.model('PersonalBudget', personalBudgetSchema);
