const rateLimit = require('express-rate-limit');

// Global API limiter — applied to all /api routes.
// 300 requests per 15 min per IP is generous for real usage but stops scripted abuse.
exports.globalApiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please slow down.' },
  skip: (req) => {
    // Don't rate-limit Razorpay webhook — it comes from Razorpay's IPs, not users
    return req.path.startsWith('/payment/webhook');
  },
});

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

// User search: each keystroke can trigger a query; 30 req/min prevents scraping all users.
exports.searchUsersLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many search requests. Please slow down.' },
});

// Manual payment-ID verification: not a brute-forceable secret (Razorpay payment
// IDs are long random strings), but still throttle scripted submission attempts.
exports.manualPaymentVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many verification attempts. Please try again later.' },
});
