module.exports = (router, { auth, isAdmin }) => {
  const subscriptionController = require('../../controllers/subscriptionController');
  const adminFeatureController = require('../../controllers/adminFeatureController');

  // Public subscription info (no auth — shown before login/signup)
  router.get('/subscription/plans', subscriptionController.getSubscriptionPlans);
  router.get('/subscription/benefits', subscriptionController.getPremiumBenefits);
  router.get('/subscription/faqs', subscriptionController.getFaqs);

  // Authenticated subscription management
  router.get('/subscription/status', auth, subscriptionController.getSubscriptionStatus);
  router.get('/subscription/history', auth, subscriptionController.getSubscriptionHistory);
  router.put('/subscription/auto-renew', auth, subscriptionController.setAutoRenew);

  // Admin: subscription plans
  router.post('/admin/subscription-plans', auth, isAdmin, adminFeatureController.createSubscriptionPlan);
  router.get('/admin/subscription-plans', auth, isAdmin, adminFeatureController.getSubscriptionPlans);
  router.put('/admin/subscription-plans/:id', auth, isAdmin, adminFeatureController.updateSubscriptionPlan);
  router.delete('/admin/subscription-plans/:id', auth, isAdmin, adminFeatureController.deleteSubscriptionPlan);

  // Admin: manage user subscriptions
  router.get('/admin/subscriptions', auth, isAdmin, adminFeatureController.getAllSubscriptions);
  router.get('/admin/subscriptions/analytics', auth, isAdmin, adminFeatureController.getSubscriptionAnalytics);
  router.post('/admin/subscriptions/grant', auth, isAdmin, adminFeatureController.grantSubscription);
  router.put('/admin/subscriptions/:id', auth, isAdmin, adminFeatureController.updateUserSubscription);
  router.put('/admin/subscriptions/:id/deactivate', auth, isAdmin, adminFeatureController.deactivateUserSubscription);
  router.put('/admin/subscriptions/:id/reactivate', auth, isAdmin, adminFeatureController.reactivateUserSubscription);

  // Admin: premium benefits
  router.post('/admin/premium-benefits', auth, isAdmin, adminFeatureController.createPremiumBenefit);
  router.get('/admin/premium-benefits', auth, isAdmin, adminFeatureController.getPremiumBenefits);
  router.put('/admin/premium-benefits/:id', auth, isAdmin, adminFeatureController.updatePremiumBenefit);
  router.delete('/admin/premium-benefits/:id', auth, isAdmin, adminFeatureController.deletePremiumBenefit);

  // Admin: FAQs
  router.post('/admin/faqs', auth, isAdmin, adminFeatureController.createFaq);
  router.get('/admin/faqs', auth, isAdmin, adminFeatureController.getFaqs);
  router.put('/admin/faqs/:id', auth, isAdmin, adminFeatureController.updateFaq);
  router.delete('/admin/faqs/:id', auth, isAdmin, adminFeatureController.deleteFaq);
};
