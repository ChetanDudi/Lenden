const PersonalBudget        = require('../models/personalBudget');
const PersonalBudgetExpense = require('../models/personalBudgetExpense');
const User                  = require('../models/user');
const Notification          = require('../models/notification');
const { hasFeature, FEATURES } = require('../utils/subscriptionFeatures');
const { sendToUser }        = require('../services/notificationService');

const _CURRENCY_SYM = { INR: '₹', USD: '$', EUR: '€', GBP: '£', JPY: '¥', AED: 'AED', SGD: 'S$', CAD: 'C$', AUD: 'A$', SAR: 'SAR' };
function _sym(c) { return _CURRENCY_SYM[c] || c; }

async function _notifyUser(userId, title, message, data = {}) {
  try {
    await Notification.create({
      sender: userId, senderModel: 'User',
      recipientType: 'specific-users', recipients: [userId],
      recipientModel: 'User', title, message,
      category: 'system', deliveryStatus: 'sent', sentAt: new Date(),
      metadata: data,
    });
    await sendToUser(User, userId, { title, body: message, data });
  } catch (err) {
    console.error('[BudgetNotif]', err.message);
  }
}

const TRIAL_DAYS = 30;

async function getUserWithAccess(userId) {
  const user = await User.findById(userId).select('email createdAt').lean();
  if (!user) return null;
  const daysSinceReg = (Date.now() - new Date(user.createdAt)) / 86400000;
  const isTrial = daysSinceReg <= TRIAL_DAYS;
  const hasSubscription = await hasFeature(userId, FEATURES.PERSONAL_BUDGET);
  return { user, isTrial, hasSubscription, hasAccess: isTrial || hasSubscription };
}

async function computeSpent(budgetId) {
  const result = await PersonalBudgetExpense.aggregate([
    { $match: { budget: budgetId, isDeleted: { $ne: true } } },
    { $group: { _id: null, total: { $sum: '$amount' } } },
  ]);
  return result[0]?.total ?? 0;
}

function enrichBudget(b, spent, now) {
  const total   = b.endDate - b.startDate;
  const elapsed = Math.max(0, Math.min(now - b.startDate, total));
  const progress = total > 0 ? elapsed / total : 0;
  const projected = progress > 0.01 ? spent / progress : null;
  return {
    ...b,
    spentAmount:   spent,
    percentSpent:  b.limit > 0 ? (spent / b.limit) * 100 : 0,
    progress:      Math.round(progress * 100),
    projectedSpend: projected,
    onTrack:       projected !== null ? projected <= b.limit : null,
    daysLeft:      Math.max(0, Math.ceil((new Date(b.endDate) - now) / 86400000)),
  };
}

// ─── Access status ────────────────────────────────────────────────────────────
exports.getAccessStatus = async (req, res) => {
  try {
    const info = await getUserWithAccess(req.user._id);
    if (!info) return res.status(404).json({ error: 'User not found' });
    const { isTrial, hasSubscription, hasAccess, user } = info;
    const daysSinceReg = (Date.now() - new Date(user.createdAt)) / 86400000;
    res.json({
      hasAccess,
      isTrial,
      hasSubscription,
      trialDaysLeft: isTrial ? Math.ceil(TRIAL_DAYS - daysSinceReg) : 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Active budgets ───────────────────────────────────────────────────────────
exports.getActive = async (req, res) => {
  try {
    const userId = req.user._id;
    const info   = await getUserWithAccess(userId);
    if (!info?.hasAccess) return res.status(403).json({ error: 'Subscribe to use Personal Budget.' });

    const now = new Date();
    // Find budgets about to be expired (only ones not yet notified)
    const toExpire = await PersonalBudget.find({
      user: userId, status: 'active', endDate: { $lt: now }, notifiedExpiry: { $ne: true },
    }).lean();

    await PersonalBudget.updateMany(
      { user: userId, status: 'active', endDate: { $lt: now } },
      { $set: { status: 'expired' } },
    );

    // Notify each newly expired budget exactly once
    if (toExpire.length > 0) {
      await PersonalBudget.updateMany(
        { _id: { $in: toExpire.map(b => b._id) } },
        { $set: { notifiedExpiry: true } },
      );
      for (const b of toExpire) {
        await _notifyUser(userId, '⏰ Budget Expired',
          `Your "${b.name}" budget has expired.`,
          { type: 'budget_expired', budgetId: b._id.toString() });
      }
    }

    const budgets = await PersonalBudget.find({ user: userId, status: 'active' })
      .sort({ startDate: -1 }).lean();

    const enriched = await Promise.all(
      budgets.map(async (b) => {
        const spent = await computeSpent(b._id);
        return enrichBudget(b, spent, now);
      }),
    );

    res.json(enriched);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Create ───────────────────────────────────────────────────────────────────
exports.create = async (req, res) => {
  try {
    const userId = req.user._id;
    const info   = await getUserWithAccess(userId);
    if (!info?.hasAccess) return res.status(403).json({ error: 'Subscribe to use Personal Budget.' });

    const { name, period, startDate, endDate, limit, currency, notes } = req.body;
    if (!name || !period || !startDate || !endDate || !limit) {
      return res.status(400).json({ error: 'name, period, startDate, endDate, limit are required.' });
    }
    const start = new Date(startDate);
    const end   = new Date(endDate);
    if (end <= start) return res.status(400).json({ error: 'endDate must be after startDate.' });

    const budget = await PersonalBudget.create({
      user: userId, name, period, startDate: start, endDate: end,
      limit: parseFloat(limit), currency: currency || 'INR', notes: notes || '',
    });

    const fmtLimit = `${_sym(budget.currency)}${budget.limit.toLocaleString('en-IN')}`;
    await _notifyUser(userId, '💰 Budget Created',
      `Your budget "${budget.name}" has been set up with a ${fmtLimit} limit.`,
      { type: 'budget_created', budgetId: budget._id.toString() });

    res.status(201).json(budget);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Update ───────────────────────────────────────────────────────────────────
exports.update = async (req, res) => {
  try {
    const budget = await PersonalBudget.findOne({ _id: req.params.id, user: req.user._id });
    if (!budget) return res.status(404).json({ error: 'Budget not found.' });

    const { name, limit, notes, status } = req.body;
    if (name  !== undefined) budget.name  = name;
    if (limit !== undefined) budget.limit = parseFloat(limit);
    if (notes !== undefined) budget.notes = notes;
    if (status && ['active', 'completed'].includes(status)) {
      if (status === 'completed' || status === 'expired') {
        budget.spentAtClose = await computeSpent(budget._id);
      }
      budget.status = status;
    }
    await budget.save();

    if (status === 'completed') {
      const pct = budget.limit > 0 ? Math.round((budget.spentAtClose / budget.limit) * 100) : 0;
      await _notifyUser(req.user._id, '✅ Budget Completed',
        `"${budget.name}" marked complete. You spent ${pct}% of your budget.`,
        { type: 'budget_completed', budgetId: budget._id.toString() });
    }

    res.json(budget);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Delete (active budget) ───────────────────────────────────────────────────
exports.remove = async (req, res) => {
  try {
    const budget = await PersonalBudget.findOneAndDelete({ _id: req.params.id, user: req.user._id, status: 'active' });
    if (!budget) return res.status(404).json({ error: 'Active budget not found.' });
    await PersonalBudgetExpense.deleteMany({ budget: req.params.id });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Delete from history ──────────────────────────────────────────────────────
exports.removeHistory = async (req, res) => {
  try {
    const budget = await PersonalBudget.findOneAndDelete({
      _id: req.params.id, user: req.user._id,
      status: { $in: ['expired', 'completed'] },
    });
    if (!budget) return res.status(404).json({ error: 'History budget not found.' });
    await PersonalBudgetExpense.deleteMany({ budget: req.params.id });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── History (paginated + searchable) ────────────────────────────────────────
exports.getHistory = async (req, res) => {
  try {
    const userId = req.user._id;
    const info   = await getUserWithAccess(userId);
    if (!info?.hasAccess) return res.status(403).json({ error: 'Subscribe to use Personal Budget.' });

    const {
      limit    = 3,
      skip     = 0,
      name,
      period,
      status,
      startFrom,
      startTo,
      minLimit,
      maxLimit,
    } = req.query;

    const filter = { user: userId, status: { $in: ['expired', 'completed'] } };
    if (name)    filter.name    = { $regex: name, $options: 'i' };
    if (period)  filter.period  = period;
    if (status && ['expired', 'completed'].includes(status)) filter.status = status;
    if (startFrom || startTo) {
      filter.startDate = {};
      if (startFrom) filter.startDate.$gte = new Date(startFrom);
      if (startTo)   filter.startDate.$lte = new Date(startTo);
    }
    if (minLimit || maxLimit) {
      filter.limit = {};
      if (minLimit) filter.limit.$gte = parseFloat(minLimit);
      if (maxLimit) filter.limit.$lte = parseFloat(maxLimit);
    }

    const [total, budgets] = await Promise.all([
      PersonalBudget.countDocuments(filter),
      PersonalBudget.find(filter)
        .sort({ startDate: -1 })
        .skip(parseInt(skip, 10))
        .limit(parseInt(limit, 10))
        .lean(),
    ]);

    const enriched = await Promise.all(
      budgets.map(async (b) => {
        const spent = b.spentAtClose ?? await computeSpent(b._id);
        return {
          ...b,
          spentAmount:  spent,
          percentSpent: b.limit > 0 ? (spent / b.limit) * 100 : 0,
        };
      }),
    );

    res.json({ budgets: enriched, total, hasMore: parseInt(skip, 10) + parseInt(limit, 10) < total });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// ─── Predictions ──────────────────────────────────────────────────────────────
exports.getPredictions = async (req, res) => {
  try {
    const userId = req.user._id;
    const info   = await getUserWithAccess(userId);
    if (!info?.hasAccess) return res.status(403).json({ error: 'Subscribe to use Personal Budget.' });

    const now = new Date();

    const [history, active] = await Promise.all([
      PersonalBudget.find({ user: userId, status: { $in: ['expired', 'completed'] } })
        .sort({ startDate: -1 }).limit(30).lean(),
      PersonalBudget.find({ user: userId, status: 'active' }).lean(),
    ]);

    const predictions = await Promise.all(
      active.map(async (b) => {
        const spent = await computeSpent(b._id);
        const base  = enrichBudget(b, spent, now);

        const sameType  = history.filter(h => h.period === b.period);
        const avgRatio  = sameType.length > 0
          ? sameType.reduce((s, h) => s + (h.spentAtClose ?? 0) / h.limit, 0) / sameType.length
          : null;

        let recommendation = null;
        if (base.projectedSpend !== null && base.projectedSpend > b.limit) {
          recommendation = `At this pace you'll exceed the budget by ₹${Math.round(base.projectedSpend - b.limit).toLocaleString('en-IN')}.`;
        } else if (base.progress > 50 && base.onTrack) {
          recommendation = `On track! ${base.daysLeft} day${base.daysLeft === 1 ? '' : 's'} remaining.`;
        } else if (avgRatio !== null && avgRatio > 1) {
          recommendation = `Historically you overspend this ${b.period} budget by ${Math.round((avgRatio - 1) * 100)}%.`;
        }

        return {
          ...base,
          avgHistoricalRatio:    avgRatio ? Math.round(avgRatio * 100) / 100 : null,
          historicalDataPoints:  sameType.length,
          recommendation,
        };
      }),
    );

    res.json(predictions);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
