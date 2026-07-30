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
    const quickLendLimit = budget?.limits?.quickLend;
    const quickBorrowLimit = budget?.limits?.quickBorrow;
    const secureLendLimit = budget?.limits?.secureLend;

    const hasAnyLimit = typeLimit || overallLimit || quickLendLimit || quickBorrowLimit || secureLendLimit;
    if (!hasAnyLimit) return next();

    const startDate = new Date(year, month - 1, 1);
    let spent = 0;
    let u;

    if (type === 'quick') {
      u = await User.findById(userId).select('email').lean();
      const [r] = await QuickTransaction.aggregate([
        { $match: { creatorEmail: u.email, date: { $gte: startDate } } },
        { $group: { _id: null, total: { $sum: '$amount' } } },
      ]);
      spent = r?.total ?? 0;
    } else if (type === 'secure') {
      u = await User.findById(userId).select('email').lean();
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

    // Role-specific limit checks for quick transactions
    if (type === 'quick' && u) {
      const role = req.body.role; // 'lender' | 'borrower'
      if (role === 'lender' && quickLendLimit) {
        const [r2] = await QuickTransaction.aggregate([
          { $match: { creatorEmail: u.email, role: 'lender', date: { $gte: startDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]);
        const lentSpent = r2?.total ?? 0;
        if (lentSpent + amount > quickLendLimit) {
          return res.status(400).json({
            message: `Monthly quick lending cap exceeded. Cap: ₹${quickLendLimit.toLocaleString('en-IN')}, Lent: ₹${Math.round(lentSpent).toLocaleString('en-IN')}.`,
            budgetExceeded: true,
            type: 'quick_lend',
            limit: quickLendLimit,
            spent: Math.round(lentSpent),
          });
        }
      }
      if (role === 'borrower' && quickBorrowLimit) {
        const [r2] = await QuickTransaction.aggregate([
          { $match: { creatorEmail: u.email, role: 'borrower', date: { $gte: startDate } } },
          { $group: { _id: null, total: { $sum: '$amount' } } },
        ]);
        const borrowedSpent = r2?.total ?? 0;
        if (borrowedSpent + amount > quickBorrowLimit) {
          return res.status(400).json({
            message: `Monthly quick borrowing cap exceeded. Cap: ₹${quickBorrowLimit.toLocaleString('en-IN')}, Borrowed: ₹${Math.round(borrowedSpent).toLocaleString('en-IN')}.`,
            budgetExceeded: true,
            type: 'quick_borrow',
            limit: quickBorrowLimit,
            spent: Math.round(borrowedSpent),
          });
        }
      }
    }

    // Secure lending limit check (creator of a secure transaction is always the lender)
    if (type === 'secure' && u && secureLendLimit) {
      if (spent + amount > secureLendLimit) {
        return res.status(400).json({
          message: `Monthly secure lending cap exceeded. Cap: ₹${secureLendLimit.toLocaleString('en-IN')}, Lent: ₹${Math.round(spent).toLocaleString('en-IN')}.`,
          budgetExceeded: true,
          type: 'secure_lend',
          limit: secureLendLimit,
          spent: Math.round(spent),
        });
      }
    }

    next();
  } catch {
    next();
  }
};
