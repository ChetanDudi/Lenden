const QuickTransaction = require('../models/quickTransaction');
const User = require('../models/user');
const Subscription = require('../models/subscription');
const { logQuickTransactionActivity } = require('./activityController');
const { awardGiftCard, shouldAwardGiftCard } = require('./userGiftCardController');
const { processReferralRewardOnFirstCreation } = require('../utils/referralService');
const { validateCoinCreationAccess } = require('../utils/coinUsageGuard');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');

const isBlockedBy = (user, other) =>
  (user.blockedUsers || []).some(
    (id) => id.toString() === other._id.toString()
  );

const isSubscribed = async (userId) => {
  const subscription = await Subscription.findOne({
    user: userId,
    status: 'active',
  });
  return (
    subscription &&
    subscription.subscribed &&
    subscription.endDate >= new Date()
  );
};

const getTodayRange = () => {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date();
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

const resetSettlementState = (quickTransaction) => {
  quickTransaction.settlementStatus = 'none';
  quickTransaction.settlementRequestedBy = null;
  quickTransaction.settlementRequestedAt = null;
  quickTransaction.settlementRespondedBy = null;
  quickTransaction.settlementRespondedAt = null;
};

exports.createQuickTransaction = async (req, res) => {
  try {
    const { amount, currency, date, time, description, counterpartyEmail, role } = req.body;
    const user = await User.findById(req.user._id).select('email blockedUsers');
    const userEmail = user.email;

    if (userEmail === counterpartyEmail) {
      return res.status(400).json({ error: 'User and counterparty email cannot be the same.' });
    }

    const counterparty = await User.findOne({ email: counterpartyEmail }).select(
      'email blockedUsers'
    );
    if (!counterparty) {
      return res.status(404).json({ error: 'Counterparty email not found.' });
    }
    if (isBlockedBy(user, counterparty)) {
      return res.status(403).json({
        error: 'You have blocked this user. Unblock to proceed.',
      });
    }
    if (isBlockedBy(counterparty, user)) {
      return res.status(403).json({
        error: 'You cannot add this user because they have blocked you.',
      });
    }

    if (!(await isSubscribed(user._id))) {
      const { start, end } = getTodayRange();
      const todayCount = await QuickTransaction.countDocuments({
        creatorEmail: userEmail,
        createdAt: { $gte: start, $lte: end },
      });
      if (todayCount >= 3) {
        return res.status(429).json({
          error: 'Daily limit reached: You can create 3 quick transactions per day.',
        });
      }
    }

    const quickTransaction = new QuickTransaction({
      amount,
      currency,
      date,
      time,
      description,
      users: [userEmail, counterpartyEmail],
      creatorEmail: userEmail,
      role,
    });

    await quickTransaction.save();
    const referralReward = await processReferralRewardOnFirstCreation(req.user._id);
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_created', quickTransaction, { counterpartyEmail });

    // Award gift card every 10 quick transactions (guaranteed, randomized within window)
    const quickTxnCount = await QuickTransaction.countDocuments({ creatorEmail: userEmail });
    let awardedCard = null;
    if (shouldAwardGiftCard(req.user._id, quickTxnCount, 10)) {
      awardedCard = await awardGiftCard(req.user._id, 'quickTransaction');
    } else {
    }

    res.status(201).json({ 
        message: 'Quick transaction created successfully', 
        quickTransaction, 
        freeQuickTransactionsRemaining: user.freeQuickTransactionsRemaining,
        referralReward,
        giftCardAwarded: awardedCard ? true : false,
        awardedCard: awardedCard
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.createQuickTransactionWithCoins = async (req, res) => {
  const QUICK_TRANSACTION_COST = 5;
  const QUICK_TRANSACTION_DAILY_LIMIT = 3;
  try {
    const { amount, currency, date, time, description, counterpartyEmail, role } = req.body;
    const user = await User.findById(req.user._id).select(
      'email blockedUsers lenDenCoins freeQuickTransactionsRemaining'
    );
    const userEmail = user.email;

    if (userEmail === counterpartyEmail) {
      return res.status(400).json({ error: 'User and counterparty email cannot be the same.' });
    }

    const counterparty = await User.findOne({ email: counterpartyEmail }).select(
      'email blockedUsers'
    );
    if (!counterparty) {
      return res.status(404).json({ error: 'Counterparty email not found.' });
    }
    if (isBlockedBy(user, counterparty)) {
      return res.status(403).json({
        error: 'You have blocked this user. Unblock to proceed.',
      });
    }
    if (isBlockedBy(counterparty, user)) {
      return res.status(403).json({
        error: 'You cannot add this user because they have blocked you.',
      });
    }

    const subscribed = await isSubscribed(user._id);
    const { start, end } = getTodayRange();
    const todayCount = await QuickTransaction.countDocuments({
      creatorEmail: userEmail,
      createdAt: { $gte: start, $lte: end },
    });
    const accessError = validateCoinCreationAccess({
      subscribed,
      freeRemaining: user.freeQuickTransactionsRemaining,
      dailyCount: todayCount,
      dailyLimit: QUICK_TRANSACTION_DAILY_LIMIT,
      dailyLimitMessage:
        'Daily limit reached: You can create 3 quick transactions per day.',
      coinBalance: user.lenDenCoins,
      coinCost: QUICK_TRANSACTION_COST,
      featureLabel: 'quick transaction',
    });
    if (accessError && accessError.error) {
      return res.status(accessError.status).json({ error: accessError.error });
    }
    const accessWarning = accessError?.warning;

    user.lenDenCoins -= QUICK_TRANSACTION_COST;
    await user.save();
    await recordCoinLedgerEntry({
      userId: user._id,
      direction: 'spent',
      coins: QUICK_TRANSACTION_COST,
      source: 'quick_transaction_with_coins',
      title: 'Quick Transaction Created With Coins',
      description: `Spent ${QUICK_TRANSACTION_COST} LenDen coins to create a quick transaction with ${counterpartyEmail}.`,
      metadata: {
        counterpartyEmail,
        amount,
        currency,
      },
    });

    const quickTransaction = new QuickTransaction({
      amount,
      currency,
      date,
      time,
      description,
      users: [userEmail, counterpartyEmail],
      creatorEmail: userEmail,
      role,
    });

    await quickTransaction.save();
    const referralReward = await processReferralRewardOnFirstCreation(req.user._id);
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_created_with_coins', quickTransaction, { counterpartyEmail });

    // Award gift card every 10 quick transactions (guaranteed, randomized within window)
    const quickTxnCount = await QuickTransaction.countDocuments({ creatorEmail: userEmail });
    let awardedCard = null;
    if (shouldAwardGiftCard(user._id, quickTxnCount, 10)) {
      awardedCard = await awardGiftCard(user._id, 'quickTransaction');
    } else {
    }

    res.status(201).json({ 
        message: 'Quick transaction created successfully with LenDen coins', 
        quickTransaction, 
        lenDenCoins: user.lenDenCoins,
        warning: accessWarning,
        referralReward,
        giftCardAwarded: awardedCard ? true : false,
        awardedCard: awardedCard
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.getQuickTransactions = async (req, res) => {
  try {
    const userEmail = req.user.email;
    const quickTransactions = await QuickTransaction.find({ users: userEmail }).sort({ createdAt: -1 }).lean();

    const populatedTransactions = await Promise.all(quickTransactions.map(async (t) => {
      const users = await User.find({ email: { $in: t.users } }).select('name email');
      t.users = users.map(u => ({ name: u.name, email: u.email }));
      return t;
    }));

    res.status(200).json({ quickTransactions: populatedTransactions });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.toggleQuickTransactionFavourite = async (req, res) => {
  try {
    const { id } = req.params;
    const { email } = req.body;

    if (!id || !email) {
      return res.status(400).json({ error: 'Quick transaction ID and email are required' });
    }

    const quickTransaction = await QuickTransaction.findById(id);
    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }

    if (!quickTransaction.users.includes(email)) {
      return res.status(403).json({ error: 'You are not a party to this quick transaction' });
    }

    const isFavourited = quickTransaction.favourite.includes(email);
    if (isFavourited) {
      quickTransaction.favourite = quickTransaction.favourite.filter(favEmail => favEmail !== email);
    } else {
      quickTransaction.favourite.push(email);
    }

    await quickTransaction.save();
    res.status(200).json({
      success: true,
      message: `Quick transaction ${isFavourited ? 'removed from' : 'added to'} favourites`,
      favourite: quickTransaction.favourite,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const { amount, currency, date, time, description, role } = req.body;
    const userEmail = req.user.email;

    const quickTransaction = await QuickTransaction.findById(id);

    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }

    if (quickTransaction.cleared) {
      return res.status(403).json({ error: 'Cannot edit a cleared transaction' });
    }

    if (!quickTransaction.users.includes(userEmail)) {
      return res.status(403).json({ error: 'User not authorized to update this transaction' });
    }

    quickTransaction.amount = amount;
    quickTransaction.currency = currency;
    quickTransaction.date = date;
    quickTransaction.time = time;
    quickTransaction.description = description;
    quickTransaction.role = role;
    resetSettlementState(quickTransaction);

    await quickTransaction.save();
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_updated', quickTransaction);

    res.status(200).json({ quickTransaction });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.deleteQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const quickTransaction = await QuickTransaction.findById(id);

    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }

    if (!quickTransaction.users.includes(req.user.email)) {
      return res.status(403).json({ error: 'User not authorized to delete this transaction' });
    }

    await QuickTransaction.findByIdAndDelete(id);
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_deleted', quickTransaction);

    res.status(200).json({ message: 'Quick transaction deleted successfully' });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.clearQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;

    const quickTransaction = await QuickTransaction.findById(id);

    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }

    if (!quickTransaction.users.includes(req.user.email)) {
      return res.status(403).json({ error: 'User not authorized to clear this transaction' });
    }

    quickTransaction.cleared = true;
    quickTransaction.settlementStatus = 'accepted';
    quickTransaction.settlementRespondedBy = req.user.email;
    quickTransaction.settlementRespondedAt = new Date();
    await quickTransaction.save();
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_cleared', quickTransaction);

    res.status(200).json({ quickTransaction });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.requestQuickTransactionSettlement = async (req, res) => {
  try {
    const { id } = req.params;
    const userEmail = req.user.email;
    const quickTransaction = await QuickTransaction.findById(id);

    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }
    if (!quickTransaction.users.includes(userEmail)) {
      return res.status(403).json({ error: 'User not authorized for this transaction' });
    }
    if (quickTransaction.cleared) {
      return res.status(400).json({ error: 'This quick transaction is already settled' });
    }
    if (quickTransaction.settlementStatus === 'pending') {
      return res.status(400).json({ error: 'Settlement request is already pending' });
    }

    quickTransaction.settlementStatus = 'pending';
    quickTransaction.settlementRequestedBy = userEmail;
    quickTransaction.settlementRequestedAt = new Date();
    quickTransaction.settlementRespondedBy = null;
    quickTransaction.settlementRespondedAt = null;
    await quickTransaction.save();
    await logQuickTransactionActivity(
      req.user._id,
      'quick_transaction_settlement_requested',
      quickTransaction
    );

    return res.status(200).json({
      message: 'Settlement request sent successfully',
      quickTransaction,
    });
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }
};

exports.respondQuickTransactionSettlement = async (req, res) => {
  try {
    const { id } = req.params;
    const { action } = req.body;
    const userEmail = req.user.email;
    const quickTransaction = await QuickTransaction.findById(id);

    if (!quickTransaction) {
      return res.status(404).json({ error: 'Quick transaction not found' });
    }
    if (!quickTransaction.users.includes(userEmail)) {
      return res.status(403).json({ error: 'User not authorized for this transaction' });
    }
    if (quickTransaction.settlementStatus !== 'pending') {
      return res.status(400).json({ error: 'No pending settlement request found' });
    }
    if (
      quickTransaction.settlementRequestedBy &&
      quickTransaction.settlementRequestedBy.toLowerCase() === userEmail.toLowerCase()
    ) {
      return res.status(400).json({ error: 'You cannot respond to your own settlement request' });
    }

    const normalizedAction = (action || '').toString().toLowerCase();
    if (!['accept', 'reject'].includes(normalizedAction)) {
      return res.status(400).json({ error: 'Action must be accept or reject' });
    }

    quickTransaction.settlementRespondedBy = userEmail;
    quickTransaction.settlementRespondedAt = new Date();

    if (normalizedAction === 'accept') {
      quickTransaction.cleared = true;
      quickTransaction.settlementStatus = 'accepted';
      await quickTransaction.save();
      await logQuickTransactionActivity(
        req.user._id,
        'quick_transaction_settlement_accepted',
        quickTransaction
      );
      return res.status(200).json({
        message: 'Settlement accepted successfully',
        quickTransaction,
      });
    }

    quickTransaction.settlementStatus = 'rejected';
    quickTransaction.cleared = false;
    await quickTransaction.save();
    await logQuickTransactionActivity(
      req.user._id,
      'quick_transaction_settlement_rejected',
      quickTransaction
    );
    return res.status(200).json({
      message: 'Settlement rejected successfully',
      quickTransaction,
    });
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }
};

exports.clearAllQuickTransactions = async (req, res) => {
  try {
    const userEmail = req.user.email;
    await QuickTransaction.deleteMany({ users: userEmail });
    await logQuickTransactionActivity(req.user._id, 'quick_transaction_cleared_all', {});
    res.status(200).json({ message: 'All quick transactions cleared successfully' });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};
