const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const { toCsv } = require('../utils/csvHelper');

const COLUMNS = [
  { key: 'date', label: 'Date' },
  { key: 'type', label: 'Type' },
  { key: 'counterparty', label: 'Counterparty/Group' },
  { key: 'role', label: 'Role' },
  { key: 'amount', label: 'Amount' },
  { key: 'currency', label: 'Currency' },
  { key: 'status', label: 'Status' },
  { key: 'description', label: 'Description' },
];

exports.exportStatement = async (req, res) => {
  try {
    const email = req.user.email;
    const { from, to, type } = req.query;
    const fromDate = from ? new Date(from) : new Date(0);
    const toDate = to ? new Date(to) : new Date();
    const wantAll = !type || type === 'all';
    const rows = [];

    if (wantAll || type === 'secure') {
      const txs = await Transaction.find({
        $or: [{ userEmail: email }, { counterpartyEmail: email }],
        date: { $gte: fromDate, $lte: toDate },
      }).sort({ date: 1 });

      for (const t of txs) {
        const isOwner = t.userEmail.toLowerCase() === email.toLowerCase();
        rows.push({
          type: 'Secure',
          date: t.date.toISOString().slice(0, 10),
          counterparty: isOwner ? t.counterpartyEmail : t.userEmail,
          role: isOwner ? t.role : (t.role === 'lender' ? 'borrower' : 'lender'),
          amount: t.amount,
          currency: t.currency,
          status: (isOwner ? t.userCleared : t.counterpartyCleared) ? 'Cleared' : 'Pending',
          description: t.description || '',
        });
      }
    }

    if (wantAll || type === 'quick') {
      const qtxs = await QuickTransaction.find({
        users: email,
        date: { $gte: fromDate, $lte: toDate },
      }).sort({ date: 1 });

      for (const t of qtxs) {
        const isCreator = t.creatorEmail.toLowerCase() === email.toLowerCase();
        const counterparty = (t.users || []).find((u) => u.toLowerCase() !== email.toLowerCase()) || '';
        rows.push({
          type: 'Quick',
          date: t.date.toISOString().slice(0, 10),
          counterparty,
          role: isCreator ? t.role : (t.role === 'lender' ? 'borrower' : 'lender'),
          amount: t.amount,
          currency: t.currency,
          status: t.cleared ? 'Cleared' : 'Pending',
          description: t.description || '',
        });
      }
    }

    if (wantAll || type === 'group') {
      const groups = await GroupTransaction.find({ 'members.user': req.user._id })
        .select('title expenses');

      for (const g of groups) {
        for (const e of (g.expenses || [])) {
          const expenseDate = new Date(e.date);
          if (expenseDate < fromDate || expenseDate > toDate) continue;
          const mySplit = (e.split || []).find((s) => s.user.toString() === req.user._id.toString());
          const isPayer = e.addedBy.toLowerCase() === email.toLowerCase();
          if (!mySplit && !isPayer) continue;

          rows.push({
            type: 'Group',
            date: expenseDate.toISOString().slice(0, 10),
            counterparty: g.title,
            role: isPayer ? 'paid' : 'share',
            amount: mySplit ? mySplit.amount : e.amount,
            currency: e.currency,
            status: mySplit ? (mySplit.settled ? 'Settled' : 'Pending') : 'Paid',
            description: e.description || '',
          });
        }
      }
    }

    rows.sort((a, b) => a.date.localeCompare(b.date));

    const csv = toCsv(COLUMNS, rows);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="lenden-statement-${Date.now()}.csv"`);
    res.status(200).send(csv);
  } catch (err) {
    console.error('Error exporting statement:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
