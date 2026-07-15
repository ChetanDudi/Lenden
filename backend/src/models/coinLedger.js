const mongoose = require('mongoose');

const coinLedgerSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    direction: {
      type: String,
      enum: ['earned', 'spent'],
      required: true,
    },
    coins: {
      type: Number,
      required: true,
      min: 1,
    },
    source: {
      type: String,
      enum: [
        'daily_login',
        'referral_inviter',
        'referral_referee',
        'offer_claim',
        'gift_card_scratch',
        'leaderboard_reward',
        'quick_transaction_with_coins',
        'secure_transaction_with_coins',
        'group_creation_with_coins',
        'private_chat_with_coins',
        'group_chat_with_coins',
        'birthday_gift_sent',
        'birthday_gift_received',
      ],
      required: true,
      index: true,
    },
    title: {
      type: String,
      required: true,
      trim: true,
    },
    description: {
      type: String,
      required: true,
      trim: true,
    },
    metadata: {
      type: mongoose.Schema.Types.Mixed,
      default: {},
    },
    occurredAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
  },
  { timestamps: true }
);

coinLedgerSchema.index({ user: 1, occurredAt: -1 });

module.exports = mongoose.model('CoinLedger', coinLedgerSchema);
