const User = require('../models/user');
const Transaction = require('../models/transaction');

function currentMonthRange() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59, 999);
  return { start, end };
}

async function getMonthLentTotal(email) {
  const { start, end } = currentMonthRange();
  const result = await Transaction.aggregate([
    { $match: { userEmail: email, role: 'lender', date: { $gte: start, $lte: end } } },
    { $group: { _id: null, total: { $sum: '$amount' } } },
  ]);
  return result[0]?.total || 0;
}

exports.getLendingBudget = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('email lendingBudget');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const monthlyLimit = user.lendingBudget?.monthlyLimit ?? null;
    const alertThresholdPercent = user.lendingBudget?.alertThresholdPercent ?? 80;
    const currentMonthLent = await getMonthLentTotal(user.email);
    const remaining = monthlyLimit != null ? Math.max(0, monthlyLimit - currentMonthLent) : null;
    const percentUsed = monthlyLimit != null && monthlyLimit > 0
      ? Math.min(100, Math.round((currentMonthLent / monthlyLimit) * 100))
      : null;

    res.json({
      monthlyLimit,
      alertThresholdPercent,
      currentMonthLent,
      remaining,
      percentUsed,
      isOverLimit: monthlyLimit != null && currentMonthLent > monthlyLimit,
      isNearLimit: percentUsed != null && percentUsed >= alertThresholdPercent,
    });
  } catch (err) {
    console.error('Error fetching lending budget:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateLendingBudget = async (req, res) => {
  try {
    const { monthlyLimit, alertThresholdPercent } = req.body;
    if (monthlyLimit !== null && monthlyLimit !== undefined) {
      if (typeof monthlyLimit !== 'number' || monthlyLimit < 0) {
        return res.status(400).json({ error: 'monthlyLimit must be a non-negative number or null.' });
      }
    }
    if (alertThresholdPercent !== undefined) {
      if (typeof alertThresholdPercent !== 'number' || alertThresholdPercent < 1 || alertThresholdPercent > 100) {
        return res.status(400).json({ error: 'alertThresholdPercent must be between 1 and 100.' });
      }
    }

    const update = {};
    if (monthlyLimit !== undefined) update['lendingBudget.monthlyLimit'] = monthlyLimit;
    if (alertThresholdPercent !== undefined) update['lendingBudget.alertThresholdPercent'] = alertThresholdPercent;

    const user = await User.findByIdAndUpdate(req.user._id, { $set: update }, { new: true })
      .select('email lendingBudget');
    if (!user) return res.status(404).json({ error: 'User not found' });

    res.json({ message: 'Lending budget updated.', lendingBudget: user.lendingBudget });
  } catch (err) {
    console.error('Error updating lending budget:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
