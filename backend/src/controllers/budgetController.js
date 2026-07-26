const Budget = require('../models/budget');
const BudgetRecurring = require('../models/budgetRecurring');
const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');
const { upsertLimitMessages } = require('./budgetMessageController');

const CATEGORY_KEYS = ['food', 'shopping', 'entertainment', 'fuel', 'travel', 'medical', 'education', 'other'];

const getUserEmail = async (userId) => {
  const u = await User.findById(userId).select('email').lean();
  return u?.email;
};

// Lazily apply last month's surplus as rollover if not yet applied for this month.
// Called at the start of getBudgetStatus so the user never needs to click "Apply Rollover" manually.
const lazyApplyRollover = async (userId, email, year, month) => {
  try {
    const existing = await Budget.findOne({ user: userId, year, month }).lean();
    if (existing?.rolloverApplied) return; // already done

    const lastYear  = month === 1 ? year - 1 : year;
    const lastMonth = month === 1 ? 12 : month - 1;
    const prevBudget = await Budget.findOne({ user: userId, year: lastYear, month: lastMonth }).lean();
    if (!prevBudget?.limits?.overall) return;

    const startDate = new Date(lastYear, lastMonth - 1, 1);
    const endDate   = new Date(lastYear, lastMonth, 0, 23, 59, 59);
    const [quick, secure] = await Promise.all([
      QuickTransaction.aggregate([{ $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
      Transaction.aggregate([{ $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
    ]);
    const prevSpent = (quick[0]?.total ?? 0) + (secure[0]?.total ?? 0);
    const surplus   = Math.max(0, prevBudget.limits.overall - prevSpent);
    if (surplus === 0) return;

    await Budget.findOneAndUpdate(
      { user: userId, year, month },
      { $inc: { 'limits.overall': surplus }, $set: { rolloverApplied: Math.round(surplus) } },
      { upsert: true },
    );
  } catch {} // best-effort; never block the main status response
};

exports.getBudget = async (req, res) => {
  try {
    const userId = req.user._id;
    const year = parseInt(req.params.year, 10);
    const month = parseInt(req.params.month, 10);
    if (!year || !month || month < 1 || month > 12) {
      return res.status(400).json({ message: 'Invalid year or month' });
    }
    const budget = await Budget.findOne({ user: userId, year, month }).lean();
    res.json(budget ?? {
      year, month,
      limits: { quick: null, secure: null, group: null, overall: null },
      categoryLimits: {},
      alertThresholds: [75, 90, 100],
    });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.setBudget = async (req, res) => {
  try {
    const userId = req.user._id;
    const { year, month, limits } = req.body;
    if (!year || !month || month < 1 || month > 12) {
      return res.status(400).json({ message: 'Invalid year or month' });
    }
    const clean = {
      quick:   limits?.quick   != null ? parseFloat(limits.quick)   : null,
      secure:  limits?.secure  != null ? parseFloat(limits.secure)  : null,
      group:   limits?.group   != null ? parseFloat(limits.group)   : null,
      overall: limits?.overall != null ? parseFloat(limits.overall) : null,
    };

    // Server-side guard: overall cap must be >= sum of set sub-limits
    if (clean.overall != null) {
      const sumParts = (clean.quick ?? 0) + (clean.secure ?? 0) + (clean.group ?? 0);
      if (sumParts > clean.overall) {
        return res.status(400).json({
          message: `Overall cap (₹${clean.overall}) cannot be less than the sum of Quick + Secure + Group limits (₹${sumParts}). Increase the cap or reduce individual limits first.`,
        });
      }
    }

    const budget = await Budget.findOneAndUpdate(
      { user: userId, year, month },
      { $set: { limits: clean } },
      { upsert: true, new: true }
    );
    res.json(budget);
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.setCategoryBudget = async (req, res) => {
  try {
    const userId = req.user._id;
    const now = new Date();
    const year = req.body.year || now.getFullYear();
    const month = req.body.month || now.getMonth() + 1;
    const { categoryLimits } = req.body;

    const clean = {};
    for (const key of CATEGORY_KEYS) {
      const val = categoryLimits?.[key];
      clean[`categoryLimits.${key}`] = val != null && val !== '' ? parseFloat(val) : null;
    }
    const budget = await Budget.findOneAndUpdate(
      { user: userId, year, month },
      { $set: clean },
      { upsert: true, new: true }
    );
    res.json(budget);
  } catch (err) {
    res.status(500).json({ message: 'Server error', detail: err.message });
  }
};

exports.setAlertThresholds = async (req, res) => {
  try {
    const userId = req.user._id;
    const now = new Date();
    const year = req.body.year || now.getFullYear();
    const month = req.body.month || now.getMonth() + 1;
    const { alertThresholds } = req.body;
    const thresholds = Array.isArray(alertThresholds)
      ? alertThresholds.map(Number).filter(n => n > 0 && n <= 100)
      : [75, 90, 100];

    const budget = await Budget.findOneAndUpdate(
      { user: userId, year, month },
      { $set: { alertThresholds: thresholds } },
      { upsert: true, new: true }
    );
    res.json(budget);
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getBudgetStatus = async (req, res) => {
  try {
    const userId = req.user._id;
    const email = await getUserEmail(userId);
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth() + 1;
    const startDate = new Date(year, month - 1, 1);

    // Auto-apply last month's surplus (fire-and-forget; re-fetched below)
    await lazyApplyRollover(userId, email, year, month);

    const [budget, quickTxns, secureTxns, groupsRaw, recurringItems] = await Promise.all([
      Budget.findOne({ user: userId, year, month }).lean(),
      QuickTransaction.find({ creatorEmail: email, date: { $gte: startDate } }).lean(),
      Transaction.find({ userEmail: email, createdAt: { $gte: startDate } }).lean(),
      GroupTransaction.find({ 'members.user': userId }, 'title color members expenses').lean(),
      BudgetRecurring.find({ user: userId, isActive: true }).sort({ createdAt: -1 }).lean(),
    ]);

    const groupLimitsMap = budget?.groupLimits instanceof Map
      ? Object.fromEntries(budget.groupLimits)
      : (budget?.groupLimits ?? {});
    const groupSpending = groupsRaw.map(g => {
      let spent = 0, count = 0;
      for (const exp of (g.expenses || [])) {
        if (new Date(exp.date) >= startDate) {
          for (const split of (exp.split || [])) {
            if (String(split.user) === String(userId)) { spent += split.amount || 0; count++; }
          }
        }
      }
      const gId = g._id.toString();
      return {
        id: gId,
        name: g.title,
        color: g.color || '#2196F3',
        memberCount: (g.members || []).filter(m => !m.leftAt).length,
        spent: Math.round(spent),
        budget: groupLimitsMap[gId] ?? null,
        expenseCount: count,
      };
    });

    const limits = budget?.limits ?? {};
    const catLimits = budget?.categoryLimits ?? {};
    const alertThresholds = budget?.alertThresholds ?? [75, 90, 100];

    const spentQuick = quickTxns.reduce((s, t) => s + (t.amount || 0), 0);
    const spentSecure = secureTxns.reduce((s, t) => s + (t.amount || 0), 0);
    const spentGroup = groupSpending.reduce((s, g) => s + g.spent, 0);
    const totalGroupCount = groupSpending.reduce((s, g) => s + g.expenseCount, 0);
    const spentOverall = spentQuick + spentSecure + spentGroup;

    // Category spending from quick + secure combined
    const catSpent = {};
    for (const key of CATEGORY_KEYS) catSpent[key] = 0;
    for (const t of [...quickTxns, ...secureTxns]) {
      const cat = (t.category || 'other').toLowerCase();
      const key = CATEGORY_KEYS.includes(cat) ? cat : 'other';
      catSpent[key] = (catSpent[key] || 0) + (t.amount || 0);
    }

    // Detect overspending
    const overspent = [];
    if (limits.quick && spentQuick > limits.quick) overspent.push({ type: 'quick', limit: limits.quick, spent: spentQuick });
    if (limits.secure && spentSecure > limits.secure) overspent.push({ type: 'secure', limit: limits.secure, spent: spentSecure });
    if (limits.group && spentGroup > limits.group) overspent.push({ type: 'group', limit: limits.group, spent: spentGroup });
    if (limits.overall && spentOverall > limits.overall) overspent.push({ type: 'overall', limit: limits.overall, spent: spentOverall });
    for (const key of CATEGORY_KEYS) {
      if (catLimits[key] && catSpent[key] > catLimits[key]) {
        overspent.push({ type: `cat_${key}`, limit: catLimits[key], spent: catSpent[key] });
      }
    }

    // Alert levels triggered
    const alerts = [];
    const checkAlert = (label, spent, limit) => {
      if (!limit || limit <= 0) return;
      const pct = Math.round((spent / limit) * 100);
      for (const threshold of alertThresholds.sort((a, b) => b - a)) {
        if (pct >= threshold) {
          alerts.push({ label, pct, threshold, spent, limit });
          break;
        }
      }
    };
    checkAlert('Quick', spentQuick, limits.quick);
    checkAlert('Secure', spentSecure, limits.secure);
    checkAlert('Group', spentGroup, limits.group);
    checkAlert('Overall', spentOverall, limits.overall);
    for (const key of CATEGORY_KEYS) {
      if (catLimits[key]) checkAlert(key.charAt(0).toUpperCase() + key.slice(1), catSpent[key], catLimits[key]);
    }

    // Fire-and-forget: auto-create budget messages for crossed limits
    upsertLimitMessages(userId, year, month, overspent, groupSpending);

    res.json({
      year, month,
      limits: {
        quick: limits.quick ?? null,
        secure: limits.secure ?? null,
        group: limits.group ?? null,
        overall: limits.overall ?? null,
      },
      categoryLimits: catLimits,
      alertThresholds,
      spent: { quick: spentQuick, secure: spentSecure, group: spentGroup, overall: spentOverall },
      counts: {
        quick: quickTxns.length,
        secure: secureTxns.length,
        group: totalGroupCount,
      },
      groupSpending,
      categorySpent: catSpent,
      overspent,
      alerts,
      recurring: recurringItems.map(r => ({
        _id: r._id,
        name: r.name,
        amount: r.amount,
        category: r.category,
        dueDay: r.dueDay,
      })),
    });
  } catch (err) {
    console.error('Budget status error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getBudgetHistory = async (req, res) => {
  try {
    const userId = req.user._id;
    const email  = await getUserEmail(userId);
    const budgets = await Budget.find({ user: userId })
      .sort({ year: -1, month: -1 })
      .limit(12)
      .lean();

    const history = await Promise.all(budgets.map(async (b) => {
      const startDate = new Date(b.year, b.month - 1, 1);
      const endDate   = new Date(b.year, b.month, 0, 23, 59, 59);
      const [quick, secure] = await Promise.all([
        QuickTransaction.aggregate([{ $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
        Transaction.aggregate([{ $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
      ]);
      const spent  = Math.round((quick[0]?.total ?? 0) + (secure[0]?.total ?? 0));
      const budget = b.limits?.overall ?? null;
      const adherence = budget > 0
        ? Math.max(0, Math.min(100, Math.round(100 - Math.max(0, ((spent - budget) / budget) * 100))))
        : 0;
      return {
        month: `${b.year}-${String(b.month).padStart(2, '0')}`,
        budget,
        spent,
        adherence,
      };
    }));

    res.json(history);
  } catch (err) {
    console.error('Budget history error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getBudgetRecommendations = async (req, res) => {
  try {
    const userId = req.user._id;
    const email = await getUserEmail(userId);
    const now = new Date();

    // Fetch last 3 months' spending
    const months = Array.from({ length: 3 }, (_, i) => {
      const d = new Date(now.getFullYear(), now.getMonth() - 1 - i, 1);
      return { year: d.getFullYear(), month: d.getMonth() + 1, startDate: d };
    });

    const groups = await GroupTransaction.find({ 'members.user': userId }, '_id expenses members').lean();

    const spending = await Promise.all(months.map(async ({ year, month, startDate }) => {
      const endDate = new Date(year, month, 0, 23, 59, 59);
      const [quick, secure] = await Promise.all([
        QuickTransaction.aggregate([
          { $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]),
        Transaction.aggregate([
          { $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]),
      ]);
      let groupTotal = 0;
      for (const g of groups) {
        for (const exp of (g.expenses || [])) {
          const d = new Date(exp.date);
          if (d >= startDate && d <= endDate) {
            for (const split of (exp.split || [])) {
              if (String(split.user) === String(userId)) groupTotal += split.amount || 0;
            }
          }
        }
      }
      return {
        year, month,
        quick: quick[0]?.total ?? 0,
        secure: secure[0]?.total ?? 0,
        group: groupTotal,
      };
    }));

    // Recommend 10% buffer over 3-month average
    const avgQuick  = spending.reduce((s, m) => s + m.quick,  0) / 3;
    const avgSecure = spending.reduce((s, m) => s + m.secure, 0) / 3;
    const avgGroup  = spending.reduce((s, m) => s + m.group,  0) / 3;

    const prev = spending[0];

    res.json({
      prevMonth: { year: prev.year, month: prev.month, quick: prev.quick, secure: prev.secure, group: prev.group },
      recommended: {
        quick:   Math.ceil((avgQuick  * 1.1)  / 100) * 100 || null,
        secure:  Math.ceil((avgSecure * 1.1)  / 100) * 100 || null,
        group:   Math.ceil((avgGroup  * 1.1)  / 100) * 100 || null,
        overall: Math.ceil(((avgQuick + avgSecure + avgGroup) * 1.15) / 500) * 500 || null,
      },
      threeMonthAvg: { quick: Math.round(avgQuick), secure: Math.round(avgSecure), group: Math.round(avgGroup) },
    });
  } catch (err) {
    console.error('Budget recommendation error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getBudgetInsights = async (req, res) => {
  try {
    const userId = req.user._id;
    const email = await getUserEmail(userId);
    const budgets = await Budget.find({ user: userId }).sort({ year: -1, month: -1 }).limit(12).lean();
    if (budgets.length === 0) return res.json({ insights: [] });

    // For each month with a budget, fetch actual spend
    const monthData = await Promise.all(budgets.map(async (b) => {
      const startDate = new Date(b.year, b.month - 1, 1);
      const endDate = new Date(b.year, b.month, 0, 23, 59, 59);
      const [quick, secure] = await Promise.all([
        QuickTransaction.aggregate([
          { $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]),
        Transaction.aggregate([
          { $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]),
      ]);
      const spent = (quick[0]?.total ?? 0) + (secure[0]?.total ?? 0);
      const overall = b.limits?.overall;
      const saved = overall ? Math.max(0, overall - spent) : 0;
      const withinBudget = overall ? spent <= overall : null;
      return { year: b.year, month: b.month, budget: overall, spent, saved, withinBudget };
    }));

    const withBudget = monthData.filter(m => m.budget != null);
    const avgSavings = withBudget.length > 0 ? Math.round(withBudget.reduce((s, m) => s + m.saved, 0) / withBudget.length) : 0;
    const successCount = withBudget.filter(m => m.withinBudget).length;
    const successRate = withBudget.length > 0 ? Math.round((successCount / withBudget.length) * 100) : null;

    const sortedBySpent = [...monthData].sort((a, b) => a.spent - b.spent);
    const bestMonthObj  = sortedBySpent[0];
    const worstMonthObj = sortedBySpent[sortedBySpent.length - 1];

    const MN = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const fmtM = (m) => m ? `${MN[m.month - 1]} ${m.year}` : null;

    const adherences = withBudget.map(m =>
      Math.max(0, Math.min(100, Math.round(100 - Math.max(0, ((m.spent - m.budget) / m.budget) * 100))))
    );
    const avgAdherence = adherences.length > 0
      ? Math.round(adherences.reduce((s, v) => s + v, 0) / adherences.length) : 0;

    const trend = (() => {
      if (adherences.length < 4) return 'stable';
      const recent = adherences.slice(0, 3);
      const older  = adherences.slice(3, 6);
      if (!older.length) return 'stable';
      const avgR = recent.reduce((s, v) => s + v, 0) / recent.length;
      const avgO = older.reduce((s, v) => s + v, 0) / older.length;
      if (avgR > avgO + 5) return 'improving';
      if (avgR < avgO - 5) return 'worsening';
      return 'stable';
    })();

    res.json({
      monthData,
      avgSavings,
      successRate,
      avgAdherence,
      bestMonth: fmtM(bestMonthObj),
      worstMonth: fmtM(worstMonthObj),
      trend,
      totalMonthsTracked: monthData.length,
    });
  } catch (err) {
    console.error('Budget insights error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getRecurring = async (req, res) => {
  try {
    const items = await BudgetRecurring.find({ user: req.user._id, isActive: true })
      .sort({ createdAt: -1 }).lean();
    res.json({ recurring: items });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.addRecurring = async (req, res) => {
  try {
    const { name, amount, category, dueDay } = req.body;
    if (!name || !name.trim()) return res.status(400).json({ message: 'Name is required' });
    const amt = parseFloat(amount);
    if (!amt || amt <= 0) return res.status(400).json({ message: 'Amount must be positive' });
    const item = await BudgetRecurring.create({
      user: req.user._id,
      name: name.trim(),
      amount: amt,
      category: category || 'Other Fixed Cost',
      dueDay: dueDay || null,
    });
    res.status(201).json({ recurring: item });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.deleteRecurring = async (req, res) => {
  try {
    const deleted = await BudgetRecurring.findOneAndDelete({
      _id: req.params.id,
      user: req.user._id,
    });
    if (!deleted) return res.status(404).json({ message: 'Not found' });
    res.json({ success: true });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /budget/rollover-preview — how much can roll over from last month
exports.getRolloverPreview = async (req, res) => {
  try {
    const userId = req.user._id;
    const email = await getUserEmail(userId);
    const now = new Date();
    const lastYear  = now.getMonth() === 0 ? now.getFullYear() - 1 : now.getFullYear();
    const lastMonth = now.getMonth() === 0 ? 12 : now.getMonth();

    const prevBudget = await Budget.findOne({ user: userId, year: lastYear, month: lastMonth }).lean();
    if (!prevBudget || !prevBudget.limits?.overall) {
      return res.json({ canRollover: false, message: 'No budget set for last month' });
    }

    const startDate = new Date(lastYear, lastMonth - 1, 1);
    const endDate   = new Date(lastYear, lastMonth, 0, 23, 59, 59);
    const [quick, secure] = await Promise.all([
      QuickTransaction.aggregate([
        { $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } },
        { $group: { _id: null, total: { $sum: '$amount' } } },
      ]),
      Transaction.aggregate([
        { $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } },
        { $group: { _id: null, total: { $sum: '$amount' } } },
      ]),
    ]);
    const prevSpent   = (quick[0]?.total ?? 0) + (secure[0]?.total ?? 0);
    const prevOverall = prevBudget.limits.overall;
    const surplus     = Math.max(0, prevOverall - prevSpent);

    if (surplus === 0) {
      return res.json({ canRollover: false, prevSpent: Math.round(prevSpent), prevBudget: prevOverall, surplus: 0 });
    }

    const thisBudget = await Budget.findOne({ user: userId, year: now.getFullYear(), month: now.getMonth() + 1 }).lean();
    const currentOverall = thisBudget?.limits?.overall ?? 0;
    const alreadyApplied = !!(thisBudget?.rolloverApplied);

    res.json({
      canRollover: true,
      alreadyApplied,
      prevMonth: { year: lastYear, month: lastMonth },
      prevBudget: Math.round(prevOverall),
      prevSpent:  Math.round(prevSpent),
      surplus:    Math.round(surplus),
      currentOverall: Math.round(currentOverall),
      newOverall: Math.round(currentOverall + surplus),
    });
  } catch (err) {
    console.error('Rollover preview error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// POST /budget/rollover — apply the rollover surplus to this month's overall limit
exports.applyRollover = async (req, res) => {
  try {
    const userId = req.user._id;
    const now    = new Date();
    const year   = now.getFullYear();
    const month  = now.getMonth() + 1;

    // Re-compute surplus (same logic as preview, not trusting client value)
    const email   = await getUserEmail(userId);
    const lastYear  = month === 1 ? year - 1 : year;
    const lastMonth = month === 1 ? 12 : month - 1;
    const prevBudget = await Budget.findOne({ user: userId, year: lastYear, month: lastMonth }).lean();
    if (!prevBudget?.limits?.overall) return res.status(400).json({ message: 'No previous budget to roll over' });

    // Idempotency: refuse if already applied this month
    const existing = await Budget.findOne({ user: userId, year, month }).lean();
    if (existing?.rolloverApplied) {
      return res.status(409).json({ message: 'Rollover already applied for this month' });
    }

    const startDate = new Date(lastYear, lastMonth - 1, 1);
    const endDate   = new Date(lastYear, lastMonth, 0, 23, 59, 59);
    const [quick, secure] = await Promise.all([
      QuickTransaction.aggregate([{ $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
      Transaction.aggregate([{ $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
    ]);
    const prevSpent = (quick[0]?.total ?? 0) + (secure[0]?.total ?? 0);
    const surplus   = Math.max(0, prevBudget.limits.overall - prevSpent);
    if (surplus === 0) return res.status(400).json({ message: 'No surplus to roll over' });

    const budget = await Budget.findOneAndUpdate(
      { user: userId, year, month },
      { $inc: { 'limits.overall': surplus }, $set: { rolloverApplied: Math.round(surplus) } },
      { upsert: true, new: true },
    );

    res.json({ message: 'Rollover applied', surplus: Math.round(surplus), newOverall: budget.limits?.overall });
  } catch (err) {
    console.error('Rollover apply error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /budget/streak — consecutive months within overall budget
exports.getBudgetStreak = async (req, res) => {
  try {
    const userId = req.user._id;
    const email  = await getUserEmail(userId);
    const budgets = await Budget.find({ user: userId, 'limits.overall': { $gt: 0 } })
      .sort({ year: -1, month: -1 }).limit(24).lean();

    if (budgets.length === 0) return res.json({ streak: 0, longestStreak: 0, history: [] });

    const monthData = await Promise.all(budgets.map(async (b) => {
      const startDate = new Date(b.year, b.month - 1, 1);
      const endDate   = new Date(b.year, b.month, 0, 23, 59, 59);
      const [quick, secure] = await Promise.all([
        QuickTransaction.aggregate([{ $match: { creatorEmail: email, date: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
        Transaction.aggregate([{ $match: { userEmail: email, createdAt: { $gte: startDate, $lte: endDate } } }, { $group: { _id: null, total: { $sum: '$amount' } } }]),
      ]);
      const spent = (quick[0]?.total ?? 0) + (secure[0]?.total ?? 0);
      const withinBudget = spent <= b.limits.overall;
      return { year: b.year, month: b.month, budget: b.limits.overall, spent: Math.round(spent), withinBudget };
    }));

    // Current streak (from most recent month back)
    let streak = 0;
    for (const m of monthData) {
      if (m.withinBudget) streak++;
      else break;
    }

    // Longest streak
    let longestStreak = 0, cur = 0;
    for (const m of [...monthData].reverse()) {
      if (m.withinBudget) { cur++; if (cur > longestStreak) longestStreak = cur; }
      else cur = 0;
    }

    res.json({ streak, longestStreak, totalMonths: monthData.length, history: monthData });
  } catch (err) {
    console.error('Budget streak error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};

exports.setGroupLimit = async (req, res) => {
  try {
    const userId = req.user._id;
    const { year, month, groupId, limit } = req.body;
    if (!year || !month || !groupId) {
      return res.status(400).json({ message: 'year, month, and groupId are required' });
    }
    const parsedLimit = limit != null ? parseFloat(limit) : null;
    if (parsedLimit !== null && (isNaN(parsedLimit) || parsedLimit < 0)) {
      return res.status(400).json({ message: 'limit must be a non-negative number' });
    }

    // Validate: sum of all group limits must not exceed the overall group limit
    const existing = await Budget.findOne({ user: userId, year, month }).lean();
    const overallGroupLimit = existing?.limits?.group ?? null;

    if (parsedLimit !== null && overallGroupLimit !== null) {
      const currentMap = existing?.groupLimits instanceof Map
        ? Object.fromEntries(existing.groupLimits)
        : (existing?.groupLimits ?? {});
      const otherLimitsSum = Object.entries(currentMap)
        .filter(([id]) => id !== groupId)
        .reduce((sum, [, v]) => sum + (v ?? 0), 0);
      if (otherLimitsSum + parsedLimit > overallGroupLimit) {
        return res.status(400).json({
          message: `Total group limits would exceed overall group limit of ₹${overallGroupLimit}. Remaining available: ₹${Math.max(0, overallGroupLimit - otherLimitsSum)}`,
        });
      }
    }

    const updateOp = parsedLimit !== null
      ? { $set: { [`groupLimits.${groupId}`]: parsedLimit } }
      : { $unset: { [`groupLimits.${groupId}`]: '' } };

    await Budget.findOneAndUpdate(
      { user: userId, year, month },
      updateOp,
      { upsert: true, new: true },
    );

    res.json({ message: 'Group limit updated' });
  } catch (err) {
    console.error('Set group limit error:', err);
    res.status(500).json({ message: 'Server error' });
  }
};
