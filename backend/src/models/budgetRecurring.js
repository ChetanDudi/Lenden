const mongoose = require('mongoose');

const budgetRecurringSchema = new mongoose.Schema({
  user:     { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  name:     { type: String, required: true, trim: true, maxlength: 100 },
  amount:   { type: Number, required: true, min: 0 },
  category: { type: String, default: 'Other Fixed Cost', trim: true },
  dueDay:   { type: Number, min: 1, max: 28, default: null },
  isActive: { type: Boolean, default: true },
}, { timestamps: true });

budgetRecurringSchema.index({ user: 1, isActive: 1 });

module.exports = mongoose.model('BudgetRecurring', budgetRecurringSchema);
