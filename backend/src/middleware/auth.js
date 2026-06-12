const jwt = require('jsonwebtoken');
const User = require('../models/user');

module.exports = async function (req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'No token provided' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      console.error('[Auth] JWT_SECRET environment variable is not set');
      return res.status(500).json({ error: 'Server misconfiguration' });
    }
    const decoded = jwt.verify(token, jwtSecret);
    if (!decoded._id && decoded.userId) {
      decoded._id = decoded.userId;
    }
    if (!decoded.userId && decoded._id) {
      decoded.userId = decoded._id;
    }
    if (!decoded.id && decoded._id) {
      decoded.id = decoded._id;
    }
    if (decoded.role !== 'admin' && decoded._id) {
      const user = await User.findById(decoded._id).select(
        'isActive deactivatedAccount suspendedUntil suspensionReason forceLogoutAfter'
      );
      if (!user) {
        return res.status(401).json({ error: 'User not found' });
      }
      if (user.isActive === false || user.deactivatedAccount === true) {
        return res.status(403).json({ error: 'Your account is inactive' });
      }
      if (user.suspendedUntil && user.suspendedUntil > new Date()) {
        return res.status(403).json({
          error: 'Your account is suspended',
          suspendedUntil: user.suspendedUntil,
          suspensionReason: user.suspensionReason || '',
        });
      }
      if (user.forceLogoutAfter) {
        const issuedAtMs = decoded.iat ? decoded.iat * 1000 : 0;
        if (issuedAtMs && issuedAtMs < new Date(user.forceLogoutAfter).getTime()) {
          return res.status(401).json({ error: 'Session expired. Please login again.' });
        }
      }
    }
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};
