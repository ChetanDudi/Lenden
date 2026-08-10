module.exports = (router, { auth, otpSendLimiter, otpVerifyLimiter, manualPaymentVerifyLimiter, walletAuthMiddleware, isAdmin }) => {
  const walletController = require('../../controllers/walletController');
  const withdrawalController = require('../../controllers/withdrawalController');
  const paymentController = require('../../controllers/paymentController');
  const scanPaymentController = require('../../controllers/scanPaymentController');
  const adminFeatureController = require('../../controllers/adminFeatureController');

  // Wallet balance & history
  router.get('/wallet/balance', auth, walletController.getBalance);
  router.get('/wallet/history', auth, walletController.getHistory);

  // Outgoing wallet payments (PIN or OTP gated)
  router.post('/wallet/pay', auth, walletAuthMiddleware, walletController.pay);
  router.post('/wallet/qr-pay', auth, walletAuthMiddleware, walletController.qrPay);
  router.post('/wallet/pay-subscription', auth, walletController.paySubscription);

  // Real-money top-up verification
  router.post('/wallet/topup/manual/verify', auth, manualPaymentVerifyLimiter, walletController.verifyManualTopUp);

  // Pay-to-user flow (send OTP → verify OTP → transfer)
  router.post('/wallet/auth/send-otp', auth, otpSendLimiter, walletController.sendWalletAuthOtp);
  router.post('/wallet/pay/send-otp', auth, otpSendLimiter, walletController.sendPayOtp);
  router.post('/wallet/pay/verify-otp', auth, otpVerifyLimiter, walletAuthMiddleware, walletController.payToUserWithOtp);

  // Wallet transaction PIN management
  router.get('/wallet/pin/status', auth, walletController.getWalletPinStatus);
  router.post('/wallet/pin/verify-otp', auth, otpVerifyLimiter, walletController.verifyWalletOtp);
  router.post('/wallet/pin/set', auth, walletController.setWalletPin);
  router.post('/wallet/pin/remove', auth, walletController.removeWalletPin);

  // Razorpay payment config & webhook
  router.get('/payment/config', auth, paymentController.getPaymentConfig);
  router.post('/payment/verify-manual', auth, manualPaymentVerifyLimiter, paymentController.verifyManualPayment);
  router.post('/payment/webhook', paymentController.razorpayWebhook);

  // Withdrawals (user)
  router.post('/wallet/withdraw', auth, walletAuthMiddleware, withdrawalController.initiateWithdrawal);
  router.get('/wallet/withdrawals', auth, withdrawalController.getWithdrawalHistory);
  router.post('/wallet/payout-webhook', withdrawalController.handlePayoutWebhook);

  // QR / scan payments (user)
  router.post('/wallet/scan-payment', auth, walletAuthMiddleware, scanPaymentController.initiateScanPayment);
  router.get('/wallet/scan-payments', auth, scanPaymentController.getScanPaymentHistory);

  // Admin: withdrawals
  router.get('/admin/withdrawals', auth, isAdmin, withdrawalController.adminGetWithdrawals);
  router.post('/admin/withdrawals/:id/process', auth, isAdmin, withdrawalController.adminMarkProcessed);
  router.post('/admin/withdrawals/:id/reject', auth, isAdmin, withdrawalController.adminRejectWithdrawal);

  // Admin: real-money top-up overview
  router.get('/admin/real-payments/topups', auth, isAdmin, walletController.adminGetTopUps);

  // Admin: in-app wallet transfer history
  router.get('/admin/in-app-transactions/counts', auth, isAdmin, adminFeatureController.getInAppTransactionCounts);
  router.get('/admin/in-app-transactions/volume', auth, isAdmin, adminFeatureController.getInAppVolumeData);
  router.get('/admin/in-app-transactions/export', auth, isAdmin, adminFeatureController.exportInAppTransactions);
  router.post('/admin/in-app-transactions/:id/flag', auth, isAdmin, adminFeatureController.flagInAppTransaction);
  router.get('/admin/in-app-transactions', auth, isAdmin, adminFeatureController.getAdminInAppTransactions);

  // Admin: scan payments
  router.get('/admin/scan-payments', auth, isAdmin, scanPaymentController.adminGetScanPayments);
  router.post('/admin/scan-payments/:id/process', auth, isAdmin, scanPaymentController.adminMarkProcessed);
  router.post('/admin/scan-payments/:id/reject', auth, isAdmin, scanPaymentController.adminRejectScanPayment);
};
