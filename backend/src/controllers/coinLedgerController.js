const CoinLedger = require('../models/coinLedger');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const mongoose = require('mongoose');
const { getCoinPricing } = require('../utils/coinPricing');

const formatSourceLabel = (source) =>
  source
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');

exports.getMyCoinHistory = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('lenDenCoins');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const limit = Math.min(Math.max(Number(req.query.limit) || 60, 1), 200);
    const entries = await CoinLedger.find({ user: req.user._id })
      .sort({ occurredAt: -1, createdAt: -1 })
      .limit(limit)
      .lean();

    const summary = entries.reduce(
      (acc, entry) => {
        const amount = Number(entry.coins || 0);
        if (entry.direction === 'earned') {
          acc.totalEarned += amount;
        } else {
          acc.totalSpent += amount;
        }

        const key = entry.source || 'other';
        if (!acc.bySource[key]) {
          acc.bySource[key] = {
            label: formatSourceLabel(key),
            earned: 0,
            spent: 0,
            count: 0,
          };
        }
        acc.bySource[key].count += 1;
        if (entry.direction === 'earned') {
          acc.bySource[key].earned += amount;
        } else {
          acc.bySource[key].spent += amount;
        }

        return acc;
      },
      { totalEarned: 0, totalSpent: 0, bySource: {} }
    );

    res.json({
      balance: Number(user.lenDenCoins || 0),
      summary: {
        totalEarned: summary.totalEarned,
        totalSpent: summary.totalSpent,
        net: summary.totalEarned - summary.totalSpent,
        sources: Object.values(summary.bySource).sort(
          (a, b) => b.count - a.count || b.earned + b.spent - (a.earned + a.spent)
        ),
      },
      entries: entries.map((entry) => ({
        id: entry._id,
        direction: entry.direction,
        coins: entry.coins,
        source: entry.source,
        title: entry.title,
        description: entry.description,
        occurredAt: entry.occurredAt,
        metadata: entry.metadata || {},
      })),
    });
  } catch (error) {
    console.error('Error fetching coin history:', error);
    res.status(500).json({ error: 'Failed to fetch coin history' });
  }
};

exports.buyCoinsWithWallet = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const coinsToBuy = Math.floor(Number(req.body.coinsToBuy));
    if (!coinsToBuy || coinsToBuy < 1 || coinsToBuy > 10000) {
      return res.status(400).json({ error: 'coinsToBuy must be a whole number between 1 and 10000.' });
    }

    const pricing = await getCoinPricing();
    if (!pricing.coinValue || pricing.coinValue <= 0) {
      return res.status(503).json({ error: 'Coin pricing is not configured. Contact admin.' });
    }
    const amount = parseFloat((coinsToBuy * pricing.coinValue).toFixed(6));

    let newWalletBalance, newCoinBalance;

    await session.withTransaction(async () => {
      const updatedUser = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount, lenDenCoins: coinsToBuy } },
        { new: true, session }
      );
      if (!updatedUser) {
        const u = await User.findById(req.user._id).select('walletBalance').session(session);
        const bal = u?.walletBalance ?? 0;
        throw Object.assign(new Error('INSUFFICIENT'), {
          code: 'INSUFFICIENT',
          required: amount,
          available: bal,
        });
      }
      newWalletBalance = updatedUser.walletBalance;
      newCoinBalance = updatedUser.lenDenCoins;

      await WalletTransaction.create([{
        user: req.user._id,
        type: 'debit',
        amount,
        note: `Bought ${coinsToBuy} LenDen Coin${coinsToBuy > 1 ? 's' : ''}`,
        status: 'processed',
        sourceType: 'coins',
      }], { session });

      await CoinLedger.create([{
        user: req.user._id,
        direction: 'earned',
        coins: coinsToBuy,
        source: 'wallet_purchase',
        title: 'Coins Purchased',
        description: `Bought ${coinsToBuy} coins for ${pricing.coinValueCurrency} ${amount.toFixed(2)}`,
        metadata: { amount, currency: pricing.coinValueCurrency, coinValue: pricing.coinValue },
        occurredAt: new Date(),
      }], { session });
    });

    res.json({
      message: `Successfully bought ${coinsToBuy} LenDen Coin${coinsToBuy > 1 ? 's' : ''}.`,
      coinsAdded: coinsToBuy,
      newCoinBalance,
      newWalletBalance,
      amountDeducted: amount,
      currency: pricing.coinValueCurrency,
    });
  } catch (err) {
    if (err.code === 'INSUFFICIENT') {
      return res.status(400).json({
        error: `Insufficient wallet balance. Required: ${err.required.toFixed(2)}, Available: ${err.available.toFixed(2)}.`,
      });
    }
    console.error('buyCoinsWithWallet error:', err);
    res.status(500).json({ error: 'Failed to purchase coins. Please try again.' });
  } finally {
    session.endSession();
  }
};
