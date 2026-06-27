const Transaction = require('../models/transaction');
const RecurringQuickTransactionTemplate = require('../models/recurringQuickTransactionTemplate');

exports.getDueDates = async (req, res) => {
  try {
    const email = req.user.email;

    const transactions = await Transaction.find({
      $or: [{ userEmail: email }, { counterpartyEmail: email }],
      expectedReturnDate: { $ne: null },
    }).select('transactionId amount currency expectedReturnDate role userEmail counterpartyEmail userCleared counterpartyCleared');

    const dueItems = transactions.map((t) => {
      const isOwner = t.userEmail.toLowerCase() === email.toLowerCase();
      const cleared = isOwner ? t.userCleared : t.counterpartyCleared;
      return {
        type: 'secure_due',
        date: t.expectedReturnDate,
        transactionId: t._id,
        amount: t.amount,
        currency: t.currency,
        role: isOwner ? t.role : (t.role === 'lender' ? 'borrower' : 'lender'),
        counterpartyEmail: isOwner ? t.counterpartyEmail : t.userEmail,
        cleared: !!cleared,
      };
    });

    const templates = await RecurringQuickTransactionTemplate.find({
      creatorEmail: email,
      isActive: true,
    }).select('amount currency counterpartyEmail role frequency nextRunAt description');

    const templateItems = templates.map((t) => ({
      type: 'recurring_template',
      date: t.nextRunAt,
      templateId: t._id,
      amount: t.amount,
      currency: t.currency,
      role: t.role,
      counterpartyEmail: t.counterpartyEmail,
      frequency: t.frequency,
      description: t.description,
    }));

    res.json({ items: [...dueItems, ...templateItems] });
  } catch (err) {
    console.error('Error fetching calendar due dates:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
