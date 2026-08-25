const bcrypt = require('bcryptjs');
const User = require('../models/user');

const PIN_MAX_ATTEMPTS = 5;
const PIN_LOCK_DURATION_MS = 15 * 60 * 1000; // 15 minutes

// Middleware that enforces a second factor before any outgoing wallet payment.
// The request body must contain exactly one of:
//   authPin  — user's 6-digit transaction PIN (server-bcrypt-verified)
//   authOtp  — 6-digit one-time code sent to the user's registered email
//              (alias: `otp` for backward-compat with the existing payToUser flow)
//
// On success: calls next(). Sets req.walletAuthMethod to 'pin' or 'otp'.
// On failure: returns 400 / 423 and does NOT call next().
module.exports = async function walletAuthMiddleware(req, res, next) {
  try {
  const { authPin, authOtp, otp } = req.body;
  const verifyOtp = authOtp || otp;

  if (!authPin && !verifyOtp) {
    return res.status(400).json({ error: 'Authentication required: provide authPin or authOtp.' });
  }

  const user = await User.findById(req.user._id).select(
    'walletPin walletPinAttempts walletPinLockedUntil walletPayOTP email'
  );
  if (!user) return res.status(401).json({ error: 'User not found' });

  // ── PIN path ──────────────────────────────────────────────────────────────
  if (authPin) {
    if (!user.walletPin) {
      return res.status(400).json({ error: 'No transaction PIN has been set. Please set a PIN in Settings first, or use Email OTP.' });
    }

    if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
      const minutesLeft = Math.ceil((user.walletPinLockedUntil - Date.now()) / 60000);
      return res.status(423).json({
        error: `Too many wrong PIN attempts. Try again in ${minutesLeft} minute${minutesLeft === 1 ? '' : 's'}.`,
        lockedUntil: user.walletPinLockedUntil,
      });
    }

    const valid = await bcrypt.compare(String(authPin), user.walletPin);
    if (!valid) {
      const newAttempts = (user.walletPinAttempts || 0) + 1;
      const lockUpdate = newAttempts >= PIN_MAX_ATTEMPTS
        ? { walletPinAttempts: 0, walletPinLockedUntil: new Date(Date.now() + PIN_LOCK_DURATION_MS) }
        : { walletPinAttempts: newAttempts };
      await User.updateOne({ _id: user._id }, { $set: lockUpdate });

      const attemptsLeft = PIN_MAX_ATTEMPTS - newAttempts;
      if (attemptsLeft <= 0) {
        return res.status(423).json({ error: `Too many wrong PIN attempts. Account locked for 15 minutes.` });
      }
      return res.status(400).json({
        error: `Incorrect PIN. ${attemptsLeft} attempt${attemptsLeft === 1 ? '' : 's'} remaining.`,
      });
    }

    await User.updateOne({ _id: user._id }, { $set: { walletPinAttempts: 0 }, $unset: { walletPinLockedUntil: 1 } });
    req.walletAuthMethod = 'pin';
    return next();
  }

  // ── OTP path ──────────────────────────────────────────────────────────────
  const OTP_MAX_ATTEMPTS = 5;

  if (!user.walletPayOTP || !user.walletPayOTP.code) {
    return res.status(400).json({ error: 'No OTP is pending. Please request a new OTP first.' });
  }
  if (new Date() > new Date(user.walletPayOTP.expiry)) {
    await User.updateOne({ _id: user._id }, { $unset: { walletPayOTP: 1 } });
    return res.status(400).json({ error: 'OTP has expired. Please request a new one.' });
  }

  if (user.walletPayOTP.code !== String(verifyOtp)) {
    const newAttempts = (user.walletPayOTP.attemptCount || 0) + 1;
    if (newAttempts >= OTP_MAX_ATTEMPTS) {
      await User.updateOne({ _id: user._id }, { $unset: { walletPayOTP: 1 } });
      return res.status(423).json({ error: 'Too many wrong OTP attempts. The OTP has been invalidated. Please request a new one.' });
    }
    await User.updateOne({ _id: user._id }, { $set: { 'walletPayOTP.attemptCount': newAttempts } });
    const attemptsLeft = OTP_MAX_ATTEMPTS - newAttempts;
    return res.status(400).json({
      error: `Invalid OTP. ${attemptsLeft} attempt${attemptsLeft === 1 ? '' : 's'} remaining.`,
    });
  }

  // One-time use — clear immediately after successful verification.
  await User.updateOne({ _id: user._id }, { $unset: { walletPayOTP: 1 } });
  req.walletAuthMethod = 'otp';
  return next();
  } catch (err) {
    console.error('walletAuthMiddleware error:', err);
    return res.status(500).json({ error: 'Authentication check failed. Please try again.' });
  }
};
