module.exports = (router, { auth, isAdmin, upload }) => {
  const adminController = require('../../controllers/adminController');
  const adminTransactionController = require('../../controllers/adminTransactionController');
  const settingsController = require('../../controllers/settingsController');
  const currencyConversionController = require('../../controllers/currencyConversionController');
  const adminCoinPricingController = require('../../controllers/adminCoinPricingController');
  const referralController = require('../../controllers/referralController');
  const userActivityController = require('../../controllers/userActivityController');

  // Dashboard summary
  router.get('/admin/dashboard-summary', auth, isAdmin, adminController.getDashboardSummary);

  // User management
  router.get('/admin/users', auth, isAdmin, adminController.getAllUsers);
  router.get('/admin/users/export', auth, isAdmin, adminController.exportUsers);
  router.patch('/admin/users/clear-pending', auth, isAdmin, adminController.clearPendingUsers);
  router.patch('/admin/users/:userId/review-pending', auth, isAdmin, adminController.reviewPendingUser);
  router.post('/admin/users/:userId/notes', auth, isAdmin, adminController.addAdminNoteToUser);
  router.patch('/admin/users/:userId/suspension', auth, isAdmin, adminController.updateUserSuspension);
  router.post('/admin/users/:userId/force-logout', auth, isAdmin, adminController.forceLogoutUser);
  router.get('/admin/users/:userId/details', auth, isAdmin, adminController.getUserDetails);
  router.patch('/admin/users/bulk-status', auth, isAdmin, adminController.bulkUpdateUserStatus);
  router.patch('/admin/users/:userId/status', auth, isAdmin, adminController.updateUserStatus);
  router.put('/admin/users/:userId', auth, isAdmin, adminController.updateUser);
  router.delete('/admin/users/:userId', auth, isAdmin, adminController.deleteUser);

  // Transaction management
  router.get('/admin/transactions', auth, isAdmin, adminTransactionController.getAllTransactions);
  router.put('/admin/transactions/:transactionId', auth, isAdmin, upload.any(), adminTransactionController.updateTransaction);
  router.delete('/admin/transactions/:transactionId', auth, isAdmin, adminTransactionController.deleteTransaction);

  // Group transaction management
  router.get('/admin/group-transactions', auth, isAdmin, adminController.getAllGroupTransactions);
  router.put('/admin/group-transactions/:groupId', auth, isAdmin, adminController.updateGroupTransaction);
  router.delete('/admin/group-transactions/:groupId', auth, isAdmin, adminController.deleteGroupTransaction);
  router.post('/admin/group-transactions/:groupId/members', auth, isAdmin, adminController.addMemberToGroup);
  router.delete('/admin/group-transactions/:groupId/members/:memberId', auth, isAdmin, adminController.removeMemberFromGroup);
  router.post('/admin/group-transactions/:groupId/expenses', auth, isAdmin, adminController.addExpenseToGroup);
  router.put('/admin/group-transactions/:groupId/expenses/:expenseId', auth, isAdmin, adminController.updateExpenseInGroup);
  router.delete('/admin/group-transactions/:groupId/expenses/:expenseId', auth, isAdmin, adminController.deleteExpenseFromGroup);
  router.post('/admin/group-transactions/:groupId/expenses/:expenseId/settle', auth, isAdmin, adminController.settleExpenseSplitsInGroup);

  // Quick transaction management
  router.get('/admin/quick-transactions', auth, isAdmin, adminController.getAllQuickTransactions);
  router.put('/admin/quick-transactions/:id', auth, isAdmin, adminController.updateAdminQuickTransaction);
  router.delete('/admin/quick-transactions/:id', auth, isAdmin, adminController.deleteAdminQuickTransaction);

  // Admin account management
  router.get('/admin/admins', auth, isAdmin, adminController.getAllAdmins);
  router.get('/admin/audit-logs', auth, isAdmin, adminController.getAdminAuditLogs);
  router.post('/admin/admins', auth, isAdmin, adminController.addAdmin);
  router.delete('/admin/admins/:adminId', auth, isAdmin, adminController.removeAdmin);
  router.patch('/admin/admins/:adminId/superadmin', auth, isAdmin, adminController.toggleSuperAdminStatus);
  router.patch('/admin/admins/:adminId/permissions', auth, isAdmin, adminController.updateAdminPermissions);

  // System settings
  router.get('/admin/system-settings', auth, isAdmin, adminController.getSystemSettings);
  router.put('/admin/system-settings', auth, isAdmin, adminController.updateSystemSettings);
  router.get('/admin/analytics-settings', auth, isAdmin, adminController.getAnalyticsSettings);
  router.put('/admin/analytics-settings', auth, isAdmin, adminController.updateAnalyticsSettings);
  router.get('/admin/security-settings', auth, isAdmin, adminController.getSecuritySettings);
  router.put('/admin/security-settings', auth, isAdmin, adminController.updateSecuritySettings);

  // Notification settings (admin)
  router.get('/admin/notification-settings', auth, isAdmin, settingsController.getAdminNotificationSettings);
  router.put('/admin/notification-settings', auth, isAdmin, settingsController.updateAdminNotificationSettings);

  // Coin pricing
  router.get('/admin/coin-pricing', auth, isAdmin, adminCoinPricingController.getCoinPricing);
  router.put('/admin/coin-pricing', auth, isAdmin, adminCoinPricingController.updateCoinPricing);

  // Currency conversions
  router.get('/currency-conversions/supported', auth, currencyConversionController.getSupportedCurrencies);
  router.get('/currency-conversions/matrix', auth, currencyConversionController.getPublicCurrencyMatrix);
  router.get('/admin/currency-conversions', auth, isAdmin, currencyConversionController.getAdminCurrencyConversions);
  router.put('/admin/currency-conversions', auth, isAdmin, currencyConversionController.upsertAdminCurrencyConversion);
  router.post('/admin/currency-conversions/currencies', auth, isAdmin, currencyConversionController.addSupportedCurrency);
  router.post('/admin/currency-conversions/sync-live-rates', auth, isAdmin, currencyConversionController.syncLiveRates);

  // Data management
  router.get('/admin/data/stats', auth, isAdmin, adminController.getSystemStats);
  router.get('/admin/data/export', auth, isAdmin, adminController.exportAdminData);
  router.post('/admin/data/maintenance', auth, isAdmin, adminController.performMaintenance);

  // User activity tracking
  router.get('/admin/user-activity/:searchTerm', auth, isAdmin, userActivityController.getUserActivity);

  // Referral config
  router.get('/admin/referral-config', auth, isAdmin, referralController.getReferralConfigForAdmin);
  router.put('/admin/referral-config', auth, isAdmin, referralController.updateReferralConfigForAdmin);
};
