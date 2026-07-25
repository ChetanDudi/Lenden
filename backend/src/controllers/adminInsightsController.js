const AdminTip        = require('../models/adminTip');
const User            = require('../models/user');
const Budget          = require('../models/budget');
const QuickTransaction = require('../models/quickTransaction');
const Transaction     = require('../models/transaction');
const Admin           = require('../models/admin');

// GET /admin/insights/platform
exports.getPlatformInsights = async (req, res) => {
  try {
    const now   = new Date();
    const year  = now.getFullYear();
    const month = now.getMonth() + 1;

    const monthStart = new Date(year, month - 1, 1);
    const lastStart  = new Date(year, month - 2, 1);
    const lastEnd    = new Date(year, month - 1, 0, 23, 59, 59, 999);

    const [totalUsers, budgetsThisMonth, quickThisMonth, secureThisMonth,
           quickLastMonth, secureLastMonth, tips] = await Promise.all([
      User.countDocuments({ role: { $ne: 'admin' } }),
      Budget.find({ year, month }).lean(),
      QuickTransaction.find({ date: { $gte: monthStart } }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart } }).lean(),
      QuickTransaction.find({ date: { $gte: lastStart, $lte: lastEnd } }).lean(),
      Transaction.find({ createdAt: { $gte: lastStart, $lte: lastEnd } }).lean(),
      AdminTip.countDocuments({ isActive: true }),
    ]);

    const thisTotal = [...quickThisMonth, ...secureThisMonth].reduce((s, t) => s + (t.amount || 0), 0);
    const lastTotal = [...quickLastMonth, ...secureLastMonth].reduce((s, t) => s + (t.amount || 0), 0);
    const volumeChange = lastTotal > 0 ? Math.round(((thisTotal - lastTotal) / lastTotal) * 100) : null;

    // Avg health score proxy: users with budgets who are under limit
    const userIds = budgetsThisMonth.map(b => b.user?.toString()).filter(Boolean);
    const spendMap = {};
    for (const t of [...quickThisMonth, ...secureThisMonth]) {
      const uid = (t.user || t.userId)?.toString();
      if (uid) spendMap[uid] = (spendMap[uid] || 0) + (t.amount || 0);
    }
    let underBudget = 0;
    for (const b of budgetsThisMonth) {
      const uid = b.user?.toString();
      const total = Object.values(b.limits || {}).reduce((s, v) => s + v, 0);
      if (total > 0 && (spendMap[uid] || 0) <= total) underBudget++;
    }
    const avgHealthScore = budgetsThisMonth.length > 0
      ? Math.round((underBudget / budgetsThisMonth.length) * 100) : 0;

    // Detect anomaly: spending > 2× the user's monthly average
    let anomalyCount = 0;
    for (const [uid, spent] of Object.entries(spendMap)) {
      const b = budgetsThisMonth.find(b => b.user?.toString() === uid);
      if (b) {
        const total = Object.values(b.limits || {}).reduce((s, v) => s + v, 0);
        if (total > 0 && spent > total * 1.5) anomalyCount++;
      }
    }

    // Category breakdown this month
    const catMap = {};
    for (const t of [...quickThisMonth, ...secureThisMonth]) {
      const c = (t.category || 'other').toLowerCase();
      catMap[c] = (catMap[c] || 0) + (t.amount || 0);
    }
    const topCategories = Object.entries(catMap)
      .map(([cat, amount]) => ({ category: cat, amount: Math.round(amount) }))
      .sort((a, b) => b.amount - a.amount).slice(0, 5);

    res.json({
      totalUsers,
      usersWithBudget: budgetsThisMonth.length,
      avgHealthScore,
      anomalyCount,
      activeAdminTips: tips,
      volumeThisMonth: Math.round(thisTotal),
      volumeLastMonth: Math.round(lastTotal),
      volumeChange,
      txnCountThisMonth: quickThisMonth.length + secureThisMonth.length,
      topCategories,
    });
  } catch (err) {
    console.error('Admin insights platform error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/insights/health-scores?page=1&limit=20
exports.getHealthScores = async (req, res) => {
  try {
    const page  = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, parseInt(req.query.limit, 10) || 20);

    const now   = new Date();
    const year  = now.getFullYear();
    const month = now.getMonth() + 1;
    const monthStart = new Date(year, month - 1, 1);

    const [users, budgets, quickTxns, secureTxns] = await Promise.all([
      User.find({ role: { $ne: 'admin' } }).select('_id name email').lean(),
      Budget.find({ year, month }).lean(),
      QuickTransaction.find({ date: { $gte: monthStart } }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart } }).lean(),
    ]);

    const budgetMap = {};
    for (const b of budgets) budgetMap[b.user?.toString()] = b;

    const spendMap = {};
    for (const t of [...quickTxns, ...secureTxns]) {
      const uid = (t.user || t.userId)?.toString();
      if (uid) spendMap[uid] = (spendMap[uid] || 0) + (t.amount || 0);
    }

    const scored = users.map(u => {
      const uid    = u._id.toString();
      const budget = budgetMap[uid];
      const spent  = spendMap[uid] || 0;
      const total  = budget ? Object.values(budget.limits || {}).reduce((s, v) => s + v, 0) : 0;

      let score = 50;
      if (total > 0) {
        const ratio = spent / total;
        if (ratio <= 0.7) score = 90;
        else if (ratio <= 0.9) score = 75;
        else if (ratio <= 1.0) score = 60;
        else score = 30;
      }

      return {
        userId:   uid,
        name:     u.name,
        email:    u.email,
        score,
        spent:    Math.round(spent),
        budget:   Math.round(total),
        hasBudget: !!budget,
      };
    }).sort((a, b) => a.score - b.score);

    const total = scored.length;
    const page_data = scored.slice((page - 1) * limit, page * limit);

    res.json({ users: page_data, total, page, pages: Math.ceil(total / limit) });
  } catch (err) {
    console.error('Admin health scores error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/insights/anomalies
exports.getAnomalies = async (req, res) => {
  try {
    const now        = new Date();
    const year       = now.getFullYear();
    const month      = now.getMonth() + 1;
    const monthStart = new Date(year, month - 1, 1);
    const lastStart  = new Date(year, month - 2, 1);
    const lastEnd    = new Date(year, month - 1, 0, 23, 59, 59, 999);

    const [budgets, quickThis, secureThis, quickLast, secureLast] = await Promise.all([
      Budget.find({ year, month }).lean(),
      QuickTransaction.find({ date: { $gte: monthStart } }).lean(),
      Transaction.find({ createdAt: { $gte: monthStart } }).lean(),
      QuickTransaction.find({ date: { $gte: lastStart, $lte: lastEnd } }).lean(),
      Transaction.find({ createdAt: { $gte: lastStart, $lte: lastEnd } }).lean(),
    ]);

    const buildSpend = (txns) => {
      const m = {};
      for (const t of txns) {
        const uid = (t.user || t.userId)?.toString();
        if (uid) m[uid] = (m[uid] || 0) + (t.amount || 0);
      }
      return m;
    };

    const thisSpend = buildSpend([...quickThis, ...secureThis]);
    const lastSpend = buildSpend([...quickLast, ...secureLast]);

    const userIds = Array.from(new Set([
      ...Object.keys(thisSpend), ...Object.keys(lastSpend),
    ]));

    const users = await User.find({ _id: { $in: userIds } }).select('name email').lean();
    const userMap = {};
    for (const u of users) userMap[u._id.toString()] = u;

    const budgetMap = {};
    for (const b of budgets) budgetMap[b.user?.toString()] = b;

    const anomalies = [];
    for (const uid of userIds) {
      const spent     = thisSpend[uid] || 0;
      const lastSpent = lastSpend[uid] || 0;
      const budget    = budgetMap[uid];
      const limit     = budget ? Object.values(budget.limits || {}).reduce((s, v) => s + v, 0) : 0;

      const overBudgetPct = limit > 0 ? Math.round(((spent - limit) / limit) * 100) : 0;
      const momIncrease   = lastSpent > 0 ? Math.round(((spent - lastSpent) / lastSpent) * 100) : null;

      const isAnomaly = (limit > 0 && spent > limit * 1.5) ||
                        (momIncrease !== null && momIncrease > 100);
      if (!isAnomaly) continue;

      const u = userMap[uid];
      anomalies.push({
        userId: uid,
        name:   u?.name  || 'Unknown',
        email:  u?.email || '',
        spent:  Math.round(spent),
        lastMonthSpent: Math.round(lastSpent),
        budgetLimit:    Math.round(limit),
        overBudgetPct:  limit > 0 ? overBudgetPct : null,
        momChange:      momIncrease,
        type: limit > 0 && spent > limit * 1.5 ? 'over_budget' : 'spike',
      });
    }

    anomalies.sort((a, b) => (b.overBudgetPct || b.momChange || 0) - (a.overBudgetPct || a.momChange || 0));
    res.json({ anomalies });
  } catch (err) {
    console.error('Admin anomalies error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /admin/insights/tips
exports.getTips = async (req, res) => {
  try {
    const tips = await AdminTip.find()
      .populate('sentBy', 'name email')
      .populate('targetUser', 'name email')
      .sort({ createdAt: -1 }).lean();
    res.json({ tips });
  } catch (err) {
    console.error('Admin get tips error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// POST /admin/insights/tips
exports.createTip = async (req, res) => {
  try {
    const { title, body, category, impact, potentialSaving, targetType, targetUser } = req.body;

    if (!title?.trim() || !body?.trim()) {
      return res.status(400).json({ message: 'title and body are required' });
    }

    if (targetType === 'specific' && !targetUser) {
      return res.status(400).json({ message: 'targetUser required for specific targeting' });
    }

    const tip = await AdminTip.create({
      sentBy:  req.admin._id,
      title:   title.trim(),
      body:    body.trim(),
      category: category || 'general',
      impact:  impact || 'medium',
      potentialSaving: potentialSaving ?? null,
      targetType: targetType || 'all',
      targetUser: targetType === 'specific' ? targetUser : null,
    });

    res.status(201).json({ tip });
  } catch (err) {
    console.error('Admin create tip error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// PATCH /admin/insights/tips/:id/toggle
exports.toggleTip = async (req, res) => {
  try {
    const tip = await AdminTip.findById(req.params.id);
    if (!tip) return res.status(404).json({ message: 'Tip not found' });

    tip.isActive = !tip.isActive;
    await tip.save();
    res.json({ tip, isActive: tip.isActive });
  } catch (err) {
    console.error('Admin toggle tip error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// DELETE /admin/insights/tips/:id
exports.deleteTip = async (req, res) => {
  try {
    const tip = await AdminTip.findByIdAndDelete(req.params.id);
    if (!tip) return res.status(404).json({ message: 'Tip not found' });
    res.json({ message: 'Tip deleted' });
  } catch (err) {
    console.error('Admin delete tip error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};
