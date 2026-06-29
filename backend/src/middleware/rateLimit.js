const rateLimit = require('express-rate-limit');

// Login: a handful of genuine typos is normal, but stop credential-stuffing/brute-force.
exports.loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many login attempts. Please try again in a few minutes.' },
});

// OTP send: prevents spamming a victim's inbox/phone or burning SMS/email quota.
exports.otpSendLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many OTP requests. Please wait a few minutes before trying again.' },
});

// OTP verify: OTPs are 6 digits, so this must be tight to block brute-forcing the code.
exports.otpVerifyLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many attempts. Please request a new OTP.' },
});

// Password reset completion: low frequency action, keep tight.
exports.passwordResetLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many password reset attempts. Please try again later.' },
});
