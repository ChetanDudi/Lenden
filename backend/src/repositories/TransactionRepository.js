const BaseRepository = require('./BaseRepository');
const Transaction = require('../models/transaction');

class TransactionRepository extends BaseRepository {
  constructor() {
    super(Transaction);
  }

  findByUser(email, options = {}) {
    return this.find({ userEmail: email }, options);
  }

  findByCounterparty(email, options = {}) {
    return this.find({ counterpartyEmail: email }, options);
  }

  findVisibleToUser(email, filter = {}, options = {}) {
    return this.find(
      { $or: [{ userEmail: email }, { counterpartyEmail: email }], ...filter },
      options
    );
  }

  findByTransactionId(transactionId) {
    return this.findOne({ transactionId });
  }

  countByUser(email, extraFilter = {}) {
    return this.count({ userEmail: email, ...extraFilter });
  }
}

module.exports = new TransactionRepository();
