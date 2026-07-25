const Budget = require('../models/budget');
const QuickTransaction = require('../models/quickTransaction');
const Transaction = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');

// Middleware factory: check monthly budget before creating a transaction.
// type = 'quick' | 'secure' | 'group'
module.exports = (type) => async (req, res, next) => {
  try {
    // User explicitly chose to proceed despite budget warning
    if (req.body.force === true || req.body.force === 'true') return next();

    const amount = parseFloat(req.body.amount);
    if (!amount || isNaN(amount) || amount <= 0) return next();

    const userId = req.user._id;
    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth() + 1;

    const budget = await Budget.findOne({ user: userId, year, month }).lean();
    const typeLimit = budget?.limits?.[type];
    const overallLimit = budget?.limits?.overall;

    if (!typeLimit && !overallLimit) return next();

    const startDate = new Date(year, month - 1, 1);
    let spent = 0;

    if (type === 'quick') {
      const u = await User.findById(userId).select('email').lean();
      const [r] = await QuickTransaction.aggregate([
        { $match: { creatorEmail: u.email, date: { $gte: startDate } } },
        { $group: { _id: null, total: { $sum: '$amount' } } },
      ]);
      spent = r?.total ?? 0;
    } else if (type === 'secure') {
      const u = await User.findById(userId).select('email').lean();
      const [r] = await Transaction.aggregate([
        { $match: { userEmail: u.email, createdAt: { $gte: startDate } } },
        { $group: { _id: null, total: { $sum: '$amount' } } },
      ]);
      spent = r?.total ?? 0;
    } else if (type === 'group') {
      const groupId = req.params.groupId;
      if (groupId) {
        const [r] = await GroupTransaction.aggregate([
          { $match: { _id: new (require('mongoose').Types.ObjectId)(groupId) } },
          { $unwind: '$expenses' },
          { $match: { 'expenses.date': { $gte: startDate } } },
          { $unwind: '$expenses.split' },
          { $match: { 'expenses.split.user': userId } },
          { $group: { _id: null, total: { $sum: '$expenses.split.amount' } } },
        ]);
        spent = r?.total ?? 0;
      }
    }

    if (typeLimit && spent + amount > typeLimit) {
      return res.status(400).json({
        message: `Monthly ${type} budget exceeded. Limit: ₹${typeLimit.toLocaleString('en-IN')}, Spent: ₹${Math.round(spent).toLocaleString('en-IN')}.`,
        budgetExceeded: true,
        type,
        limit: typeLimit,
        spent: Math.round(spent),
      });
    }

    if (overallLimit && spent + amount > overallLimit) {
      return res.status(400).json({
        message: `Overall monthly budget exceeded. Limit: ₹${overallLimit.toLocaleString('en-IN')}, Spent: ₹${Math.round(spent).toLocaleString('en-IN')}.`,
        budgetExceeded: true,
        type: 'overall',
        limit: overallLimit,
        spent: Math.round(spent),
      });
    }

    next();
  } catch {
    next();
  }
};
