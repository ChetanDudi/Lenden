const express = require('express');
const router = express.Router();
const multer = require('multer');

module.exports = (io) => {
  const auth = require('../middleware/auth');
  const sessionTimeout = require('../middleware/sessionTimeout');
  const { globalApiLimiter, loginLimiter, otpSendLimiter, otpVerifyLimiter, passwordResetLimiter, manualPaymentVerifyLimiter } = require('../middleware/rateLimit');
  router.use(globalApiLimiter);
  const walletAuthMiddleware = require('../middleware/walletAuth');
  const budgetCheck = require('../middleware/budgetCheck');
  const handleUsage = require('../middleware/handleUsage');
  const { handleAdUpload } = require('../middleware/adUpload');
  const isAdmin = require('../middleware/isAdmin');

  const upload = multer({ limits: { fileSize: 10 * 1024 * 1024 } });

  const deps = {
    auth, sessionTimeout, walletAuthMiddleware, budgetCheck, handleUsage,
    upload, handleAdUpload,
    loginLimiter, otpSendLimiter, otpVerifyLimiter, passwordResetLimiter, manualPaymentVerifyLimiter,
    isAdmin, io,
  };

  require('./domains/auth.routes')(router, deps);
  require('./domains/social.routes')(router, deps);
  require('./domains/transaction.routes')(router, deps);
  require('./domains/group.routes')(router, deps);
  require('./domains/wallet.routes')(router, deps);
  require('./domains/subscription.routes')(router, deps);
  require('./domains/content.routes')(router, deps);
  require('./domains/support.routes')(router, deps);
  require('./domains/budget.routes')(router, deps);
  require('./domains/community.routes')(router, deps);
  require('./domains/admin.routes')(router, deps);

  // App version check — no auth required so client can call before login
  router.get('/app-version', (req, res) => {
    res.json({
      minVersion: process.env.APP_MIN_VERSION || '1.0.0',
      latestVersion: process.env.APP_LATEST_VERSION || '1.0.0',
      forceUpdate: false,
      updateUrl: process.env.APP_UPDATE_URL || '',
    });
  });

  return router;
};
