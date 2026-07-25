const mongoose = require('mongoose');

const adminTipSchema = new mongoose.Schema({
  sentBy:         { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', required: true },
  targetType:     { type: String, enum: ['all', 'specific', 'premium'], default: 'all' },
  targetUser:     { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  title:          { type: String, required: true, trim: true, maxlength: 120 },
  body:           { type: String, required: true, trim: true, maxlength: 500 },
  category:       { type: String, default: 'general', trim: true },
  impact:         { type: String, enum: ['high', 'medium', 'low'], default: 'medium' },
  potentialSaving:{ type: Number, default: null, min: 0 },
  isActive:       { type: Boolean, default: true },
}, { timestamps: true });

adminTipSchema.index({ isActive: 1, targetType: 1, targetUser: 1 });

module.exports = mongoose.model('AdminTip', adminTipSchema);
