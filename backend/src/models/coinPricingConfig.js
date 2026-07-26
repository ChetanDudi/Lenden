const mongoose = require('mongoose');

const coinPricingConfigSchema = new mongoose.Schema(
  {
    singletonKey: { type: String, default: 'default', unique: true },

    // Spend costs (coins per action)
    privateChatMessageCost: { type: Number, default: 5, min: 0 },
    groupChatMessageCost:   { type: Number, default: 7, min: 0 },
    quickTransactionCost:   { type: Number, default: 5, min: 0 },
    secureTransactionCost:  { type: Number, default: 10, min: 0 },
    groupCreationCost:      { type: Number, default: 20, min: 0 },
    groupExpenseCost:       { type: Number, default: 5, min: 0 },

    // Earn rewards
    dailyLoginReward:        { type: Number, default: 1, min: 0 },
    leaderboardRank1Reward:  { type: Number, default: 20, min: 0 },
    leaderboardRank2Reward:  { type: Number, default: 10, min: 0 },
    leaderboardRank3Reward:  { type: Number, default: 5, min: 0 },

    // Real-money value of 1 coin (display only)
    coinValueCurrency: { type: String, default: 'INR' },
    coinValue:         { type: Number, default: 0.10, min: 0 },

    updatedBy: { type: String },
  },
  { timestamps: true }
);

module.exports = mongoose.model('CoinPricingConfig', coinPricingConfigSchema);
