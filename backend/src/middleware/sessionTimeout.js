const User = require('../models/user');

module.exports = async function sessionTimeout(req, res, next) {
  try {
    if (!req.user || req.user.role !== 'user') return next();

    const user = await User.findById(req.user._id).select('privacySettings');
    if (!user) return next();

    const ps = user.privacySettings || {};
    // 0 = never timeout. Default to 0 so users without an explicit setting are never timed out.
    const timeout = typeof ps.sessionTimeout === 'number' ? ps.sessionTimeout : 0;

    if (timeout === 0) {
      await User.updateOne(
        { _id: req.user._id },
        { $set: { 'privacySettings.lastActivityAt': new Date() } }
      );
      return next();
    }

    const now = Date.now();
    // Use JWT iat as a floor: a freshly-issued token means the session cannot have timed
    // out yet, regardless of any stale lastActivityAt value in the database.
    const iatMs = req.user.iat ? req.user.iat * 1000 : now;
    const storedMs = ps.lastActivityAt ? new Date(ps.lastActivityAt).getTime() : iatMs;
    const effectiveLastActivity = Math.max(storedMs, iatMs);
    const diffMinutes = (now - effectiveLastActivity) / 60000;

    if (diffMinutes > timeout) {
      return res.status(440).json({ error: 'Session timed out due to inactivity.' });
    }

    await User.updateOne(
      { _id: req.user._id },
      { $set: { 'privacySettings.lastActivityAt': new Date() } }
    );
    next();
  } catch (e) {
    next();
  }
};
