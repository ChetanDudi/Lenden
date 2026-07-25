const BudgetMessage = require('../models/budgetMessage');

// GET /api/budget/messages?type=quick&unreadOnly=true
exports.getBudgetMessages = async (req, res) => {
  try {
    const userId = req.user._id;
    const { type, unreadOnly } = req.query;
    const filter = { user: userId };
    if (type) filter.type = type;
    if (unreadOnly === 'true') filter.isRead = false;

    const messages = await BudgetMessage.find(filter)
      .sort({ isRead: 1, createdAt: -1 })
      .lean();

    res.json({ messages });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
};

// GET /api/budget/messages/unread-count
exports.getUnreadCount = async (req, res) => {
  try {
    const count = await BudgetMessage.countDocuments({ user: req.user._id, isRead: false });
    res.json({ count });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

// PUT /api/budget/messages/:id/read
exports.markRead = async (req, res) => {
  try {
    await BudgetMessage.findOneAndUpdate(
      { _id: req.params.id, user: req.user._id },
      { $set: { isRead: true } },
    );
    res.json({ success: true });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

// PUT /api/budget/messages/read-all
exports.markAllRead = async (req, res) => {
  try {
    await BudgetMessage.updateMany({ user: req.user._id, isRead: false }, { $set: { isRead: true } });
    res.json({ success: true });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

// DELETE /api/budget/messages — clears all read messages (or all if ?all=true)
exports.clearMessages = async (req, res) => {
  try {
    const filter = { user: req.user._id };
    if (req.query.all !== 'true') filter.isRead = true;
    await BudgetMessage.deleteMany(filter);
    res.json({ success: true });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

// Utility: called by budgetController.getStatus to upsert crossed-limit messages
exports.upsertLimitMessages = async (userId, year, month, overspent, groupSpending) => {
  try {
    const ops = [];

    for (const o of overspent) {
      const type = o.type;
      const msg = type.startsWith('cat_')
        ? `You have exceeded your ${type.substring(4)} category budget this month`
        : `You have exceeded your ${type} budget this month`;
      ops.push({
        updateOne: {
          filter: { user: userId, type, groupId: null, year, month },
          update: {
            $set: { message: msg, amountSpent: o.spent, limit: o.limit },
            $setOnInsert: { isRead: false, createdAt: new Date(), groupId: null, groupName: null },
          },
          upsert: true,
        },
      });
    }

    // Per-group specific messages
    for (const g of (groupSpending || [])) {
      if (g.budget != null && g.spent > g.budget) {
        ops.push({
          updateOne: {
            filter: { user: userId, type: 'group_specific', groupId: g.id, year, month },
            update: {
              $set: {
                message: `You have exceeded the budget for group "${g.name}" this month`,
                amountSpent: g.spent,
                limit: g.budget,
                groupName: g.name,
              },
              $setOnInsert: { isRead: false, createdAt: new Date() },
            },
            upsert: true,
          },
        });
      }
    }

    if (ops.length > 0) {
      await BudgetMessage.bulkWrite(ops, { ordered: false });
    }
  } catch (err) {
    console.error('upsertLimitMessages error:', err);
  }
};
