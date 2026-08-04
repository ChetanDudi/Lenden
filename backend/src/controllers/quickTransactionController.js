const mongoose = require('mongoose');
const QuickTransaction = require('../models/quickTransaction');
const User = require('../models/user');
const WalletTransaction = require('../models/walletTransaction');
const { logQuickTransactionActivity } = require('./activityController');
const { awardGiftCard, shouldAwardGiftCard } = require('./userGiftCardController');
const { processReferralRewardOnFirstCreation } = require('../utils/referralService');
const { validateCoinCreationAccess } = require('../utils/coinUsageGuard');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { FEATURES, hasFeature } = require('../utils/subscriptionFeatures');
const Notification = require('../models/notification');
const { getCoinPricing } = require('../utils/coinPricing');
const { sendToUser } = require('../services/notificationService');

const { isBlockedBy } = require('../utils/userHelpers');
const { getTodayRange } = require('../utils/dateHelpers');

const isSubscribed = (userId) => hasFeature(userId, FEATURES.QUICK_TRANSACTIONS);

const resetSettlementState = (quickTransaction) => {
  quickTransaction.settlementStatus = 'none';
  quickTransaction.settlementRequestedBy = null;
  quickTransaction.settlementRequestedAt = null;
  quickTransaction.settlementRespondedBy = null;
  quickTransaction.settlementRespondedAt = null;
};

exports.createQuickTransaction = async (req, res) => {
  try {
    const { amount, currency, date, time, description, counterpartyEmail, role, category, isScheduled, scheduledAt } = req.body;

    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'amount must be a positive number' });
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!counterpartyEmail || !emailRegex.test(counterpartyEmail)) {
      return res.status(400).json({ error: 'Valid counterpartyEmail is required' });
    }

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

    const scheduledDate = isScheduled && scheduledAt ? new Date(scheduledAt) : null;
    const quickTransaction = new QuickTransaction({
      amount,
      currency,
      date,
      time,
      description,
      users: [userEmail, counterpartyEmail],
      creatorEmail: userEmail,
      role,
      category: category || 'other',
      isScheduled: !!(isScheduled && scheduledDate),
      scheduledAt: scheduledDate,
      scheduledStatus: (isScheduled && scheduledDate) ? 'pending' : null,
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

    // Notify counterparty fire-and-forget
    User.findById(counterparty._id).select('notificationSettings').then(cp => {
      if (cp?.notificationSettings?.transactionNotifications !== false) {
        return Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [counterparty._id], recipientModel: 'User', category: 'transaction',
          message: `${userEmail} recorded a quick transaction with you for ${amount} ${currency}.`,
        });
      }
    }).catch(() => {});
    sendToUser(User, counterparty._id, { title: 'New Transaction 📝', body: `${userEmail} recorded a transaction with you.`, data: { type: 'quick_transaction' } });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.createQuickTransactionWithCoins = async (req, res) => {
  const pricing = await getCoinPricing();
  const QUICK_TRANSACTION_COST = pricing.quickTransactionCost;
  const QUICK_TRANSACTION_DAILY_LIMIT = 3;
  try {
    const { amount, currency, date, time, description, counterpartyEmail, role, category, isScheduled, scheduledAt } = req.body;

    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'amount must be a positive number' });
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!counterpartyEmail || !emailRegex.test(counterpartyEmail)) {
      return res.status(400).json({ error: 'Valid counterpartyEmail is required' });
    }

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

    const updatedUser = await User.findOneAndUpdate(
      { _id: user._id, lenDenCoins: { $gte: QUICK_TRANSACTION_COST } },
      { $inc: { lenDenCoins: -QUICK_TRANSACTION_COST } },
      { new: true }
    );
    if (!updatedUser) {
      return res.status(400).json({ error: 'Insufficient LenDen coins to create this quick transaction.' });
    }
    user.lenDenCoins = updatedUser.lenDenCoins;
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

    const scheduledDate2 = isScheduled && scheduledAt ? new Date(scheduledAt) : null;
    const quickTransaction = new QuickTransaction({
      amount,
      currency,
      date,
      time,
      description,
      users: [userEmail, counterpartyEmail],
      creatorEmail: userEmail,
      role,
      category: category || 'other',
      isScheduled: !!(isScheduled && scheduledDate2),
      scheduledAt: scheduledDate2,
      scheduledStatus: (isScheduled && scheduledDate2) ? 'pending' : null,
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

    // Notify counterparty fire-and-forget
    User.findById(counterparty._id).select('notificationSettings').then(cp => {
      if (cp?.notificationSettings?.transactionNotifications !== false) {
        return Notification.create({
          sender: req.user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [counterparty._id], recipientModel: 'User', category: 'transaction',
          message: `${userEmail} recorded a quick transaction with you for ${amount} ${currency}.`,
        });
      }
    }).catch(() => {});
    sendToUser(User, counterparty._id, { title: 'New Transaction 📝', body: `${userEmail} recorded a transaction with you.`, data: { type: 'quick_transaction' } });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.getQuickTransactions = async (req, res) => {
  try {
    const userEmail = req.user.email;
    const {
      search,
      sortBy = 'created_desc',
      filterBy = 'all',
      role = 'all',
      dateFilter = 'all',
      favouritesOnly,
      counterparty,
      category,
    } = req.query;

    // Base query
    const query = { users: userEmail };

    // Clearance filter
    if (filterBy === 'cleared') {
      query.cleared = true;
    } else if (filterBy === 'not_cleared') {
      query.cleared = { $ne: true };
    }

    // Role filter (based on creator's role field)
    if (role === 'lender') {
      query.role = 'lender';
    } else if (role === 'borrower') {
      query.role = 'borrower';
    }

    // Favourites only
    if (favouritesOnly === 'true') {
      query.favourite = userEmail;
    }

    // Counterparty filter
    if (counterparty && counterparty.trim()) {
      query.users = { $all: [userEmail, counterparty.trim()] };
    }

    // Text search pushed to MongoDB
    if (search && search.trim()) {
      const searchRegex = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      const searchConditions = [
        { description: searchRegex },
        { users: searchRegex },
      ];
      query.$and = query.$and ? [...query.$and, { $or: searchConditions }] : [{ $or: searchConditions }];
    }

    // Date filter
    if (dateFilter && dateFilter !== 'all') {
      const now = new Date();
      if (dateFilter === 'today') {
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
        query.$or = [
          { date: { $gte: start, $lt: end } },
          { createdAt: { $gte: start, $lt: end } },
        ];
      } else if (dateFilter === 'week') {
        const dayOfWeek = now.getDay();
        const diff = now.getDate() - (dayOfWeek === 0 ? 6 : dayOfWeek - 1);
        const weekStart = new Date(now.setDate(diff));
        weekStart.setHours(0, 0, 0, 0);
        query.$or = [
          { date: { $gte: weekStart } },
          { createdAt: { $gte: weekStart } },
        ];
      } else if (dateFilter === 'month') {
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
        query.$or = [
          { date: { $gte: monthStart } },
          { createdAt: { $gte: monthStart } },
        ];
      }
    }

    // Category filter
    if (category && category !== 'all') {
      query.category = category;
    }

    // Build sort
    let sortObj = { createdAt: -1 };
    switch (sortBy) {
      case 'created_asc': sortObj = { createdAt: 1 }; break;
      case 'created_desc': sortObj = { createdAt: -1 }; break;
      case 'updated_asc': sortObj = { updatedAt: 1 }; break;
      case 'updated_desc': sortObj = { updatedAt: -1 }; break;
      case 'amount_asc': sortObj = { amount: 1 }; break;
      case 'amount_desc': sortObj = { amount: -1 }; break;
      default: sortObj = { createdAt: -1 };
    }

    const page = Math.max(1, parseInt(req.query.page) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit) || 20));
    const skip = (page - 1) * limit;

    const [quickTransactions, totalCount] = await Promise.all([
      QuickTransaction.find(query).sort(sortObj).skip(skip).limit(limit).lean(),
      QuickTransaction.countDocuments(query),
    ]);

    // Collect all unique emails across all transactions, then fetch in one query
    const allEmails = [...new Set(quickTransactions.flatMap(t => t.users))];
    const userDocs = await User.find({ email: { $in: allEmails } }).select('name email phone').lean();
    const userByEmail = Object.fromEntries(userDocs.map(u => [u.email, u]));

    const populatedTransactions = quickTransactions.map(t => ({
      ...t,
      users: t.users.map(email => {
        const u = userByEmail[email];
        return u ? { name: u.name, email: u.email, phone: u.phone ?? null } : { email };
      }),
    }));

    res.status(200).json({
      quickTransactions: populatedTransactions,
      total: totalCount,
      page,
      limit,
      hasMore: skip + quickTransactions.length < totalCount,
    });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.toggleQuickTransactionFavourite = async (req, res) => {
  try {
    const { id } = req.params;
    const email = req.user.email;

    if (!id) {
      return res.status(400).json({ error: 'Quick transaction ID is required' });
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
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const { amount, currency, date, time, description, role } = req.body;
    const userEmail = req.user.email;

    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'amount must be a positive number' });
    }

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

    quickTransaction.amount = parsedAmount;
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

// Pays the counterparty the full quick-transaction amount via an atomic LenDen
// Wallet transfer — both parties are resolved from the transaction record
// itself (quickTransaction.users), never trusted from the client — then marks
// it settled. Replaces the old flow where the client independently chose
// Razorpay/wallet and called /clear afterward; the backend never verified
// money actually moved, so a buggy/malicious client could mark something
// "cleared" with nothing paid.
exports.payQuickTransaction = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { id } = req.params;
    const payerEmail = (req.user.email || '').toLowerCase().trim();

    const quickTransaction = await QuickTransaction.findById(id);
    if (!quickTransaction) return res.status(404).json({ error: 'Quick transaction not found' });
    if (!quickTransaction.users.some((u) => u.toLowerCase() === payerEmail)) {
      return res.status(403).json({ error: 'User not authorized to pay this transaction' });
    }
    if (quickTransaction.cleared) {
      return res.status(400).json({ error: 'This quick transaction is already settled' });
    }

    const payeeEmail = quickTransaction.users.find((u) => u.toLowerCase() !== payerEmail);
    if (!payeeEmail) {
      return res.status(400).json({ error: 'Could not determine the other party on this transaction' });
    }
    const payee = await User.findOne({ email: payeeEmail.toLowerCase().trim() }).select('_id email');
    if (!payee) return res.status(404).json({ error: 'The other party is no longer on LenDen' });

    const amount = quickTransaction.amount;
    let newBalance;
    await session.withTransaction(async () => {
      // Atomic check-and-debit — fails (returns null) if balance is insufficient,
      // so no partial/overdraft state is possible under concurrent requests.
      const payer = await User.findOneAndUpdate(
        { _id: req.user._id, walletBalance: { $gte: amount } },
        { $inc: { walletBalance: -amount } },
        { new: true, session }
      );
      if (!payer) {
        throw Object.assign(new Error('Insufficient wallet balance'), {
          status: 400,
          userMessage: 'Insufficient LenDen wallet balance. Please top up your wallet and try again.',
        });
      }

      await User.findByIdAndUpdate(payee._id, { $inc: { walletBalance: amount } }, { session });

      await WalletTransaction.create([
        { user: payer._id, type: 'debit', amount, toEmail: payee.email, note: quickTransaction.description || 'Quick transaction settlement', sourceType: 'quick' },
        { user: payee._id, type: 'credit', amount, fromEmail: payer.email, note: quickTransaction.description || 'Quick transaction settlement', sourceType: 'quick' },
      ], { session });

      quickTransaction.cleared = true;
      quickTransaction.settledViaPayment = true;
      quickTransaction.paymentMethod = 'wallet';
      if (quickTransaction.settlementStatus === 'pending') {
        quickTransaction.settlementStatus = 'accepted';
      }
      quickTransaction.settlementRespondedBy = payerEmail;
      quickTransaction.settlementRespondedAt = new Date();
      await quickTransaction.save({ session });

      newBalance = payer.walletBalance;
    });

    await logQuickTransactionActivity(req.user._id, 'quick_transaction_paid', quickTransaction);

    res.status(200).json({ message: 'Payment successful', quickTransaction, balance: newBalance });
  } catch (err) {
    res.status(err.status ?? 500).json({ error: err.userMessage || err.message || 'Server error' });
  } finally {
    session.endSession();
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
      quickTransaction.settlementStatus = 'accepted';
      quickTransaction.cleared = true;
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

exports.getScheduledQuickTransactions = async (req, res) => {
  try {
    const userEmail = req.user.email;
    const scheduled = await QuickTransaction.find({
      users: userEmail,
      isScheduled: true,
    }).sort({ scheduledAt: 1 });
    res.json({ scheduled });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.cancelScheduledQuickTransaction = async (req, res) => {
  try {
    const userEmail = req.user.email;
    const qt = await QuickTransaction.findOne({ _id: req.params.id, users: userEmail, isScheduled: true });
    if (!qt) return res.status(404).json({ error: 'Scheduled transaction not found' });
    qt.scheduledStatus = 'cancelled';
    await qt.save();
    res.json({ success: true });
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
};

exports.getFriendBalances = async (req, res) => {
  try {
    const myEmail = req.user.email;
    const txns = await QuickTransaction.find({ users: myEmail, cleared: { $ne: true } }).lean();

    const balanceMap = {};
    for (const t of txns) {
      const counterpartyEmail = t.creatorEmail === myEmail
        ? t.users.find(u => u !== myEmail)
        : t.creatorEmail;
      if (!counterpartyEmail || counterpartyEmail === myEmail) continue;

      if (!balanceMap[counterpartyEmail]) balanceMap[counterpartyEmail] = 0;

      const isCreator = t.creatorEmail === myEmail;
      const creatorRole = (t.role || '').toLowerCase();
      // positive = they owe me (I lent), negative = I owe them (I borrowed)
      const iLent = (isCreator && creatorRole === 'lender') || (!isCreator && creatorRole === 'borrower');
      balanceMap[counterpartyEmail] += iLent ? (t.amount || 0) : -(t.amount || 0);
    }

    // Resolve names from User docs
    const emails = Object.keys(balanceMap).filter(e => balanceMap[e] !== 0);
    const users = await User.find({ email: { $in: emails } }).select('email name username profilePicture').lean();
    const userMap = {};
    for (const u of users) userMap[u.email] = u;

    const balances = emails
      .map(email => ({
        email,
        name: userMap[email]?.name || userMap[email]?.username || email,
        avatar: userMap[email]?.profilePicture || null,
        net: Math.round(balanceMap[email]),
      }))
      .filter(b => b.net !== 0)
      .sort((a, b) => Math.abs(b.net) - Math.abs(a.net));

    res.json({ balances });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
