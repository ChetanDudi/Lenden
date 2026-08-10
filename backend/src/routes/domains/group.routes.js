module.exports = (router, { auth, otpVerifyLimiter, budgetCheck, handleUsage, upload, walletAuthMiddleware, io }) => {
  const groupTransactionController = require('../../controllers/groupTransactionController');
  const groupChatController = require('../../controllers/groupChatController')(io);

  // Create group
  router.post('/group-transactions', auth, handleUsage('group'), groupTransactionController.createGroup);
  router.post('/group-transactions/with-coins', auth, groupTransactionController.createGroupWithCoins);

  // Membership
  router.post('/group-transactions/:groupId/add-member', auth, groupTransactionController.addMember);
  router.post('/group-transactions/:groupId/remove-member', auth, groupTransactionController.removeMember);
  router.post('/group-transactions/:groupId/leave', auth, groupTransactionController.leaveGroup);
  router.post('/group-transactions/:groupId/request-leave', auth, groupTransactionController.requestLeave);
  router.post('/group-transactions/:groupId/send-leave-request', auth, groupTransactionController.sendLeaveRequest);

  // Expenses
  router.post('/group-transactions/:groupId/add-expense', auth, budgetCheck('group'), groupTransactionController.addExpense);
  router.put('/group-transactions/:groupId/expenses/:expenseId', auth, groupTransactionController.editExpense);
  router.delete('/group-transactions/:groupId/expenses/:expenseId', auth, groupTransactionController.deleteExpense);
  router.post('/group-transactions/:groupId/expenses/:expenseId/settle', auth, groupTransactionController.settleExpenseSplits);

  // Settlement
  router.post('/group-transactions/:groupId/settle-member-expenses', auth, groupTransactionController.settleMemberExpenses);
  router.post('/group-transactions/:groupId/self-settle', auth, groupTransactionController.selfSettleExpenses);
  router.post('/group-transactions/:groupId/record-payment', auth, walletAuthMiddleware, groupTransactionController.recordMemberPayment);
  router.post('/group-transactions/:groupId/settle-balance', auth, groupTransactionController.settleBalance);
  router.post('/group-transactions/:groupId/otp-verify-settle', auth, otpVerifyLimiter, groupTransactionController.otpVerifySettle);

  // Group info & metadata
  router.get('/group-transactions/user-groups', auth, groupTransactionController.getUserGroups);
  router.put('/group-transactions/:groupId/colour', auth, groupTransactionController.updateGroupColor);
  router.put('/group-transactions/:groupId/color', auth, groupTransactionController.updateGroupColor);
  router.put('/group-transactions/:groupId/image', auth, upload.single('groupImage'), groupTransactionController.uploadGroupImage);
  router.get('/group-transactions/:groupId/image', groupTransactionController.getGroupImage);
  router.delete('/group-transactions/:groupId/image', auth, groupTransactionController.removeGroupImage);
  router.delete('/group-transactions/:groupId', auth, groupTransactionController.deleteGroup);
  router.put('/group-transactions/:groupId/favourite', auth, groupTransactionController.toggleGroupFavourite);
  router.post('/group-transactions/:groupId/receipt', auth, groupTransactionController.generateGroupReceipt);
  router.get('/group-transactions/:groupId/stats', auth, groupTransactionController.getGroupStats);

  // Join codes
  router.post('/group-transactions/join', auth, groupTransactionController.joinByCode);
  router.post('/group-transactions/:groupId/join-code', auth, groupTransactionController.generateJoinCode);
  router.delete('/group-transactions/:groupId/join-code', auth, groupTransactionController.disableJoinCode);

  // Group chat
  router.get('/group-chat/messages/:groupTransactionId', auth, groupChatController.getGroupMessages);
};
