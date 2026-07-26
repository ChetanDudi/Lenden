const CoinPricingConfig = require('../models/coinPricingConfig');

const DEFAULTS = Object.freeze({
  privateChatMessageCost: 5,
  groupChatMessageCost:   7,
  quickTransactionCost:   5,
  secureTransactionCost:  10,
  groupCreationCost:      20,
  groupExpenseCost:       5,
  dailyLoginReward:       1,
  leaderboardRank1Reward: 20,
  leaderboardRank2Reward: 10,
  leaderboardRank3Reward: 5,
  coinValueCurrency:      'INR',
  coinValue:              0.10,
});

let _cache = null;
let _cacheTime = 0;
const CACHE_TTL = 5 * 60 * 1000; // 5 minutes

async function getCoinPricing() {
  const now = Date.now();
  if (_cache && now - _cacheTime < CACHE_TTL) return _cache;

  try {
    const doc = await CoinPricingConfig.findOne({ singletonKey: 'default' }).lean();
    _cache = doc ? { ...DEFAULTS, ...doc } : { ...DEFAULTS };
    _cacheTime = now;
  } catch (_) {
    // On DB error fall back to defaults without poisoning the cache
    return { ...DEFAULTS };
  }
  return _cache;
}

function invalidateCoinPricingCache() {
  _cache = null;
  _cacheTime = 0;
}

module.exports = { getCoinPricing, invalidateCoinPricingCache, DEFAULTS };
