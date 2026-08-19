const mongoose = require('mongoose');

const referralShareSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    channel: {
      type: String,
      required: true,
      enum: ['whatsapp', 'telegram', 'email', 'sms', 'copy', 'other', 'quick_transaction', 'group_invite'],
    },
    referralCode: { type: String, required: true },
    message: { type: String, default: '' },
  },
  { timestamps: true }
);

referralShareSchema.index({ user: 1, createdAt: -1 });

module.exports = mongoose.model('ReferralShare', referralShareSchema);
