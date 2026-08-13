const mongoose = require('mongoose');
const { Schema: { Types: { ObjectId } } } = mongoose;

const personalBudgetExpenseSchema = new mongoose.Schema({
  budget:      { type: ObjectId, ref: 'PersonalBudget', required: true },
  user:        { type: ObjectId, ref: 'User', required: true },
  amount:      { type: Number, required: true, min: 0 },
  category:       { type: String, required: true, trim: true, maxlength: 50 },
  allocationName: { type: String, default: null, trim: true, maxlength: 80 },
  description:    { type: String, default: '', maxlength: 200, trim: true },
  date:         { type: Date, default: Date.now },
  scheduledFor: { type: Date, default: null },
  status:       { type: String, enum: ['active', 'scheduled'], default: 'active' },
  // Audit trail
  editHistory: [{
    amount:      Number,
    category:    String,
    description: String,
    date:        Date,
    editedAt:    { type: Date, default: Date.now },
    _id: false,
  }],
  isDeleted:   { type: Boolean, default: false },
  deletedAt:   { type: Date },
}, { timestamps: true });

personalBudgetExpenseSchema.index({ budget: 1, date: -1 });
personalBudgetExpenseSchema.index({ user: 1, budget: 1 });

module.exports = mongoose.model('PersonalBudgetExpense', personalBudgetExpenseSchema);
