module.exports = (router, { auth, otpSendLimiter, otpVerifyLimiter, budgetCheck, handleUsage, upload, walletAuthMiddleware }) => {
  const transactionController = require('../../controllers/transactionController');
  const quickTransactionController = require('../../controllers/quickTransactionController');
  const analyticController = require('../../controllers/analyticController');
  const counterpartyController = require('../../controllers/counterpartyController');
  const limitsController = require('../../controllers/limitsController');
  const recurringTemplateController = require('../../controllers/recurringTemplateController');
  const calendarController = require('../../controllers/calendarController');
  const statementController = require('../../controllers/statementController');

  // Quick transactions
  router.get('/quick-transactions', auth, quickTransactionController.getQuickTransactions);
  router.put('/quick-transactions/:id/favourite', auth, quickTransactionController.toggleQuickTransactionFavourite);
  router.post('/quick-transactions', auth, handleUsage('quickTransaction'), budgetCheck('quick'), quickTransactionController.createQuickTransaction);
  router.post('/quick-transactions/with-coins', auth, quickTransactionController.createQuickTransactionWithCoins);
  router.put('/quick-transactions/:id', auth, quickTransactionController.updateQuickTransaction);
  router.delete('/quick-transactions/:id', auth, quickTransactionController.deleteQuickTransaction);
  router.put('/quick-transactions/:id/clear', auth, quickTransactionController.clearQuickTransaction);
  router.post('/quick-transactions/:id/pay', auth, walletAuthMiddleware, quickTransactionController.payQuickTransaction);
  router.post('/quick-transactions/:id/request-payment', auth, quickTransactionController.requestQuickTransactionPayment);
  router.post('/quick-transactions/:id/request-settlement', auth, quickTransactionController.requestQuickTransactionSettlement);
  router.post('/quick-transactions/:id/respond-settlement', auth, quickTransactionController.respondQuickTransactionSettlement);
  router.delete('/quick-transactions', auth, quickTransactionController.clearAllQuickTransactions);
  router.get('/quick-transactions/scheduled', auth, quickTransactionController.getScheduledQuickTransactions);
  router.delete('/quick-transactions/:id/cancel-scheduled', auth, quickTransactionController.cancelScheduledQuickTransaction);
  router.get('/quick-transactions/friend-balances', auth, quickTransactionController.getFriendBalances);
  router.get('/quick-transactions/:id', auth, quickTransactionController.getQuickTransactionById);

  // Secure transactions
  router.post('/transactions/create', auth, handleUsage('userTransaction'), budgetCheck('secure'), upload.array('files'), transactionController.createTransaction);
  router.post('/transactions/with-coins', auth, upload.array('files'), transactionController.createTransactionWithCoins);
  router.post('/transactions/check-email', auth, transactionController.checkEmailExists);
  router.post('/transactions/send-counterparty-otp', auth, otpSendLimiter, transactionController.sendCounterpartyOTP);
  router.post('/transactions/verify-counterparty-otp', auth, otpVerifyLimiter, transactionController.verifyCounterpartyOTP);
  router.post('/transactions/send-user-otp', auth, otpSendLimiter, transactionController.sendUserOTP);
  router.post('/transactions/verify-user-otp', auth, otpVerifyLimiter, transactionController.verifyUserOTP);
  router.post('/transactions/clear', auth, transactionController.clearTransaction);
  router.delete('/transactions/delete', auth, transactionController.deleteTransaction);
  router.post('/transactions/:transactionId/receipt', auth, transactionController.generateReceipt);
  router.put('/transactions/:transactionId/favourite', auth, transactionController.toggleFavourite);
  router.get('/transactions/user', auth, transactionController.getUserTransactions);

  // Partial payments
  router.post('/transactions/send-partial-payment-otp', auth, otpSendLimiter, transactionController.sendPartialPaymentOTP);
  router.post('/transactions/verify-partial-payment-otp', auth, otpVerifyLimiter, transactionController.verifyPartialPaymentOTP);
  router.post('/transactions/partial-payment/verify-pin', auth, transactionController.verifyPartialPaymentPin);
  router.post('/transactions/verify-creation-pin', auth, transactionController.verifyTransactionCreationPin);
  router.post('/transactions/partial-payment', auth, transactionController.processPartialPayment);
  router.put('/transactions/:id/chat/mark-seen', auth, transactionController.markTransactionChatSeen);
  router.get('/transactions/:transactionId', auth, transactionController.getTransactionDetails);

  // Analytics
  router.get('/analytics/user', auth, analyticController.getUserAnalytics);
  router.get('/analytics/secure', auth, analyticController.getUserAnalytics);
  router.get('/analytics/quick', auth, analyticController.getQuickAnalytics);
  router.get('/analytics/group', auth, analyticController.getGroupAnalytics);
  router.get('/analytics/groups', auth, analyticController.getGroupAnalytics);

  // Counterparties
  router.get('/counterparties/user', auth, counterpartyController.getUserCounterparties);
  router.get('/counterparties/stats', auth, counterpartyController.getCounterpartyStats);
  router.post('/counterparties/stats-batch', auth, counterpartyController.getCounterpartyStatsBatch);

  // Daily limits
  router.get('/limits/daily', auth, limitsController.getDailyLimits);
  router.get('/limits/transaction/:transactionId/messages', auth, limitsController.getTransactionMessageLimit);
  router.get('/limits/group/:groupId/messages', auth, limitsController.getGroupMessageLimit);
  router.get('/limits/group/:groupId/expenses', auth, limitsController.getGroupExpenseLimit);

  // Recurring templates
  router.post('/recurring-templates', auth, recurringTemplateController.createTemplate);
  router.get('/recurring-templates/mine', auth, recurringTemplateController.getMyTemplates);
  router.patch('/recurring-templates/:id', auth, recurringTemplateController.updateTemplate);
  router.delete('/recurring-templates/:id', auth, recurringTemplateController.deleteTemplate);

  // Calendar due-dates
  router.get('/calendar/due-dates', auth, calendarController.getDueDates);

  // Statement export
  router.get('/statements/export', auth, statementController.exportStatement);
};
