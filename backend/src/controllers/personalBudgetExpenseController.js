const PersonalBudget        = require('../models/personalBudget');
const PersonalBudgetExpense = require('../models/personalBudgetExpense');
const User                  = require('../models/user');
const Notification          = require('../models/notification');
const { sendToUser }        = require('../services/notificationService');

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
    console.error('[ExpenseNotif]', err.message);
  }
}

async function getBudgetForUser(budgetId, userId) {
  return PersonalBudget.findOne({ _id: budgetId, user: userId }).lean();
}

function isEditable(budget) {
  if (!budget) return false;
  if (budget.status !== 'active') return false;
  return new Date(budget.endDate) >= new Date();
}

// POST /personal-budget/:budgetId/expenses
exports.addExpense = async (req, res) => {
  try {
    const budget = await getBudgetForUser(req.params.budgetId, req.user._id);
    if (!budget) return res.status(404).json({ error: 'Budget not found.' });
    if (!isEditable(budget)) {
      return res.status(403).json({ error: 'Cannot add expenses after budget deadline or when budget is closed.' });
    }

    const { amount, category, description, date, allocationName, scheduledFor } = req.body;
    if (!amount || !category) return res.status(400).json({ error: 'amount and category are required.' });

    const prevTotal = await PersonalBudgetExpense.aggregate([
      { $match: { budget: budget._id, isDeleted: { $ne: true }, status: 'active' } },
      { $group: { _id: null, total: { $sum: '$amount' } } },
    ]).then(r => r[0]?.total ?? 0);

    const parsedScheduledFor = scheduledFor ? new Date(scheduledFor) : null;
    const isScheduled = parsedScheduledFor && parsedScheduledFor > new Date();

    const expense = await PersonalBudgetExpense.create({
      budget:         budget._id,
      user:           req.user._id,
      amount:         parseFloat(amount),
      category:       category.trim(),
      allocationName: allocationName?.trim() || null,
      description:    description?.trim() || '',
      date:           date ? new Date(date) : new Date(),
      scheduledFor:   parsedScheduledFor,
      status:         isScheduled ? 'scheduled' : 'active',
    });

    // Only active expenses count toward limit thresholds
    const activeAmount = isScheduled ? 0 : expense.amount;
    const newTotal = prevTotal + activeAmount;
    const prevPct  = budget.limit > 0 ? (prevTotal / budget.limit) * 100 : 0;
    const newPct   = budget.limit > 0 ? (newTotal  / budget.limit) * 100 : 0;

    if (newPct >= 100 && prevPct < 100) {
      await _notifyUser(req.user._id, '🚨 Budget Exceeded!',
        `You've exceeded your "${budget.name}" budget limit! (${newPct.toFixed(0)}% used)`,
        { type: 'budget_exceeded', budgetId: budget._id.toString() });
    } else if (newPct >= 80 && prevPct < 80) {
      await _notifyUser(req.user._id, '⚠️ Budget Alert – 80% Used',
        `You've used 80% of your "${budget.name}" budget. Spend carefully!`,
        { type: 'budget_80pct', budgetId: budget._id.toString() });
    }

    res.status(201).json(expense);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// GET /personal-budget/:budgetId/expenses
exports.getExpenses = async (req, res) => {
  try {
    const budget = await getBudgetForUser(req.params.budgetId, req.user._id);
    if (!budget) return res.status(404).json({ error: 'Budget not found.' });

    // Auto-transition scheduled expenses whose scheduledFor date has passed
    const now = new Date();
    await PersonalBudgetExpense.updateMany(
      { budget: budget._id, isDeleted: { $ne: true }, status: 'scheduled', scheduledFor: { $lte: now } },
      { $set: { status: 'active' } }
    );

    const expenses = await PersonalBudgetExpense.find({ budget: budget._id, isDeleted: { $ne: true } })
      .sort({ date: -1 }).lean();

    // Only active expenses count toward total spend
    const total = expenses.reduce((s, e) => s + (e.status === 'active' ? e.amount : 0), 0);

    // Category breakdown (active expenses only for amounts; all expenses for counts)
    const byCategory = {};
    for (const e of expenses) {
      if (!byCategory[e.category]) byCategory[e.category] = { amount: 0 };
      if (e.status === 'active') byCategory[e.category].amount += e.amount;
    }

    // Per-allocation spending (active only)
    const byAllocation = {};
    for (const e of expenses) {
      if (e.allocationName && e.status === 'active') {
        byAllocation[e.allocationName] = (byAllocation[e.allocationName] || 0) + e.amount;
      }
    }
    const allocations = (budget.allocations || []).map(a => ({
      name:  a.name,
      limit: a.limit,
      spent: byAllocation[a.name] || 0,
    }));

    res.json({
      expenses,
      total,
      byCategory: Object.entries(byCategory)
        .map(([cat, data]) => ({ category: cat, amount: data.amount }))
        .sort((a, b) => b.amount - a.amount),
      budget: {
        _id:        budget._id,
        name:       budget.name,
        limit:      budget.limit,
        currency:   budget.currency,
        status:     budget.status,
        endDate:    budget.endDate,
        allocations,
        isEditable: isEditable(budget),
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// PUT /personal-budget/:budgetId/expenses/:expenseId
exports.updateExpense = async (req, res) => {
  try {
    const budget = await getBudgetForUser(req.params.budgetId, req.user._id);
    if (!budget) return res.status(404).json({ error: 'Budget not found.' });
    if (!isEditable(budget)) {
      return res.status(403).json({ error: 'Cannot edit expenses after budget deadline or when budget is closed.' });
    }

    const expense = await PersonalBudgetExpense.findOne({
      _id: req.params.expenseId, budget: budget._id, user: req.user._id,
    });
    if (!expense) return res.status(404).json({ error: 'Expense not found.' });

    const { amount, category, description, date, allocationName } = req.body;

    // Snapshot current state before applying changes
    expense.editHistory = expense.editHistory || [];
    expense.editHistory.push({
      amount:      expense.amount,
      category:    expense.category,
      description: expense.description,
      date:        expense.date,
      editedAt:    new Date(),
    });

    if (amount          !== undefined) expense.amount         = parseFloat(amount);
    if (category        !== undefined) expense.category       = category.trim();
    if (allocationName  !== undefined) expense.allocationName = allocationName?.trim() || null;
    if (description     !== undefined) expense.description    = description.trim();
    if (date            !== undefined) expense.date           = new Date(date);

    await expense.save();
    res.json(expense);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// DELETE /personal-budget/:budgetId/expenses/:expenseId
exports.deleteExpense = async (req, res) => {
  try {
    const budget = await getBudgetForUser(req.params.budgetId, req.user._id);
    if (!budget) return res.status(404).json({ error: 'Budget not found.' });
    if (!isEditable(budget)) {
      return res.status(403).json({ error: 'Cannot delete expenses after budget deadline or when budget is closed.' });
    }

    const expense = await PersonalBudgetExpense.findOne({
      _id: req.params.expenseId, budget: budget._id, user: req.user._id,
    });
    if (!expense) return res.status(404).json({ error: 'Expense not found.' });
    expense.isDeleted = true;
    expense.deletedAt = new Date();
    await expense.save();
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};
