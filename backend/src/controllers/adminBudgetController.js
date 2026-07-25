const Budget         = require('../models/budget');
const BudgetRecurring = require('../models/budgetRecurring');
const User           = require('../models/user');
const QuickTransaction = require('../models/quickTransaction');
const Transaction    = require('../models/transaction');

// GET /admin/budget/overview
exports.getBudgetOverview = async (req, res) => {
  try {
    const now    = new Date();
    const year   = now.getFullYear();
    const month  = now.getMonth() + 1;

    const [totalUsers, budgetsThisMonth, recurringItems] = await Promise.all([
      User.countDocuments({ role: { $ne: 'admin' } }),
      Budget.find({ year, month }).lean(),
      BudgetRecurring.find({ isActive: true }).lean(),
    ]);

    const usersWithBudget = new Set(budgetsThisMonth.map(b => b.user?.toString())).size;

    // Compute spending per user to check overspending
    const userIds = budgetsThisMonth.map(b => b.user?.toString()).filter(Boolean);
    const monthStart = new Date(year, month - 1, 1);
    const monthEnd   = new Date(year, month, 0, 23, 59, 59, 999);

    const [quickTxns, secureTxns] = await Promise.all([
      QuickTransaction.find({ date: { $gte: monthStart, $lte: monthEnd } }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart, $lte: monthEnd } }).lean(),
    ]);

    const spendMap = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const uid = (t.user || t.userId)?.toString();
      if (!uid) continue;
      spendMap[uid] = (spendMap[uid] || 0) + (t.amount || 0);
    }

    let overspendingCount = 0;
    let totalBudgetLimit  = 0;
    let totalSpent        = 0;
    const categoryUsage   = {};

    for (const b of budgetsThisMonth) {
      const uid   = b.user?.toString();
      const spent = spendMap[uid] || 0;
      const total = Object.values(b.limits || {}).reduce((s, v) => s + v, 0);
      totalBudgetLimit += total;
      totalSpent += spent;
      if (total > 0 && spent > total) overspendingCount++;

      for (const [cat, limit] of Object.entries(b.limits || {})) {
        if (!categoryUsage[cat]) categoryUsage[cat] = { totalLimit: 0, count: 0 };
        categoryUsage[cat].totalLimit += limit;
        categoryUsage[cat].count++;
      }
    }

    const categories = Object.entries(categoryUsage)
      .map(([cat, { totalLimit, count }]) => ({
        category: cat,
        avgLimit: Math.round(totalLimit / count),
        usersWithLimit: count,
      }))
      .sort((a, b) => b.usersWithLimit - a.usersWithLimit);

    // Recurring breakdown by category
    const recurringByCat = {};
    for (const r of recurringItems) {
      const c = r.category || 'Other';
      if (!recurringByCat[c]) recurringByCat[c] = { count: 0, totalAmount: 0 };
      recurringByCat[c].count++;
      recurringByCat[c].totalAmount += r.amount || 0;
    }

    res.json({
      totalUsers,
      usersWithBudget,
      budgetAdoptionPct: totalUsers > 0 ? Math.round((usersWithBudget / totalUsers) * 100) : 0,
      overspendingCount,
      complianceRate: usersWithBudget > 0
        ? Math.round(((usersWithBudget - overspendingCount) / usersWithBudget) * 100) : 100,
      totalBudgetLimit: Math.round(totalBudgetLimit),
      totalSpent:       Math.round(totalSpent),
      recurringItemsCount: recurringItems.length,
      categories,
      recurringByCategory: Object.entries(recurringByCat).map(([cat, v]) => ({
        category: cat, count: v.count, totalAmount: Math.round(v.totalAmount),
      })).sort((a, b) => b.count - a.count),
    });
  } catch (err) {
    console.error('Admin budget overview error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/budget/users?search=&page=1&limit=20
exports.getBudgetUsers = async (req, res) => {
  try {
    const now   = new Date();
    const year  = now.getFullYear();
    const month = now.getMonth() + 1;
    const page  = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, parseInt(req.query.limit, 10) || 20);
    const search = (req.query.search || '').trim();

    const userQuery = { role: { $ne: 'admin' } };
    if (search) {
      userQuery.$or = [
        { email: { $regex: search, $options: 'i' } },
        { name:  { $regex: search, $options: 'i' } },
      ];
    }

    const [users, total] = await Promise.all([
      User.find(userQuery).select('_id name email').skip((page - 1) * limit).limit(limit).lean(),
      User.countDocuments(userQuery),
    ]);

    const userIds = users.map(u => u._id);
    const budgets = await Budget.find({ year, month, user: { $in: userIds } }).lean();
    const budgetMap = {};
    for (const b of budgets) budgetMap[b.user?.toString()] = b;

    const monthStart = new Date(year, month - 1, 1);
    const monthEnd   = new Date(year, month, 0, 23, 59, 59, 999);
    const [quickTxns, secureTxns] = await Promise.all([
      QuickTransaction.find({ date: { $gte: monthStart, $lte: monthEnd }, user: { $in: userIds } }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart, $lte: monthEnd }, user: { $in: userIds } }).lean(),
    ]);
    const spendMap = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const uid = (t.user || t.userId)?.toString();
      if (!uid) continue;
      spendMap[uid] = (spendMap[uid] || 0) + (t.amount || 0);
    }

    const rows = users.map(u => {
      const uid    = u._id.toString();
      const budget = budgetMap[uid];
      const spent  = spendMap[uid] || 0;
      const totalLimit = budget ? Object.values(budget.limits || {}).reduce((s, v) => s + v, 0) : 0;
      return {
        userId:     uid,
        name:       u.name,
        email:      u.email,
        hasBudget:  !!budget,
        totalLimit: Math.round(totalLimit),
        spent:      Math.round(spent),
        usedPct:    totalLimit > 0 ? Math.round((spent / totalLimit) * 100) : null,
        isOver:     totalLimit > 0 && spent > totalLimit,
        categories: budget ? Object.keys(budget.limits || {}).length : 0,
      };
    });

    res.json({ rows, total, page, pages: Math.ceil(total / limit) });
  } catch (err) {
    console.error('Admin budget users error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// PATCH /admin/budget/user/:userId/limits
// Admin overrides a user's budget limits for the current month
exports.setUserBudgetLimits = async (req, res) => {
  try {
    const { userId } = req.params;
    const { limits, year: y, month: m } = req.body;

    if (!limits || typeof limits !== 'object') {
      return res.status(400).json({ message: 'limits object required' });
    }

    const now   = new Date();
    const year  = y ?? now.getFullYear();
    const month = m ?? (now.getMonth() + 1);

    const user = await User.findById(userId).select('_id name email').lean();
    if (!user) return res.status(404).json({ message: 'User not found' });

    const sanitized = {};
    for (const [cat, val] of Object.entries(limits)) {
      const n = parseFloat(val);
      if (!isNaN(n) && n >= 0) sanitized[cat] = n;
    }

    const budget = await Budget.findOneAndUpdate(
      { user: userId, year, month },
      {
        $set: {
          limits: sanitized,
          updatedBy: req.admin._id,
          adminOverride: true,
        },
      },
      { upsert: true, new: true },
    );

    res.json({ message: 'Budget limits updated', budget });
  } catch (err) {
    console.error('Admin set budget limits error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/budget/user/:userId
exports.getUserBudgetDetail = async (req, res) => {
  try {
    const { userId } = req.params;
    const now   = new Date();
    const year  = parseInt(req.query.year, 10) || now.getFullYear();
    const month = parseInt(req.query.month, 10) || (now.getMonth() + 1);

    const user = await User.findById(userId).select('name email').lean();
    if (!user) return res.status(404).json({ message: 'User not found' });

    const [budget, recurringItems] = await Promise.all([
      Budget.findOne({ user: userId, year, month }).lean(),
      BudgetRecurring.find({ user: userId, isActive: true }).lean(),
    ]);

    const monthStart = new Date(year, month - 1, 1);
    const monthEnd   = new Date(year, month, 0, 23, 59, 59, 999);
    const [quickTxns, secureTxns] = await Promise.all([
      QuickTransaction.find({ date: { $gte: monthStart, $lte: monthEnd }, user: userId }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart, $lte: monthEnd }, user: userId }).lean(),
    ]);

    const catSpend = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const c = (t.category || 'other').toLowerCase();
      catSpend[c] = (catSpend[c] || 0) + (t.amount || 0);
    }

    const limits = budget?.limits || {};
    const categories = Array.from(new Set([...Object.keys(limits), ...Object.keys(catSpend)]))
      .map(cat => ({
        category:   cat,
        limit:      limits[cat] || null,
        spent:      Math.round(catSpend[cat] || 0),
        remaining:  limits[cat] ? Math.round(limits[cat] - (catSpend[cat] || 0)) : null,
        usedPct:    limits[cat] ? Math.round(((catSpend[cat] || 0) / limits[cat]) * 100) : null,
      }))
      .sort((a, b) => (b.spent || 0) - (a.spent || 0));

    res.json({
      user: { id: userId, name: user.name, email: user.email },
      year, month,
      categories,
      recurringItems,
      adminOverride: budget?.adminOverride ?? false,
    });
  } catch (err) {
    console.error('Admin user budget detail error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/budget/subscriptions?page=1&limit=30
exports.getAllSubscriptions = async (req, res) => {
  try {
    const page  = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, parseInt(req.query.limit, 10) || 30);

    const [items, total] = await Promise.all([
      BudgetRecurring.find({ isActive: true, category: 'Subscription' })
        .populate('user', 'name email')
        .skip((page - 1) * limit).limit(limit)
        .sort({ createdAt: -1 }).lean(),
      BudgetRecurring.countDocuments({ isActive: true, category: 'Subscription' }),
    ]);

    res.json({
      subscriptions: items.map(r => ({
        id:       r._id,
        name:     r.name,
        amount:   r.amount,
        dueDay:   r.dueDay,
        user:     r.user ? { id: r.user._id, name: r.user.name, email: r.user.email } : null,
        createdAt: r.createdAt,
      })),
      total, page, pages: Math.ceil(total / limit),
    });
  } catch (err) {
    console.error('Admin subscriptions error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};
