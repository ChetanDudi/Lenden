const Transaction = require('../models/transaction');

const ADMIN_TRANSACTION_SORT_FIELDS = new Set([
  'amount',
  'currency',
  'date',
  'time',
  'place',
  'interestType',
  'interestRate',
  'expectedReturnDate',
  'counterpartyEmail',
  'userEmail',
  'role',
  'userCleared',
  'counterpartyCleared',
  'remainingAmount',
  'totalAmountWithInterest',
  'isPartiallyPaid',
  'createdAt',
  'updatedAt',
]);

const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const parsePositiveInteger = (value) => {
  const parsed = parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed <= 0) return null;
  return parsed;
};

const buildAdminTransactionFilter = (query = {}) => {
  const {
    q,
    search,
    currency,
    role,
    interestType,
    userEmail,
    counterpartyEmail,
    isPartiallyPaid,
    clearanceFilter,
  } = query;

  const filter = {};

  if (currency && currency !== 'All') {
    filter.currency = currency;
  }

  if (role && role !== 'All') {
    filter.role = role;
  }

  if (interestType && interestType !== 'All') {
    filter.interestType = interestType;
  }

  if (typeof isPartiallyPaid === 'string' && isPartiallyPaid !== 'All') {
    filter.isPartiallyPaid = isPartiallyPaid === 'true';
  }

  if (userEmail) {
    filter.userEmail = { $regex: escapeRegex(userEmail), $options: 'i' };
  }

  if (counterpartyEmail) {
    filter.counterpartyEmail = {
      $regex: escapeRegex(counterpartyEmail),
      $options: 'i',
    };
  }

  // Clearance filter
  if (clearanceFilter && clearanceFilter !== 'all') {
    if (clearanceFilter === 'totally_cleared') {
      filter.userCleared = true;
      filter.counterpartyCleared = true;
    } else if (clearanceFilter === 'totally_uncleared') {
      filter.userCleared = { $ne: true };
      filter.counterpartyCleared = { $ne: true };
    }
  }

  // Support both q (existing) and search (new alias)
  const searchTerm = (q || search || '').trim();
  if (searchTerm) {
    const searchRegex = new RegExp(escapeRegex(searchTerm), 'i');
    filter.$or = [
      { transactionId: searchRegex },
      { place: searchRegex },
      { currency: searchRegex },
      { role: searchRegex },
      { description: searchRegex },
      { userEmail: searchRegex },
      { counterpartyEmail: searchRegex },
    ];
  }

  return filter;
};

const normalizeAdminTransactionUpdate = (payload = {}) => {
  const allowedPaths = new Set(
    Object.keys(Transaction.schema.paths).filter(
      (path) => !['_id', '__v', 'createdAt', 'updatedAt'].includes(path)
    )
  );

  const normalized = {};

  for (const [key, value] of Object.entries(payload)) {
    if (!allowedPaths.has(key)) continue;

    if (['date', 'expectedReturnDate'].includes(key)) {
      normalized[key] = value ? new Date(value) : null;
      continue;
    }

    normalized[key] = value;
  }

  if (
    Object.prototype.hasOwnProperty.call(normalized, 'amount') &&
    !Object.prototype.hasOwnProperty.call(normalized, 'remainingAmount') &&
    normalized.isPartiallyPaid !== true
  ) {
    normalized.remainingAmount = normalized.amount;
  }

  if (
    Object.prototype.hasOwnProperty.call(normalized, 'amount') &&
    !Object.prototype.hasOwnProperty.call(normalized, 'totalAmountWithInterest')
  ) {
    const nextInterestType = normalized.interestType;
    const nextInterestRate = normalized.interestRate;
    if (
      nextInterestType === 'none' ||
      nextInterestType == null ||
      nextInterestRate == null
    ) {
      normalized.totalAmountWithInterest = normalized.amount;
    }
  }

  return normalized;
};

const getAllTransactions = async (req, res) => {
  try {
    const { page, limit, sortBy = 'date', order = 'desc' } = req.query;
    const sortField = ADMIN_TRANSACTION_SORT_FIELDS.has(sortBy)
      ? sortBy
      : 'date';
    const sortOrder = order === 'asc' ? 1 : -1;
    const pageNumber = parsePositiveInteger(page) || 1;
    const limitNumber = parsePositiveInteger(limit);
    const filter = buildAdminTransactionFilter(req.query);

    let query = Transaction.find(filter).sort({ [sortField]: sortOrder, _id: -1 });

    if (limitNumber) {
      query = query.skip((pageNumber - 1) * limitNumber).limit(limitNumber);
    }

    const transactions = await query;
    const totalTransactions = await Transaction.countDocuments(filter);

    res.json({
      success: true,
      transactions,
      totalTransactions,
      totalPages: limitNumber ? Math.ceil(totalTransactions / limitNumber) : 1,
      currentPage: pageNumber,
    });
  } catch (error) {
    console.error('Error fetching transactions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch transactions',
    });
  }
};

const User = require('../models/user');
const { logTransactionActivity } = require('./activityController');

const updateTransaction = async (req, res) => {
  try {
    const { transactionId } = req.params;
    
    let body = { ...req.body };
    const isMultipart = req.is('multipart/form-data');

    if (isMultipart) {
      for (const key in body) {
        if (body[key] === 'true') {
          body[key] = true;
        } else if (body[key] === 'false') {
          body[key] = false;
        } else if (
          typeof body[key] === 'string' &&
          (body[key].startsWith('{') || body[key].startsWith('['))
        ) {
          try {
            body[key] = JSON.parse(body[key]);
          } catch (e) {
            // Not a valid JSON string, leave as is
          }
        }
      }
    }
    
    let existingPhotos = [];
    if (body.photos) {
      if (typeof body.photos === 'string') {
        try {
          existingPhotos = JSON.parse(body.photos);
        } catch (e) {
          existingPhotos = [body.photos];
        }
      } else if (Array.isArray(body.photos)) {
        existingPhotos = body.photos;
      }
    }

    const newPhotos = (req.files || []).map(file => file.buffer.toString('base64'));
    body.photos = [...existingPhotos, ...newPhotos];


    const updateData = normalizeAdminTransactionUpdate(body);
    const originalTransaction = await Transaction.findById(transactionId);

    if (!originalTransaction) {
      return res.status(404).json({
        success: false,
        message: 'Transaction not found',
      });
    }

    const originalPartialPaymentsJSON = JSON.stringify(originalTransaction.partialPayments);

    Object.assign(originalTransaction, updateData);
    const transaction = await originalTransaction.save();

    const newPartialPaymentsJSON = JSON.stringify(transaction.partialPayments);

    // Log activity if partial payment was made, edited or deleted
    if (originalPartialPaymentsJSON !== newPartialPaymentsJSON) {
      const user = await User.findOne({ email: transaction.userEmail });
      const counterparty = await User.findOne({ email: transaction.counterpartyEmail });
      
      if (user && counterparty) {
        await logTransactionActivity(user._id, 'transaction_updated_by_admin', transaction, {}, { creatorId: req.user._id, creatorEmail: req.user.email });
        await logTransactionActivity(counterparty._id, 'transaction_updated_by_admin', transaction, {}, { creatorId: req.user._id, creatorEmail: req.user.email });
      }
    }

    res.json({
      success: true,
      message: 'Transaction updated successfully',
      transaction,
    });
  } catch (error) {
    console.error('Error updating transaction:', error);
    res.status(error.name === 'ValidationError' ? 400 : 500).json({
      success: false,
      message:
        error.name === 'ValidationError'
          ? error.message
          : 'Failed to update transaction',
    });
  }
};

const deleteTransaction = async (req, res) => {
  try {
    const { transactionId } = req.params;
    const transaction = await Transaction.findByIdAndDelete(transactionId);

    if (!transaction) {
      return res.status(404).json({
        success: false,
        message: 'Transaction not found',
      });
    }

    res.json({
      success: true,
      message: 'Transaction deleted successfully',
    });
  } catch (error) {
    console.error('Error deleting transaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete transaction',
    });
  }
};

module.exports = {
  getAllTransactions,
  updateTransaction,
  deleteTransaction,
};
