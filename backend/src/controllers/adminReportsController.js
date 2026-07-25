const QuickTransaction = require('../models/quickTransaction');
const Transaction      = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const User             = require('../models/user');

const fmt = (n) => Math.round(n).toLocaleString('en-IN');
const MONTH_NAMES = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

const parsePeriod = (query) => {
  const now   = new Date();
  const start = query.startDate ? new Date(query.startDate) : new Date(now.getFullYear(), now.getMonth() - 2, 1);
  const end   = query.endDate   ? new Date(query.endDate)   : now;
  return { start, end };
};

// GET /admin/reports/platform
exports.getPlatformOverview = async (req, res) => {
  try {
    const { start, end } = parsePeriod(req.query);

    const [quickTxns, secureTxns, groupsAll, totalUsers] = await Promise.all([
      QuickTransaction.find({ date: { $gte: start, $lte: end } }).lean(),
      Transaction.find({ createdAt: { $gte: start, $lte: end } }).lean(),
      GroupTransaction.find({ createdAt: { $gte: start, $lte: end } }).lean(),
      User.countDocuments({ role: { $ne: 'admin' } }),
    ]);

    const quickLent     = quickTxns.filter(t => t.role === 'lender').reduce((s, t) => s + t.amount, 0);
    const quickBorrowed = quickTxns.filter(t => t.role === 'borrower').reduce((s, t) => s + t.amount, 0);
    const secureLent    = secureTxns.filter(t => t.role === 'lender').reduce((s, t) => s + t.amount, 0);
    const secureBorrowed = secureTxns.filter(t => t.role === 'borrower').reduce((s, t) => s + t.amount, 0);

    const groupExpenses = groupsAll.flatMap(g => g.expenses || [])
      .filter(e => { const d = new Date(e.date); return d >= start && d <= end; });
    const groupVolume = groupExpenses.reduce((s, e) => s + (e.amount || 0), 0);

    const allAmounts = [
      ...quickTxns.map(t => t.amount || 0),
      ...secureTxns.map(t => t.amount || 0),
    ].filter(a => a > 0);

    const avgTxn = allAmounts.length > 0
      ? Math.round(allAmounts.reduce((s, v) => s + v, 0) / allAmounts.length) : 0;
    const maxTxn = allAmounts.length > 0 ? Math.max(...allAmounts) : 0;

    // Category breakdown (from quick + secure)
    const catMap = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const c = (t.category || 'other').toLowerCase();
      catMap[c] = (catMap[c] || 0) + (t.amount || 0);
    }
    const categories = Object.entries(catMap)
      .map(([cat, amount]) => ({ category: cat, amount: Math.round(amount) }))
      .sort((a, b) => b.amount - a.amount);

    // Monthly trend (last 6 months)
    const monthlyTrend = [];
    for (let i = 5; i >= 0; i--) {
      const mStart = new Date(end.getFullYear(), end.getMonth() - i, 1);
      const mEnd   = new Date(end.getFullYear(), end.getMonth() - i + 1, 0, 23, 59, 59, 999);
      const qm = quickTxns.filter(t => { const d = new Date(t.date); return d >= mStart && d <= mEnd; });
      const sm = secureTxns.filter(t => { const d = new Date(t.createdAt); return d >= mStart && d <= mEnd; });
      monthlyTrend.push({
        label: MONTH_NAMES[mStart.getMonth()],
        quick: Math.round(qm.reduce((s, t) => s + t.amount, 0)),
        secure: Math.round(sm.reduce((s, t) => s + t.amount, 0)),
        count: qm.length + sm.length,
      });
    }

    res.json({
      period: { start, end },
      summary: {
        totalUsers,
        quickTransactions: quickTxns.length,
        secureTransactions: secureTxns.length,
        groupTransactions: groupsAll.length,
        totalVolume: Math.round(quickLent + quickBorrowed + secureLent + secureBorrowed),
        quickVolume: Math.round(quickLent + quickBorrowed),
        secureVolume: Math.round(secureLent + secureBorrowed),
        groupVolume: Math.round(groupVolume),
        avgTransactionSize: avgTxn,
        maxTransactionSize: Math.round(maxTxn),
        quickLent: Math.round(quickLent),
        quickBorrowed: Math.round(quickBorrowed),
        secureLent: Math.round(secureLent),
        secureBorrowed: Math.round(secureBorrowed),
      },
      categories,
      monthlyTrend,
    });
  } catch (err) {
    console.error('Admin reports overview error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/reports/top-users?limit=20&sort=volume
exports.getTopUsers = async (req, res) => {
  try {
    const limit  = Math.min(parseInt(req.query.limit, 10) || 20, 50);
    const { start, end } = parsePeriod(req.query);

    const [quickTxns, secureTxns] = await Promise.all([
      QuickTransaction.find({ date: { $gte: start, $lte: end } }).lean(),
      Transaction.find({ createdAt: { $gte: start, $lte: end } }).lean(),
    ]);

    const userMap = {};
    const touch = (email) => {
      if (!userMap[email]) userMap[email] = { email, lent: 0, borrowed: 0, count: 0 };
    };

    for (const t of quickTxns) {
      if (t.users) {
        const [u1, u2] = t.users;
        if (t.role === 'lender' && u1) { touch(u1); userMap[u1].lent += t.amount || 0; userMap[u1].count++; }
        if (t.role === 'borrower' && u1) { touch(u1); userMap[u1].borrowed += t.amount || 0; userMap[u1].count++; }
      }
      if (t.creatorEmail) { touch(t.creatorEmail); }
    }
    for (const t of secureTxns) {
      if (t.userEmail) {
        touch(t.userEmail);
        if (t.role === 'lender') userMap[t.userEmail].lent += t.amount || 0;
        else userMap[t.userEmail].borrowed += t.amount || 0;
        userMap[t.userEmail].count++;
      }
    }

    const users = await User.find({ email: { $in: Object.keys(userMap) } })
      .select('name email profilePhoto').lean();
    const nameMap = {};
    for (const u of users) nameMap[u.email] = u.name || u.email;

    const sorted = Object.values(userMap)
      .map(u => ({
        email: u.email,
        name: nameMap[u.email] || u.email,
        lent:     Math.round(u.lent),
        borrowed: Math.round(u.borrowed),
        volume:   Math.round(u.lent + u.borrowed),
        count:    u.count,
      }))
      .sort((a, b) => b.volume - a.volume)
      .slice(0, limit);

    res.json({ topUsers: sorted, period: { start, end } });
  } catch (err) {
    console.error('Admin top users error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/reports/category-trends
exports.getCategoryTrends = async (req, res) => {
  try {
    const now = new Date();
    const thisMonthStart = new Date(now.getFullYear(), now.getMonth(), 1);
    const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);

    const [thisQ, lastQ, thisS, lastS] = await Promise.all([
      QuickTransaction.find({ date: { $gte: thisMonthStart } }).lean(),
      QuickTransaction.find({ date: { $gte: lastMonthStart, $lt: thisMonthStart } }).lean(),
      Transaction.find({ createdAt: { $gte: thisMonthStart } }).lean(),
      Transaction.find({ createdAt: { $gte: lastMonthStart, $lt: thisMonthStart } }).lean(),
    ]);

    const buildCatMap = (txns) => {
      const m = {};
      for (const t of txns) {
        const c = (t.category || 'other').toLowerCase();
        m[c] = (m[c] || 0) + (t.amount || 0);
      }
      return m;
    };

    const thisMap = buildCatMap([...thisQ, ...thisS]);
    const lastMap = buildCatMap([...lastQ, ...lastS]);
    const cats = new Set([...Object.keys(thisMap), ...Object.keys(lastMap)]);

    const trends = Array.from(cats).map(cat => {
      const thisAmt = Math.round(thisMap[cat] || 0);
      const lastAmt = Math.round(lastMap[cat] || 0);
      const change  = lastAmt > 0 ? Math.round(((thisAmt - lastAmt) / lastAmt) * 100) : null;
      return { category: cat, thisMonth: thisAmt, lastMonth: lastAmt, change };
    }).sort((a, b) => b.thisMonth - a.thisMonth);

    res.json({ trends, month: MONTH_NAMES[now.getMonth()] });
  } catch (err) {
    console.error('Admin category trends error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/reports/user/:userId
exports.getUserReport = async (req, res) => {
  try {
    const { userId } = req.params;
    const { start, end } = parsePeriod(req.query);

    const user = await User.findById(userId).select('name email').lean();
    if (!user) return res.status(404).json({ message: 'User not found' });

    const email = user.email;
    const [quickTxns, secureTxns] = await Promise.all([
      QuickTransaction.find({ creatorEmail: email, date: { $gte: start, $lte: end } }).lean(),
      Transaction.find({ userEmail: email, createdAt: { $gte: start, $lte: end } }).lean(),
    ]);

    const lent     = quickTxns.filter(t => t.role === 'lender').reduce((s, t) => s + t.amount, 0);
    const borrowed = quickTxns.filter(t => t.role === 'borrower').reduce((s, t) => s + t.amount, 0);
    const secLent  = secureTxns.filter(t => t.role === 'lender').reduce((s, t) => s + t.amount, 0);
    const secBor   = secureTxns.filter(t => t.role === 'borrower').reduce((s, t) => s + t.amount, 0);

    const catMap = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const c = (t.category || 'other').toLowerCase();
      catMap[c] = (catMap[c] || 0) + (t.amount || 0);
    }
    const categories = Object.entries(catMap)
      .map(([cat, amount]) => ({ category: cat, amount: Math.round(amount) }))
      .sort((a, b) => b.amount - a.amount);

    res.json({
      user: { id: userId, name: user.name, email },
      period: { start, end },
      quick:  { lent: Math.round(lent), borrowed: Math.round(borrowed), count: quickTxns.length },
      secure: { lent: Math.round(secLent), borrowed: Math.round(secBor), count: secureTxns.length },
      categories,
      totalVolume: Math.round(lent + borrowed + secLent + secBor),
      netBalance: Math.round(lent + secLent - borrowed - secBor),
    });
  } catch (err) {
    console.error('Admin user report error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/reports/search-users?q=
exports.searchUsers = async (req, res) => {
  try {
    const q = (req.query.q || '').trim();
    if (!q) return res.json({ users: [] });
    const users = await User.find({
      role: { $ne: 'admin' },
      $or: [
        { email: { $regex: q, $options: 'i' } },
        { name:  { $regex: q, $options: 'i' } },
      ],
    }).select('_id name email').limit(10).lean();
    res.json({ users });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};
