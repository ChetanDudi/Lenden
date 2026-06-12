const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');

exports.getUserCounterparties = async (req, res) => {
  try {
    const { email } = req.query;
    if (!email) return res.status(400).json({ error: 'Email is required' });

    // Only allow requesting own counterparties
    if (req.user?.email?.toLowerCase() !== email.toLowerCase()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const user = await User.findOne({ email }).select('_id');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const transactions = await Transaction.find({
      $or: [{ userEmail: email }, { counterpartyEmail: email }],
    }).lean();

    const quickTransactions = await QuickTransaction.find({
      users: email,
    }).lean();

    const groups = await GroupTransaction.find({
      'members.user': user._id,
    })
      .populate('members.user', 'email')
      .lean();

    let counterparties = {};

    transactions.forEach((t) => {
      const cp = t.counterpartyEmail;
      if (cp) counterparties[cp] = (counterparties[cp] || 0) + 1;
    });

    quickTransactions.forEach((t) => {
      const others = (t.users || []).filter((u) => u && u !== email);
      others.forEach((cp) => {
        counterparties[cp] = (counterparties[cp] || 0) + 1;
      });
    });

    groups.forEach((g) => {
      const members = (g.members || [])
        .map((m) => m.user?.email)
        .filter((e) => e && e !== email);
      members.forEach((cp) => {
        counterparties[cp] = (counterparties[cp] || 0) + 1;
      });
    });

    const counterpartiesList = Object.entries(counterparties)
      .map(([k, v]) => ({ email: k, count: v }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 100);

    res.json({ counterparties: counterpartiesList });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getCounterpartyStats = async (req, res) => {
  try {
    const { email, counterpartyEmail } = req.query;
    if (!email || !counterpartyEmail) {
      return res
        .status(400)
        .json({ error: 'email and counterpartyEmail are required' });
    }

    if (req.user?.email?.toLowerCase() !== email.toLowerCase()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const user = await User.findOne({ email }).select('_id');
    const counterparty = await User.findOne({ email: counterpartyEmail }).select(
      '_id'
    );

    const userTxCount = await require('../models/transaction').countDocuments({
      $or: [
        { userEmail: email, counterpartyEmail },
        { userEmail: counterpartyEmail, counterpartyEmail: email },
      ],
    });

    const quickTxCount = await require('../models/quickTransaction').countDocuments(
      {
        users: { $all: [email, counterpartyEmail] },
      }
    );

    let groupCount = 0;
    if (user && counterparty) {
      groupCount = await require('../models/groupTransaction').countDocuments({
        'members.user': { $all: [user._id, counterparty._id] },
      });
    }

    res.json({
      userTransactions: userTxCount,
      quickTransactions: quickTxCount,
      groups: groupCount,
      total: userTxCount + quickTxCount + groupCount,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getCounterpartyStatsBatch = async (req, res) => {
  try {
    const { email, counterparties } = req.body || {};
    if (!email || !Array.isArray(counterparties)) {
      return res
        .status(400)
        .json({ error: 'email and counterparties[] are required' });
    }
    if (req.user?.email?.toLowerCase() !== email.toLowerCase()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Build interaction counts for the current user once
    const transactions = await require('../models/transaction').find({
      $or: [{ userEmail: email }, { counterpartyEmail: email }],
    }).lean();
    const quickTransactions = await require('../models/quickTransaction').find({
      users: email,
    }).lean();
    const user = await User.findOne({ email }).select('_id');
    const groups = user
      ? await require('../models/groupTransaction')
          .find({ 'members.user': user._id })
          .populate('members.user', 'email')
          .lean()
      : [];

    const counts = {};
    const normalize = (val) => (val || '').toString().toLowerCase().trim();
    transactions.forEach((t) => {
      const cp = t.userEmail === email ? t.counterpartyEmail : t.userEmail;
      const key = normalize(cp);
      if (key) counts[key] = (counts[key] || 0) + 1;
    });
    quickTransactions.forEach((t) => {
      const others = (t.users || []).filter((u) => u && u !== email);
      others.forEach((cp) => {
        const key = normalize(cp);
        if (key) counts[key] = (counts[key] || 0) + 1;
      });
    });
    groups.forEach((g) => {
      const members = (g.members || [])
        .map((m) => m.user?.email)
        .filter((e) => e && e !== email);
      members.forEach((cp) => {
        const key = normalize(cp);
        if (key) counts[key] = (counts[key] || 0) + 1;
      });
    });

    const response = {};
    counterparties.forEach((cp) => {
      const key = normalize(cp);
      response[key] = counts[key] || 0;
    });

    res.json({ counts: response });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
