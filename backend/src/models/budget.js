const mongoose = require('mongoose');

const budgetSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  year: { type: Number, required: true },
  month: { type: Number, required: true, min: 1, max: 12 },
  limits: {
    quick: { type: Number, default: null, min: 0 },
    secure: { type: Number, default: null, min: 0 },
    group: { type: Number, default: null, min: 0 },
    overall: { type: Number, default: null, min: 0 },
  },
  categoryLimits: {
    food: { type: Number, default: null },
    shopping: { type: Number, default: null },
    entertainment: { type: Number, default: null },
    fuel: { type: Number, default: null },
    travel: { type: Number, default: null },
    medical: { type: Number, default: null },
    education: { type: Number, default: null },
    other: { type: Number, default: null },
  },
  groupLimits: { type: Map, of: Number, default: {} },
  alertThresholds: { type: [Number], default: [75, 90, 100] },
  rolloverApplied: { type: Number, default: null },
}, { timestamps: true });

budgetSchema.index({ user: 1, year: 1, month: 1 }, { unique: true });

module.exports = mongoose.model('Budget', budgetSchema);
