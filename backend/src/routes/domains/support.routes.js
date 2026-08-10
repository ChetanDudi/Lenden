module.exports = (router, { auth, isAdmin, io, otpSendLimiter }) => {
  const supportController = require('../../controllers/supportController')(io);
  const contactConfigController = require('../../controllers/contactConfigController');
  const disputeController = require('../../controllers/disputeController');
  const fraudAlertController = require('../../controllers/fraudAlertController');

  // Contact info (public)
  router.get('/contact-info', contactConfigController.getPublicContactConfig);
  router.get('/contact-categories', contactConfigController.getContactCategories);
  router.post('/contact-message', otpSendLimiter, contactConfigController.submitContactMessage);
  router.get('/contact-messages/mine', auth, contactConfigController.getUserMessages);

  // Support queries (user)
  router.post('/support/queries', auth, supportController.createSupportQuery);
  router.get('/support/queries/me', auth, supportController.getUserSupportQueries);
  router.put('/support/queries/:queryId', auth, supportController.updateSupportQuery);
  router.delete('/support/queries/:queryId', auth, supportController.deleteSupportQuery);

  // Disputes (user)
  router.post('/disputes', auth, disputeController.createDispute);
  router.get('/disputes/mine', auth, disputeController.getMyDisputes);
  router.get('/disputes/:id', auth, disputeController.getDisputeById);

  // Admin: support queries
  router.get('/admin/support/queries', auth, isAdmin, supportController.getAllSupportQueries);
  router.get('/admin/support/queries/export', auth, isAdmin, supportController.exportSupportQueries);
  router.post('/admin/support/queries/:queryId/reply', auth, isAdmin, supportController.replyToSupportQuery);
  router.put('/admin/support/queries/:queryId/replies/:replyId', auth, isAdmin, supportController.editReply);
  router.delete('/admin/support/queries/:queryId/replies/:replyId', auth, isAdmin, supportController.deleteReply);
  router.patch('/admin/support/queries/:queryId/status', auth, isAdmin, supportController.updateQueryStatus);
  router.patch('/admin/support/queries/:queryId/workflow', auth, isAdmin, supportController.updateQueryWorkflow);

  // Admin: contact config & messages
  router.get('/admin/contact-info', auth, isAdmin, contactConfigController.getAdminContactConfig);
  router.put('/admin/contact-info', auth, isAdmin, contactConfigController.updateAdminContactConfig);
  router.get('/admin/contact-messages', auth, isAdmin, contactConfigController.getAdminMessages);
  router.patch('/admin/contact-messages/:id/status', auth, isAdmin, contactConfigController.updateMessageStatus);
  router.post('/admin/contact-messages/:id/reply', auth, isAdmin, contactConfigController.replyToMessage);

  // Admin: disputes
  router.get('/admin/disputes', auth, isAdmin, disputeController.adminListDisputes);
  router.patch('/admin/disputes/:id', auth, isAdmin, disputeController.adminResolveDispute);

  // Admin: fraud alerts
  router.get('/admin/fraud-alerts', auth, isAdmin, fraudAlertController.listFraudAlerts);
  router.patch('/admin/fraud-alerts/:id', auth, isAdmin, fraudAlertController.updateFraudAlert);
  router.post('/admin/fraud-alerts/scan', auth, isAdmin, fraudAlertController.triggerFraudScan);
};
