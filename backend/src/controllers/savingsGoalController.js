const SavingsGoal = require('../models/savingsGoal');

exports.getGoals = async (req, res) => {
  try {
    const goals = await SavingsGoal.find({ user: req.user._id }).sort({ createdAt: -1 }).lean();
    res.json(goals);
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.createGoal = async (req, res) => {
  try {
    const { name, emoji, targetAmount, savedAmount, deadline, color } = req.body;
    if (!name?.trim()) return res.status(400).json({ message: 'Name is required' });
    if (!targetAmount || parseFloat(targetAmount) < 1) return res.status(400).json({ message: 'Target amount must be at least 1' });

    const goal = await SavingsGoal.create({
      user: req.user._id,
      name: name.trim(),
      emoji: emoji || '🎯',
      targetAmount: parseFloat(targetAmount),
      savedAmount: savedAmount ? Math.max(0, parseFloat(savedAmount)) : 0,
      deadline: deadline ? new Date(deadline) : null,
      color: color || '#00BCD4',
      isCompleted: false,
    });
    res.status(201).json(goal);
  } catch (err) {
    res.status(500).json({ message: 'Server error', detail: err.message });
  }
};

exports.updateGoal = async (req, res) => {
  try {
    const goal = await SavingsGoal.findOne({ _id: req.params.id, user: req.user._id });
    if (!goal) return res.status(404).json({ message: 'Goal not found' });

    const { name, emoji, targetAmount, savedAmount, deadline, color, isCompleted } = req.body;
    if (name !== undefined) goal.name = name.trim();
    if (emoji !== undefined) goal.emoji = emoji;
    if (targetAmount !== undefined) goal.targetAmount = parseFloat(targetAmount);
    if (savedAmount !== undefined) goal.savedAmount = Math.max(0, parseFloat(savedAmount));
    if (deadline !== undefined) goal.deadline = deadline ? new Date(deadline) : null;
    if (color !== undefined) goal.color = color;
    if (isCompleted !== undefined) goal.isCompleted = isCompleted;
    if (goal.savedAmount >= goal.targetAmount) goal.isCompleted = true;

    await goal.save();
    res.json(goal);
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.deleteGoal = async (req, res) => {
  try {
    const result = await SavingsGoal.deleteOne({ _id: req.params.id, user: req.user._id });
    if (result.deletedCount === 0) return res.status(404).json({ message: 'Goal not found' });
    res.json({ message: 'Goal deleted' });
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.addSavings = async (req, res) => {
  try {
    const goal = await SavingsGoal.findOne({ _id: req.params.id, user: req.user._id });
    if (!goal) return res.status(404).json({ message: 'Goal not found' });

    const amount = parseFloat(req.body.amount);
    if (!amount || amount <= 0) return res.status(400).json({ message: 'Amount must be positive' });

    goal.savedAmount = Math.min(goal.targetAmount, goal.savedAmount + amount);
    if (goal.savedAmount >= goal.targetAmount) goal.isCompleted = true;
    await goal.save();
    res.json(goal);
  } catch {
    res.status(500).json({ message: 'Server error' });
  }
};
