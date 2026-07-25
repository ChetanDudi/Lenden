const mongoose = require('mongoose');

const savingsGoalSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  name: { type: String, required: true, trim: true },
  emoji: { type: String, default: '🎯' },
  targetAmount: { type: Number, required: true, min: 1 },
  savedAmount: { type: Number, default: 0, min: 0 },
  deadline: { type: Date, default: null },
  color: { type: String, default: '#00BCD4' },
  isCompleted: { type: Boolean, default: false },
}, { timestamps: true });

savingsGoalSchema.index({ user: 1, createdAt: -1 });

module.exports = mongoose.model('SavingsGoal', savingsGoalSchema);
