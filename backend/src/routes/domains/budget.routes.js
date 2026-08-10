module.exports = (router, { auth, isAdmin }) => {
  const budgetController = require('../../controllers/budgetController');
  const budgetMessageController = require('../../controllers/budgetMessageController');
  const personalBudgetController = require('../../controllers/personalBudgetController');
  const personalBudgetExpenseController = require('../../controllers/personalBudgetExpenseController');
  const savingsGoalController = require('../../controllers/savingsGoalController');
  const reportsController = require('../../controllers/reportsController');
  const insightsController = require('../../controllers/insightsController');
  const adminReportsController = require('../../controllers/adminReportsController');
  const adminBudgetController = require('../../controllers/adminBudgetController');
  const adminInsightsController = require('../../controllers/adminInsightsController');

  // Shared budget
  router.get('/budget/status', auth, budgetController.getBudgetStatus);
  router.get('/budget/history', auth, budgetController.getBudgetHistory);
  router.get('/budget/recommendations', auth, budgetController.getBudgetRecommendations);
  router.get('/budget/insights', auth, budgetController.getBudgetInsights);
  router.get('/budget/recurring', auth, budgetController.getRecurring);
  router.post('/budget/recurring', auth, budgetController.addRecurring);
  router.delete('/budget/recurring/:id', auth, budgetController.deleteRecurring);
  router.get('/budget/rollover-preview', auth, budgetController.getRolloverPreview);
  router.post('/budget/rollover', auth, budgetController.applyRollover);
  router.get('/budget/streak', auth, budgetController.getBudgetStreak);
  router.patch('/budget/group-limit', auth, budgetController.setGroupLimit);

  // Budget messages — before /:year/:month wildcard
  router.get('/budget/messages/unread-count', auth, budgetMessageController.getUnreadCount);
  router.put('/budget/messages/read-all', auth, budgetMessageController.markAllRead);
  router.put('/budget/messages/:id/read', auth, budgetMessageController.markRead);
  router.get('/budget/messages', auth, budgetMessageController.getBudgetMessages);
  router.delete('/budget/messages', auth, budgetMessageController.clearMessages);

  router.get('/budget/:year/:month', auth, budgetController.getBudget);
  router.post('/budget', auth, budgetController.setBudget);
  router.put('/budget/categories', auth, budgetController.setCategoryBudget);
  router.put('/budget/alerts', auth, budgetController.setAlertThresholds);

  // Personal budget
  router.get('/personal-budget/access', auth, personalBudgetController.getAccessStatus);
  router.get('/personal-budget/active', auth, personalBudgetController.getActive);
  router.get('/personal-budget/history', auth, personalBudgetController.getHistory);
  router.get('/personal-budget/predictions', auth, personalBudgetController.getPredictions);
  router.post('/personal-budget', auth, personalBudgetController.create);
  router.put('/personal-budget/:id', auth, personalBudgetController.update);
  router.delete('/personal-budget/:id', auth, personalBudgetController.remove);
  router.delete('/personal-budget/history/:id', auth, personalBudgetController.removeHistory);
  router.get('/personal-budget/:budgetId/expenses', auth, personalBudgetExpenseController.getExpenses);
  router.post('/personal-budget/:budgetId/expenses', auth, personalBudgetExpenseController.addExpense);
  router.put('/personal-budget/:budgetId/expenses/:expenseId', auth, personalBudgetExpenseController.updateExpense);
  router.delete('/personal-budget/:budgetId/expenses/:expenseId', auth, personalBudgetExpenseController.deleteExpense);

  // Savings goals
  router.get('/savings-goals', auth, savingsGoalController.getGoals);
  router.post('/savings-goals', auth, savingsGoalController.createGoal);
  router.put('/savings-goals/:id', auth, savingsGoalController.updateGoal);
  router.delete('/savings-goals/:id', auth, savingsGoalController.deleteGoal);
  router.post('/savings-goals/:id/add', auth, savingsGoalController.addSavings);

  // Reports & insights (user)
  router.get('/reports/summary', auth, reportsController.getReportSummary);
  router.get('/insights', auth, insightsController.getInsights);

  // Admin: reports
  router.get('/admin/reports/platform', auth, isAdmin, adminReportsController.getPlatformOverview);
  router.get('/admin/reports/top-users', auth, isAdmin, adminReportsController.getTopUsers);
  router.get('/admin/reports/category-trends', auth, isAdmin, adminReportsController.getCategoryTrends);
  router.get('/admin/reports/search-users', auth, isAdmin, adminReportsController.searchUsers);
  router.get('/admin/reports/user/:userId', auth, isAdmin, adminReportsController.getUserReport);

  // Admin: shared budget
  router.get('/admin/budget/overview', auth, isAdmin, adminBudgetController.getBudgetOverview);
  router.get('/admin/budget/users', auth, isAdmin, adminBudgetController.getBudgetUsers);
  router.get('/admin/budget/subscriptions', auth, isAdmin, adminBudgetController.getAllSubscriptions);
  router.get('/admin/budget/user/:userId', auth, isAdmin, adminBudgetController.getUserBudgetDetail);
  router.patch('/admin/budget/user/:userId/limits', auth, isAdmin, adminBudgetController.setUserBudgetLimits);

  // Admin: personal budget
  router.get('/admin/personal-budget/all-active', auth, isAdmin, adminBudgetController.getAllActivePersonalBudgets);
  router.get('/admin/personal-budget/all-history', auth, isAdmin, adminBudgetController.getAllPersonalBudgetHistory);
  router.get('/admin/personal-budget/:budgetId/expenses', auth, isAdmin, adminBudgetController.getAdminBudgetExpenses);
  router.get('/admin/personal-budget/users', auth, isAdmin, adminBudgetController.getPersonalBudgetUsers);
  router.get('/admin/personal-budget/user/:userId', auth, isAdmin, adminBudgetController.getPersonalBudgetUser);

  // Admin: insights
  router.get('/admin/insights/platform', auth, isAdmin, adminInsightsController.getPlatformInsights);
  router.get('/admin/insights/health-scores', auth, isAdmin, adminInsightsController.getHealthScores);
  router.get('/admin/insights/anomalies', auth, isAdmin, adminInsightsController.getAnomalies);
  router.get('/admin/insights/tips', auth, isAdmin, adminInsightsController.getTips);
  router.post('/admin/insights/tips', auth, isAdmin, adminInsightsController.createTip);
  router.patch('/admin/insights/tips/:id/toggle', auth, isAdmin, adminInsightsController.toggleTip);
  router.delete('/admin/insights/tips/:id', auth, isAdmin, adminInsightsController.deleteTip);
};
