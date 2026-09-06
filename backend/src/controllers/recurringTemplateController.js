const RecurringQuickTransactionTemplate = require('../models/recurringQuickTransactionTemplate');
const User = require('../models/user');

const { isBlockedBy } = require('../utils/userHelpers');

exports.createTemplate = async (req, res) => {
  try {
    const { amount, currency, counterpartyEmail, role, description, frequency, startDate } = req.body;

    const parsedAmount = parseFloat(amount);
    if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
      return res.status(400).json({ error: 'amount must be a positive number' });
    }
    if (description && description.length > 300) {
      return res.status(400).json({ error: 'Description must be 300 characters or less.' });
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!counterpartyEmail || !emailRegex.test(counterpartyEmail)) {
      return res.status(400).json({ error: 'Valid counterpartyEmail is required' });
    }
    if (!['lender', 'borrower'].includes(role)) {
      return res.status(400).json({ error: 'role must be lender or borrower' });
    }
    if (!['weekly', 'monthly'].includes(frequency)) {
      return res.status(400).json({ error: 'frequency must be weekly or monthly' });
    }
    const start = startDate ? new Date(startDate) : new Date();
    if (isNaN(start.getTime())) {
      return res.status(400).json({ error: 'Invalid startDate' });
    }

    const user = await User.findById(req.user._id).select('email blockedUsers');
    if (user.email.toLowerCase() === counterpartyEmail.toLowerCase()) {
      return res.status(400).json({ error: 'User and counterparty email cannot be the same.' });
    }
    const counterparty = await User.findOne({ email: counterpartyEmail }).select('_id email blockedUsers');
    if (!counterparty) {
      return res.status(404).json({ error: 'Counterparty email not found.' });
    }
    if (isBlockedBy(user, counterparty._id) || isBlockedBy(counterparty, user._id)) {
      return res.status(403).json({ error: 'Cannot create a recurring template with a blocked user.' });
    }

    const template = await RecurringQuickTransactionTemplate.create({
      creatorEmail: user.email,
      counterpartyEmail,
      amount: parsedAmount,
      currency: currency || 'INR',
      role,
      description: description || '',
      frequency,
      dayOfMonth: frequency === 'monthly' ? start.getDate() : null,
      weekday: frequency === 'weekly' ? start.getDay() : null,
      nextRunAt: start,
    });

    res.status(201).json({ message: 'Recurring template created.', template });
  } catch (err) {
    console.error('Error creating recurring template:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getMyTemplates = async (req, res) => {
  try {
    const templates = await RecurringQuickTransactionTemplate.find({ creatorEmail: req.user.email })
      .sort({ nextRunAt: 1 });
    res.json({ templates });
  } catch (err) {
    console.error('Error fetching recurring templates:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateTemplate = async (req, res) => {
  try {
    const template = await RecurringQuickTransactionTemplate.findOne({
      _id: req.params.id,
      creatorEmail: req.user.email,
    });
    if (!template) return res.status(404).json({ error: 'Template not found' });

    const { amount, description, isActive } = req.body;
    if (amount !== undefined) {
      const parsedAmount = parseFloat(amount);
      if (!parsedAmount || parsedAmount <= 0 || !isFinite(parsedAmount)) {
        return res.status(400).json({ error: 'amount must be a positive number' });
      }
      template.amount = parsedAmount;
    }
    if (description !== undefined) template.description = description;
    if (isActive !== undefined) {
      template.isActive = !!isActive;
      if (template.isActive) template.pausedReason = '';
    }
    await template.save();

    res.json({ message: 'Template updated.', template });
  } catch (err) {
    console.error('Error updating recurring template:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

exports.deleteTemplate = async (req, res) => {
  try {
    const template = await RecurringQuickTransactionTemplate.findOneAndDelete({
      _id: req.params.id,
      creatorEmail: req.user.email,
    });
    if (!template) return res.status(404).json({ error: 'Template not found' });
    res.json({ message: 'Template deleted.' });
  } catch (err) {
    console.error('Error deleting recurring template:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
