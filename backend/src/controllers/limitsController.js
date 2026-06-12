const Subscription = require('../models/subscription');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const Chat = require('../models/chat');
const GroupChat = require('../models/groupChat');
const User = require('../models/user');

const getTodayRange = () => {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date();
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

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

exports.getDailyLimits = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('email');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const subscribed = await isSubscribed(user._id);
    const { start, end } = getTodayRange();

    const quickUsed = await QuickTransaction.countDocuments({
      creatorEmail: user.email,
      createdAt: { $gte: start, $lte: end },
    });
    const userTxUsed = await Transaction.countDocuments({
      userEmail: user.email,
      createdAt: { $gte: start, $lte: end },
    });
    const groupUsed = await GroupTransaction.countDocuments({
      creator: user._id,
      createdAt: { $gte: start, $lte: end },
    });

    res.json({
      subscribed,
      limits: {
        quickTransactions: {
          limit: 3,
          used: quickUsed,
          remaining: Math.max(0, 3 - quickUsed),
        },
        userTransactions: {
          limit: 2,
          used: userTxUsed,
          remaining: Math.max(0, 2 - userTxUsed),
        },
        groupCreations: {
          limit: 1,
          used: groupUsed,
          remaining: Math.max(0, 1 - groupUsed),
        },
      },
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getTransactionMessageLimit = async (req, res) => {
  try {
    const { transactionId } = req.params;
    const subscribed = await isSubscribed(req.user._id);
    const { start, end } = getTodayRange();
    const used = await Chat.countDocuments({
      transactionId,
      senderId: req.user._id,
      createdAt: { $gte: start, $lte: end },
    });
    res.json({
      subscribed,
      limit: 3,
      used,
      remaining: Math.max(0, 3 - used),
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getGroupMessageLimit = async (req, res) => {
  try {
    const { groupId } = req.params;
    const subscribed = await isSubscribed(req.user._id);
    const { start, end } = getTodayRange();
    const used = await GroupChat.countDocuments({
      groupTransactionId: groupId,
      senderId: req.user._id,
      createdAt: { $gte: start, $lte: end },
    });
    res.json({
      subscribed,
      limit: 3,
      used,
      remaining: Math.max(0, 3 - used),
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getGroupExpenseLimit = async (req, res) => {
  try {
    const { groupId } = req.params;
    const user = await User.findById(req.user._id).select('email');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const subscribed = await isSubscribed(req.user._id);
    const { start, end } = getTodayRange();
    const group = await GroupTransaction.findById(groupId).select('expenses');
    if (!group) return res.status(404).json({ error: 'Group not found' });

    const used = (group.expenses || []).filter((e) => {
      if (!e || !e.addedBy || !e.date) return false;
      const expenseDate = new Date(e.date);
      return (
        e.addedBy === user.email &&
        expenseDate >= start &&
        expenseDate <= end
      );
    }).length;

    res.json({
      subscribed,
      limit: 3,
      used,
      remaining: Math.max(0, 3 - used),
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
