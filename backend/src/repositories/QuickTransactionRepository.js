const BaseRepository = require('./BaseRepository');
const QuickTransaction = require('../models/quickTransaction');

class QuickTransactionRepository extends BaseRepository {
  constructor() {
    super(QuickTransaction);
  }

  findByUser(email, options = {}) {
    return this.find({ users: email }, options);
  }

  findByUserPaginated(email, { page = 1, limit = 20, sort = { createdAt: -1 }, filter = {} } = {}) {
    const skip = (page - 1) * limit;
    return this.find({ users: email, ...filter }, { sort, skip, limit });
  }

  countByUser(email, extraFilter = {}) {
    return this.count({ users: email, ...extraFilter });
  }

  // Returns aggregated per-counterparty totals for analytics
  counterpartyBreakdown(userEmail) {
    return this.aggregate([
      { $match: { users: userEmail } },
      { $unwind: '$users' },
      { $match: { users: { $ne: userEmail } } },
      {
        $group: {
          _id: '$users',
          totalLent: {
            $sum: {
              $cond: [{ $eq: ['$role', 'lender'] }, '$amount', 0],
            },
          },
          totalBorrowed: {
            $sum: {
              $cond: [{ $eq: ['$role', 'borrower'] }, '$amount', 0],
            },
          },
          transactionCount: { $sum: 1 },
          cleared: {
            $sum: { $cond: [{ $eq: ['$cleared', true] }, 1, 0] },
          },
        },
      },
      { $sort: { transactionCount: -1 } },
    ]);
  }
}

module.exports = new QuickTransactionRepository();
