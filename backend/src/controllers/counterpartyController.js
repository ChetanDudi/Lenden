const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');

exports.getUserCounterparties = async (req, res) => {
  try {
    const { email, search, sortBy, gender } = req.query;
    if (!email) return res.status(400).json({ error: 'Email is required' });

    // Only allow requesting own counterparties
    if (req.user?.email?.toLowerCase() !== email.toLowerCase()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const user = await User.findOne({ email }).select('_id');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const [transactions, quickTransactions, groups] = await Promise.all([
      Transaction.find({ $or: [{ userEmail: email }, { counterpartyEmail: email }] })
        .select('counterpartyEmail userEmail').lean(),
      QuickTransaction.find({ users: email }).select('users').lean(),
      GroupTransaction.find({ 'members.user': user._id })
        .populate('members.user', 'email').select('members').lean(),
    ]);

    const counts = {};
    transactions.forEach((t) => {
      const cp = t.userEmail === email ? t.counterpartyEmail : t.userEmail;
      if (cp && cp !== email) counts[cp] = (counts[cp] || 0) + 1;
    });
    quickTransactions.forEach((t) => {
      (t.users || []).filter((u) => u && u !== email).forEach((cp) => {
        counts[cp] = (counts[cp] || 0) + 1;
      });
    });
    groups.forEach((g) => {
      (g.members || []).map((m) => m.user?.email)
        .filter((e) => e && e !== email)
        .forEach((cp) => { counts[cp] = (counts[cp] || 0) + 1; });
    });

    const cpEmails = Object.keys(counts);
    if (cpEmails.length === 0) return res.json({ counterparties: [] });

    // Populate all profiles in one query
    const profileFilter = { email: { $in: cpEmails } };
    if (gender) profileFilter.gender = gender;
    if (search && search.trim()) {
      const re = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      profileFilter.$or = [{ name: re }, { email: re }, { phone: re }];
    }

    const profiles = await User.find(profileFilter)
      .select('name email gender phone birthday profileImage avgRating memberSince')
      .lean();

    let counterpartiesList = profiles.map((p) => ({
      _id: p._id.toString(),
      email: p.email,
      name: p.name,
      gender: p.gender || null,
      phone: p.phone || null,
      birthday: p.birthday || null,
      avgRating: p.avgRating || 0,
      memberSince: p.memberSince || null,
      profileImage: p.profileImage
        ? `${req.protocol}://${req.get('host')}/api/users/${p._id}/profile-image`
        : null,
      count: counts[p.email] || 0,
    }));

    // Sort
    switch (sortBy) {
      case 'name_asc':
        counterpartiesList.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
        break;
      case 'count_asc':
        counterpartiesList.sort((a, b) => a.count - b.count);
        break;
      default: // count_desc (default)
        counterpartiesList.sort((a, b) => b.count - a.count);
    }

    res.json({ counterparties: counterpartiesList.slice(0, 100) });
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
