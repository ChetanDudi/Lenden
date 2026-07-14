const User = require('../models/user');

module.exports = async function sessionTimeout(req, res, next) {
  try {
    // Only check for authenticated user requests
    if (!req.user || req.user.role !== 'user') return next();

    const user = await User.findById(req.user._id).select('sessionTimeout lastActivityAt');
    if (!user) return next();

    // sessionTimeout in minutes, 0 means "Never"
    const timeout = user.sessionTimeout || 30;
    if (timeout === 0) {
      // Never timeout
      user.lastActivityAt = new Date();
      await user.save();
      return next();
    }

    const now = Date.now();
    const lastActivity = user.lastActivityAt ? new Date(user.lastActivityAt).getTime() : now;
    const diffMinutes = (now - lastActivity) / 60000;

    if (diffMinutes > timeout) {
      // Session expired
      return res.status(440).json({ error: 'Session timed out due to inactivity.' });
    }

    // Update lastActivityAt
    user.lastActivityAt = new Date();
    await user.save();
    next();
  } catch (e) {
    next();
  }
};
