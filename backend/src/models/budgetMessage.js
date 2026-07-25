const mongoose = require('mongoose');

const budgetMessageSchema = new mongoose.Schema({
  user:       { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  type:       { type: String, required: true }, // 'quick' | 'secure' | 'group' | 'overall' | 'group_specific' | 'cat_{key}'
  groupId:    { type: String, default: null },  // only for group_specific
  groupName:  { type: String, default: null },
  year:       { type: Number, required: true },
  month:      { type: Number, required: true },
  message:    { type: String, required: true },
  amountSpent:{ type: Number, default: 0 },
  limit:      { type: Number, default: 0 },
  isRead:     { type: Boolean, default: false },
  createdAt:  { type: Date, default: Date.now },
});

// One message per user per type per group per month — upsert-safe
budgetMessageSchema.index({ user: 1, type: 1, groupId: 1, year: 1, month: 1 }, { unique: true });

module.exports = mongoose.model('BudgetMessage', budgetMessageSchema);
