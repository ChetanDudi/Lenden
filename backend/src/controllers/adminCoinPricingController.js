const CoinPricingConfig = require('../models/coinPricingConfig');
const { invalidateCoinPricingCache, DEFAULTS } = require('../utils/coinPricing');
const CurrencyConversionRate = require('../models/currencyConversionRate');
const { getSupportedCurrencyDefinitions } = require('../utils/supportedCurrencies');

const NUMERIC_FIELDS = [
  'privateChatMessageCost',
  'groupChatMessageCost',
  'quickTransactionCost',
  'secureTransactionCost',
  'groupCreationCost',
  'groupExpenseCost',
  'communityCoinCost',
  'dailyLoginReward',
  'leaderboardRank1Reward',
  'leaderboardRank2Reward',
  'leaderboardRank3Reward',
  'coinValue',
];

exports.getCoinPricing = async (req, res) => {
  try {
    let config = await CoinPricingConfig.findOne({ singletonKey: 'default' }).lean();
    if (!config) config = { ...DEFAULTS, singletonKey: 'default' };

    const currencyDefs = await getSupportedCurrencyDefinitions();
    const currencies = currencyDefs.map((c) => ({
      code: c.code,
      symbol: c.symbol,
      label: c.label,
    }));

    // Fetch all rates whose base is the configured coin-value currency
    const baseCurrency = config.coinValueCurrency || 'INR';
    const rateRows = await CurrencyConversionRate.find({ baseCurrency }).lean();
    const rateMap = {};
    rateRows.forEach((r) => { rateMap[r.quoteCurrency] = r.rate; });
    // Same-currency rate is always 1
    rateMap[baseCurrency] = 1;

    res.json({ config, currencies, rateMap });
  } catch (err) {
    console.error('[CoinPricing] GET error:', err);
    res.status(500).json({ error: 'Failed to load coin pricing config.' });
  }
};

exports.updateCoinPricing = async (req, res) => {
  try {
    const admin = req.user;
    const update = { updatedBy: admin.email || String(admin._id) };

    for (const field of NUMERIC_FIELDS) {
      if (req.body[field] === undefined) continue;
      const val = Number(req.body[field]);
      if (!isFinite(val) || val < 0) {
        return res.status(400).json({ error: `Invalid value for ${field}: must be a non-negative number.` });
      }
      update[field] = val;
    }

    if (req.body.coinValueCurrency !== undefined) {
      const code = String(req.body.coinValueCurrency).trim().toUpperCase();
      if (!code) return res.status(400).json({ error: 'coinValueCurrency cannot be empty.' });
      update.coinValueCurrency = code;
    }

    const config = await CoinPricingConfig.findOneAndUpdate(
      { singletonKey: 'default' },
      { $set: update },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    invalidateCoinPricingCache();
    res.json({ message: 'Coin pricing updated successfully.', config });
  } catch (err) {
    console.error('[CoinPricing] PUT error:', err);
    res.status(500).json({ error: 'Failed to update coin pricing config.' });
  }
};
