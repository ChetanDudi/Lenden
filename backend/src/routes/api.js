const express = require('express');
const router = express.Router();

module.exports = (io) => {
  const AppratingController = require('../controllers/AppratingController');
  const feedbackController = require('../controllers/feedbackController');
  const userController = require('../controllers/userController');
  const quickTransactionController = require('../controllers/quickTransactionController');
  const adminController = require('../controllers/adminController');
  const adminTransactionController = require('../controllers/adminTransactionController');
  const forgotPasswordController = require('../controllers/forgotPasswordController');
  const profileController = require('../controllers/profileController');
  const editProfileController = require('../controllers/editProfileController');
  const auth = require('../middleware/auth');
  const sessionTimeout = require('../middleware/sessionTimeout');
  const fs = require('fs');
  const multer = require('multer');
  const os = require('os');
  const upload = multer({
    limits: { fileSize: 10 * 1024 * 1024 } // 10 MB per file (industry standard for images/PDFs)
  });
  const adUploadStorage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, os.tmpdir()),
    filename: (_req, file, cb) => {
      const safeName = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
      cb(
        null,
        `ad-${Date.now()}-${Math.round(Math.random() * 1e9)}-${safeName}`
      );
    },
  });
  const adUpload = multer({
    storage: adUploadStorage,
    limits: { fileSize: 150 * 1024 * 1024 },
  });
  const handleAdUpload = (req, res, next) => {
    adUpload.single('media')(req, res, (error) => {
      const cleanupTempFile = () => {
        if (req.file?.path) {
          fs.promises.unlink(req.file.path).catch(() => {});
        }
      };

      if (!error) return next();

      if (error instanceof multer.MulterError) {
        cleanupTempFile();
        if (error.code === 'LIMIT_FILE_SIZE') {
          return res.status(400).json({
            error: 'Ad media file is too large. Please upload a file smaller than 150 MB.',
          });
        }

        return res.status(400).json({
          error: error.message || 'Failed to process ad media upload.',
        });
      }

      console.error('Ad upload middleware failed:', error);
      cleanupTempFile();
      return res.status(400).json({
        error: error?.message || 'Failed to process ad media upload.',
      });
    });
  };
  const transactionController = require('../controllers/transactionController');
  const analyticController = require('../controllers/analyticController');
  const counterpartyController = require('../controllers/counterpartyController');
  const limitsController = require('../controllers/limitsController');
  const noteController = require('../controllers/noteController');
  const groupTransactionController = require('../controllers/groupTransactionController');
  const activityController = require('../controllers/activityController');
  const settingsController = require('../controllers/settingsController');
  const userActivityController = require('../controllers/userActivityController');
  const supportController = require('../controllers/supportController')(io);
  const ratingController = require('../controllers/ratingController');
  const notificationController = require('../controllers/notificationController');
  const chatController = require('../controllers/chatController')(io);
  const groupChatController = require('../controllers/groupChatController')(io);
  const subscriptionController = require('../controllers/subscriptionController');
  const paymentController = require('../controllers/paymentController');
  const adminFeatureController = require('../controllers/adminFeatureController');
  const giftCardController = require('../controllers/giftCardController');
  const friendController = require('../controllers/friendController');
  const leaderboardController = require('../controllers/leaderboardController');
  const referralController = require('../controllers/referralController');
  const offerController = require('../controllers/offerController');
  const contactConfigController = require('../controllers/contactConfigController');
  const coinLedgerController = require('../controllers/coinLedgerController');
  const appContentController = require('../controllers/appContentController');
  const currencyConversionController = require('../controllers/currencyConversionController');
  const handleUsage = require('../middleware/handleUsage');

  // Middleware to check for admin role
  const isAdmin = (req, res, next) => {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ error: 'Access denied. Admins only.' });
    }
    next();
  };

  // App rating routes
  router.post('/rating', auth, AppratingController.submitRating);
  router.get('/rating/my', auth, AppratingController.getMyRating);
    // User rating routes (for RatingsPage)
    router.get('/ratings/me', auth, ratingController.getMyRatings);
    router.post('/ratings', auth, ratingController.rateUser);
    router.patch('/ratings/:ratingId', auth, ratingController.updateRating);
    router.get('/ratings/user-avg', ratingController.getUserAvgRating);

  // User routes
  router.post('/users/register', userController.register);
  router.post('/users/verify-otp', userController.verifyOtp);
  router.post('/users/resend-otp', userController.resendOtp);
  router.post('/users/login', userController.login);
  router.post('/users/check-username', userController.checkUsername);
  router.post('/users/check-email', userController.checkEmail);
  router.get('/users/list', userController.listUsers); // Debug endpoint
  router.post('/users/send-login-otp', userController.sendLoginOtp);
  router.post('/users/verify-login-otp', userController.verifyLoginOtp);
  router.post('/users/login-with-otp', userController.verifyLoginOtp);
  router.post('/users/send-reset-otp', forgotPasswordController.sendResetOtp);
  router.post('/users/verify-reset-otp', forgotPasswordController.verifyResetOtp);
  router.post('/users/reset-password', forgotPasswordController.resetPassword);
  router.post('/users/recover-account', userController.recoverAccount);
  
  // Token management routes
  router.post('/users/refresh-token', userController.refreshToken);
  router.post('/users/logout', userController.logout);
  router.post('/users/logout-all-devices', userController.logoutAllDevices);
  router.get('/users/active-sessions', userController.getActiveSessions);
  
  // All authenticated user routes should use sessionTimeout after auth
  router.get('/users/me', auth, sessionTimeout, profileController.getUserProfile);
  router.post('/users/daily-login-reward', auth, sessionTimeout, userController.applyDailyLoginRewardOnAppOpen);
  router.get('/users/freebie-counts', auth, userController.getFreebieCounts);
  router.put('/users/me', auth, sessionTimeout, upload.single('profileImage'), editProfileController.updateUserProfile);
  router.put('/users/me/chat-public-key', auth, sessionTimeout, userController.updateChatEncryptionPublicKey);
  // Serve user profile image
  router.get('/users/:id/profile-image', profileController.getUserProfileImage);
  router.get('/users/profile-by-email', profileController.getUserProfileByEmail);
  router.get('/users/devices', auth, sessionTimeout, userController.listDevices);
  router.post('/users/logout-device', auth, sessionTimeout, userController.logoutDevice);
  router.get('/users/:id', auth, userController.getUserById);

  // Friends routes
  router.get('/friends', auth, friendController.getFriends);
  router.get('/friends/search', auth, friendController.searchUsers);
  router.get('/friends/suggestions', auth, friendController.getFriendSuggestions);
  router.get('/friends/mutual', auth, friendController.getMutualFriends);
  router.post('/friends/mutual-counts', auth, friendController.getMutualFriendCounts);
  router.get('/friends/requests', auth, friendController.getFriendRequests);
  router.post('/friends/request', auth, friendController.sendFriendRequest);
  router.post('/friends/add', auth, friendController.sendFriendRequest);
  router.post('/friends/requests/:requestId/accept', auth, friendController.acceptFriendRequest);
  router.post('/friends/requests/:requestId/decline', auth, friendController.declineFriendRequest);
  router.post('/friends/requests/:requestId/cancel', auth, friendController.cancelFriendRequest);
  router.post('/friends/block', auth, friendController.blockUser);
  router.post('/friends/unblock', auth, friendController.unblockUser);
  router.delete('/friends/:friendId', auth, friendController.removeFriend);

  // Quick Transaction routes
  router.get('/quick-transactions', auth, quickTransactionController.getQuickTransactions);
  router.put('/quick-transactions/:id/favourite', auth, quickTransactionController.toggleQuickTransactionFavourite);
  router.post('/quick-transactions', auth, handleUsage('quickTransaction'), quickTransactionController.createQuickTransaction);
  router.post('/quick-transactions/with-coins', auth, quickTransactionController.createQuickTransactionWithCoins);
  router.put('/quick-transactions/:id', auth, quickTransactionController.updateQuickTransaction);
  router.delete('/quick-transactions/:id', auth, quickTransactionController.deleteQuickTransaction);
  router.put('/quick-transactions/:id/clear', auth, quickTransactionController.clearQuickTransaction);
  router.post('/quick-transactions/:id/request-settlement', auth, quickTransactionController.requestQuickTransactionSettlement);
  router.post('/quick-transactions/:id/respond-settlement', auth, quickTransactionController.respondQuickTransactionSettlement);
  router.delete('/quick-transactions', auth, quickTransactionController.clearAllQuickTransactions);

  // Support routes (User)
  router.get('/contact-info', contactConfigController.getPublicContactConfig);
  router.post('/support/queries', auth, supportController.createSupportQuery);
  router.get('/support/queries/me', auth, supportController.getUserSupportQueries);
  router.put('/support/queries/:queryId', auth, supportController.updateSupportQuery);
  router.delete('/support/queries/:queryId', auth, supportController.deleteSupportQuery);

  // Admin routes (only register, login is now unified)
  router.post('/admins/register', adminController.register);
  // Test endpoint to create a simple admin (for testing only)
  router.post('/admins/create-test', async (req, res) => {
    try {
      const Admin = require('../models/admin');
      const bcrypt = require('bcryptjs');
      
      // Check if test admin already exists
      const existingAdmin = await Admin.findOne({ email: 'admin@test.com' });
      if (existingAdmin) {
        return res.json({
          success: true,
          message: 'Test admin already exists',
          admin: {
            email: 'admin@test.com',
            username: 'admin',
            password: 'Admin123!'
          }
        });
      }
      
      // Create test admin
      const hashedPassword = await bcrypt.hash('Admin123!', 10);
      const admin = new Admin({
        name: 'Test Admin',
        username: 'admin',
        email: 'admin@test.com',
        password: hashedPassword,
        gender: 'Other'
      });
      
      await admin.save();
      
      res.json({
        success: true,
        message: 'Test admin created successfully',
        admin: {
          email: 'admin@test.com',
          username: 'admin',
          password: 'Admin123!'
        }
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        message: 'Failed to create test admin',
        error: error.message
      });
    }
  });
  router.get('/admins/me', auth, profileController.getAdminProfile);
  router.put('/admins/me', auth, upload.single('profileImage'), editProfileController.updateAdminProfile);
  // Serve admin profile image
  router.get('/admins/:id/profile-image', profileController.getAdminProfileImage);

  // Transaction routes
  router.post('/transactions/create', auth, handleUsage('userTransaction'), upload.array('files'), transactionController.createTransaction);
  router.post('/transactions/with-coins', auth, upload.array('files'), transactionController.createTransactionWithCoins);
  router.post('/transactions/check-email', transactionController.checkEmailExists);
  router.post('/transactions/send-counterparty-otp', transactionController.sendCounterpartyOTP);
  router.post('/transactions/verify-counterparty-otp', transactionController.verifyCounterpartyOTP);
  router.post('/transactions/send-user-otp', transactionController.sendUserOTP);
  router.post('/transactions/verify-user-otp', transactionController.verifyUserOTP);
  router.post('/transactions/clear', transactionController.clearTransaction);
  router.delete('/transactions/delete', transactionController.deleteTransaction);
  router.post('/transactions/:transactionId/receipt', auth, transactionController.generateReceipt);
  router.put('/transactions/:transactionId/favourite', auth, transactionController.toggleFavourite);

  router.get('/transactions/user', transactionController.getUserTransactions);

  // Partial payment routes
  router.post('/transactions/send-partial-payment-otp', transactionController.sendPartialPaymentOTP);
  router.post('/transactions/verify-partial-payment-otp', transactionController.verifyPartialPaymentOTP);
  router.post('/transactions/partial-payment', transactionController.processPartialPayment);
  router.get('/transactions/:transactionId', transactionController.getTransactionDetails);


  // Analytics routes
  router.get('/analytics/user', analyticController.getUserAnalytics);
  router.get('/analytics/secure', analyticController.getUserAnalytics);
  router.get('/analytics/quick', analyticController.getQuickAnalytics);
  router.get('/analytics/group', analyticController.getGroupAnalytics);
  router.get('/analytics/groups', analyticController.getGroupAnalytics);
  router.get('/currency-conversions/supported', auth, currencyConversionController.getSupportedCurrencies);
  router.get('/currency-conversions/matrix', auth, currencyConversionController.getPublicCurrencyMatrix);
  // Counterparty routes
  router.get('/counterparties/user', auth, counterpartyController.getUserCounterparties);
  router.get('/counterparties/stats', auth, counterpartyController.getCounterpartyStats);
  router.post('/counterparties/stats-batch', auth, counterpartyController.getCounterpartyStatsBatch);

  // Daily limits routes
  router.get('/limits/daily', auth, limitsController.getDailyLimits);
  router.get('/limits/transaction/:transactionId/messages', auth, limitsController.getTransactionMessageLimit);
  router.get('/limits/group/:groupId/messages', auth, limitsController.getGroupMessageLimit);
  router.get('/limits/group/:groupId/expenses', auth, limitsController.getGroupExpenseLimit);

  // Leaderboard routes
  router.get('/leaderboard', auth, leaderboardController.getDailyLeaderboard);
  router.get('/leaderboard/rewards/me', auth, leaderboardController.getMyMonthlyRewardSummary);

  // Referral routes
  router.get('/referral/me', auth, referralController.getReferralInfo);
  router.get('/coins/history', auth, coinLedgerController.getMyCoinHistory);
  router.get('/app-updates', auth, appContentController.listUpdates);
  router.post('/app-updates/:updateId/read', auth, appContentController.markUpdateRead);
  router.post('/app-updates/read-all', auth, appContentController.markAllUpdatesRead);
  router.get('/ads/random', auth, appContentController.getRandomActiveAd);
  router.post('/ads/:adId/events', auth, appContentController.trackAdEvent);
  router.get('/ads/media/:fileId', appContentController.streamAdMedia);
  router.post('/referral/share', auth, referralController.logReferralShare);
  router.get('/admin/referral-config', auth, isAdmin, referralController.getReferralConfigForAdmin);
  router.put('/admin/referral-config', auth, isAdmin, referralController.updateReferralConfigForAdmin);

  // Offer routes (User)
  router.get('/offers/available', auth, offerController.getAvailableOffers);
  router.post('/offers/:offerId/accept', auth, offerController.acceptOffer);
  router.get('/offers/my-claims', auth, offerController.getMyOfferClaims);

  // Offer routes (Admin)
  router.post('/admin/offers', auth, isAdmin, offerController.createOffer);
  router.get('/admin/offers', auth, isAdmin, offerController.getAdminOffers);
  router.get('/admin/offers/users', auth, isAdmin, offerController.searchUsersForOffers);
  router.get('/admin/offers/:offerId/analytics', auth, isAdmin, offerController.getOfferAnalytics);
  router.get('/admin/offers/:offerId/claims', auth, isAdmin, offerController.getOfferClaimsAudit);
  router.put('/admin/offers/:offerId', auth, isAdmin, offerController.updateOffer);
  router.delete('/admin/offers/:offerId', auth, isAdmin, offerController.deleteOffer);
  router.get('/admin/content-analytics', auth, isAdmin, appContentController.getAdminContentAnalytics);
  router.post('/admin/app-updates', auth, isAdmin, appContentController.createUpdate);
  router.put('/admin/app-updates/:updateId', auth, isAdmin, appContentController.updateUpdate);
  router.delete('/admin/app-updates/:updateId', auth, isAdmin, appContentController.deleteUpdate);
  router.get('/admin/ads', auth, isAdmin, appContentController.listAdminAds);
  router.post('/admin/ads', auth, isAdmin, handleAdUpload, appContentController.createAd);
  router.put('/admin/ads/:adId', auth, isAdmin, handleAdUpload, appContentController.updateAd);
  router.patch('/admin/ads/:adId', auth, isAdmin, appContentController.toggleAd);
  router.delete('/admin/ads/:adId', auth, isAdmin, appContentController.deleteAd);

  // Notes routes
  router.post('/notes', auth, noteController.createNote);
  router.get('/notes', auth, noteController.getNotes);
  router.put('/notes/:id', auth, noteController.updateNote);
  router.delete('/notes/:id', auth, noteController.deleteNote);

  // Group Transaction routes
  router.post('/group-transactions', auth, handleUsage('group'), groupTransactionController.createGroup);
  router.post('/group-transactions/with-coins', auth, groupTransactionController.createGroupWithCoins);
  router.post('/group-transactions/:groupId/add-member', auth, groupTransactionController.addMember);
  router.post('/group-transactions/:groupId/remove-member', auth, groupTransactionController.removeMember);
  router.post('/group-transactions/:groupId/settle-member-expenses', auth, groupTransactionController.settleMemberExpenses);
  router.post('/group-transactions/:groupId/self-settle', auth, groupTransactionController.selfSettleExpenses);
  router.post('/group-transactions/:groupId/record-payment', auth, groupTransactionController.recordMemberPayment);
  router.post('/group-transactions/:groupId/add-expense', auth, groupTransactionController.addExpense);
  router.put('/group-transactions/:groupId/expenses/:expenseId', auth, groupTransactionController.editExpense);
  router.delete('/group-transactions/:groupId/expenses/:expenseId', auth, groupTransactionController.deleteExpense);
  router.post('/group-transactions/:groupId/expenses/:expenseId/settle', auth, groupTransactionController.settleExpenseSplits);
  router.post('/group-transactions/:groupId/request-leave', auth, groupTransactionController.requestLeave);
  router.post('/group-transactions/:groupId/settle-balance', auth, groupTransactionController.settleBalance);
  router.post('/group-transactions/:groupId/otp-verify-settle', auth, groupTransactionController.otpVerifySettle);
  // New: Get all groups for the logged-in user
  router.get('/group-transactions/user-groups', auth, groupTransactionController.getUserGroups);
  // New: Update group color
  router.put('/group-transactions/:groupId/color', auth, groupTransactionController.updateGroupColor);
  // New: Delete group (creator only)
  router.delete('/group-transactions/:groupId', auth, groupTransactionController.deleteGroup);
  // New: Leave group (members only)
  router.post('/group-transactions/:groupId/leave', auth, groupTransactionController.leaveGroup);
  // New: Send leave request to group creator
  router.post('/group-transactions/:groupId/send-leave-request', auth, groupTransactionController.sendLeaveRequest);
  router.put('/group-transactions/:groupId/favourite', auth, groupTransactionController.toggleGroupFavourite);

  // New: Generate group receipt
  router.post('/group-transactions/:groupId/receipt', auth, groupTransactionController.generateGroupReceipt);

  // Activity routes
  router.get('/activities', auth, activityController.getUserActivities);
  router.get('/activities/stats', auth, activityController.getActivityStats);
  router.delete('/activities/:activityId', auth, activityController.deleteActivity);
  router.patch('/activities/:activityId/bookmark', auth, activityController.bookmarkActivity);
  router.delete('/activities/cleanup', auth, activityController.cleanupOldActivities);

  // Settings routes
  // Change Password
  router.post('/users/change-password', auth, settingsController.changePassword);

  // Alternative Email
  router.post('/users/alternative-email/send-otp', auth, settingsController.sendAlternativeEmailOTP);
  router.post('/users/alternative-email/verify-otp', auth, settingsController.verifyAlternativeEmailOTP);
  router.put('/users/alternative-email', auth, settingsController.updateAlternativeEmail);
  router.delete('/users/alternative-email', auth, settingsController.removeAlternativeEmail);

  // Notification Settings
  router.get('/users/notification-settings', auth, settingsController.getNotificationSettings);
  router.put('/users/notification-settings', auth, settingsController.updateNotificationSettings);

  // Privacy Settings
  router.get('/users/privacy-settings', auth, sessionTimeout, settingsController.getPrivacySettings);
  router.put('/users/privacy-settings', auth, sessionTimeout, settingsController.updatePrivacySettings);

  // Account Information
  router.put('/users/account-information', auth, settingsController.updateAccountInformation);

  // Data Management
  router.delete('/users/delete-account', auth, sessionTimeout, settingsController.deleteAccount);

  // Admin routes
  // User Management
  router.get('/admin/dashboard-summary', auth, isAdmin, adminController.getDashboardSummary);
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

  // Transaction Management (Admin)
  router.get('/admin/transactions', auth, isAdmin, adminTransactionController.getAllTransactions);
  router.put('/admin/transactions/:transactionId', auth, isAdmin, upload.any(), adminTransactionController.updateTransaction);
  router.delete('/admin/transactions/:transactionId', auth, isAdmin, adminTransactionController.deleteTransaction);

  // Group Transaction Management (Admin)
  router.get('/admin/group-transactions', auth, isAdmin, adminController.getAllGroupTransactions);
  router.put('/admin/group-transactions/:groupId', auth, isAdmin, adminController.updateGroupTransaction);
  router.delete('/admin/group-transactions/:groupId', auth, isAdmin, adminController.deleteGroupTransaction);
  router.post('/admin/group-transactions/:groupId/members', auth, isAdmin, adminController.addMemberToGroup);
  router.delete('/admin/group-transactions/:groupId/members/:memberId', auth, isAdmin, adminController.removeMemberFromGroup);
  router.post('/admin/group-transactions/:groupId/expenses', auth, isAdmin, adminController.addExpenseToGroup);
  router.put('/admin/group-transactions/:groupId/expenses/:expenseId', auth, isAdmin, adminController.updateExpenseInGroup);
  router.delete('/admin/group-transactions/:groupId/expenses/:expenseId', auth, isAdmin, adminController.deleteExpenseFromGroup);
  router.post('/admin/group-transactions/:groupId/expenses/:expenseId/settle', auth, isAdmin, adminController.settleExpenseSplitsInGroup);

  // Admin Management routes
  router.get('/admin/admins', auth, isAdmin, adminController.getAllAdmins); // This route now supports ?search=query
  router.get('/admin/audit-logs', auth, isAdmin, adminController.getAdminAuditLogs);
  router.post('/admin/admins', auth, isAdmin, adminController.addAdmin);
  router.delete('/admin/admins/:adminId', auth, isAdmin, adminController.removeAdmin);
  router.patch('/admin/admins/:adminId/superadmin', auth, isAdmin, adminController.toggleSuperAdminStatus);
  router.patch('/admin/admins/:adminId/permissions', auth, isAdmin, adminController.updateAdminPermissions);

  // System Settings
  router.get('/admin/system-settings', auth, isAdmin, adminController.getSystemSettings);
  router.put('/admin/system-settings', auth, isAdmin, adminController.updateSystemSettings);

  // Analytics Settings
  router.get('/admin/analytics-settings', auth, isAdmin, adminController.getAnalyticsSettings);
  router.put('/admin/analytics-settings', auth, isAdmin, adminController.updateAnalyticsSettings);

  // Security Settings
  router.get('/admin/security-settings', auth, isAdmin, adminController.getSecuritySettings);
  router.put('/admin/security-settings', auth, isAdmin, adminController.updateSecuritySettings);

  // Currency Conversions
  router.get('/admin/currency-conversions', auth, isAdmin, currencyConversionController.getAdminCurrencyConversions);
  router.put('/admin/currency-conversions', auth, isAdmin, currencyConversionController.upsertAdminCurrencyConversion);
  router.post('/admin/currency-conversions/currencies', auth, isAdmin, currencyConversionController.addSupportedCurrency);

  // Notification Settings
  router.get('/admin/notification-settings', auth, isAdmin, settingsController.getAdminNotificationSettings);
  router.put('/admin/notification-settings', auth, isAdmin, settingsController.updateAdminNotificationSettings);

  // User Activity
  router.get('/admin/user-activity/:searchTerm', auth, isAdmin, userActivityController.getUserActivity);

  // Support routes (Admin)
  router.get('/admin/support/queries', auth, isAdmin, supportController.getAllSupportQueries);
  router.get('/admin/support/queries/export', auth, isAdmin, supportController.exportSupportQueries);
  router.post('/admin/support/queries/:queryId/reply', auth, isAdmin, supportController.replyToSupportQuery);
  router.put('/admin/support/queries/:queryId/replies/:replyId', auth, isAdmin, supportController.editReply);
  router.delete('/admin/support/queries/:queryId/replies/:replyId', auth, isAdmin, supportController.deleteReply);
  router.patch('/admin/support/queries/:queryId/status', auth, isAdmin, supportController.updateQueryStatus);
  router.patch('/admin/support/queries/:queryId/workflow', auth, isAdmin, supportController.updateQueryWorkflow);
  router.get('/admin/contact-info', auth, isAdmin, contactConfigController.getAdminContactConfig);
  router.put('/admin/contact-info', auth, isAdmin, contactConfigController.updateAdminContactConfig);

  // Feedback routes
  router.post('/feedback', auth, feedbackController.submitFeedback);
  router.get('/feedback/my', auth, feedbackController.getUserFeedbacks);
  router.get('/feedback/app-ratings', AppratingController.getAppRatings);
  router.get('/rating/all', auth, isAdmin, AppratingController.getAllRatings);
  router.get('/feedbacks/all', auth, isAdmin, feedbackController.getAllFeedbacks);

  // Notification routes
  router.post('/notifications', auth, isAdmin, notificationController.createNotification);
  router.get('/notifications', auth, notificationController.getNotifications);
  router.get('/notifications/sent', auth, isAdmin, notificationController.getSentNotifications);
  router.get('/notifications/audience-preview', auth, isAdmin, notificationController.getAudiencePreview);
  router.get('/notifications/unread-count', auth, notificationController.getUnreadNotificationCount);
  router.post('/notifications/mark-as-read', auth, notificationController.markNotificationsAsRead);
  router.delete('/notifications/:id', auth, notificationController.deleteNotification);
  router.put('/notifications/:id', auth, notificationController.updateNotification);

  // Chat routes
  router.get('/chat/messages/:transactionId', auth, chatController.getMessages);

  // Group Chat routes
  router.get('/group-chat/messages/:groupTransactionId', auth, groupChatController.getGroupMessages);

  // Subscription routes (update is admin-only — normal users must go through /payment/verify)
  router.post('/subscription/update', auth, isAdmin, subscriptionController.updateSubscription);
  router.get('/subscription/status', auth, subscriptionController.getSubscriptionStatus);
  router.get('/subscription/history', auth, subscriptionController.getSubscriptionHistory);

  // Public subscription routes
  router.get('/subscription/plans', subscriptionController.getSubscriptionPlans);
  router.get('/subscription/benefits', subscriptionController.getPremiumBenefits);
  router.get('/subscription/faqs', subscriptionController.getFaqs);

  // Payment routes (Razorpay)
  router.post('/payment/create-order', auth, paymentController.createOrder);
  router.post('/payment/verify', auth, paymentController.verifyPayment);
  router.post('/payment/create-p2p-order', auth, paymentController.createP2POrder);
  router.post('/payment/verify-p2p', auth, paymentController.verifyP2PPayment);
  router.post('/payment/webhook', paymentController.razorpayWebhook); // no auth — Razorpay calls this

  // LenDen Wallet routes
  const walletController = require('../controllers/walletController');
  router.get('/wallet/balance', auth, walletController.getBalance);
  router.get('/wallet/history', auth, walletController.getHistory);
  router.post('/wallet/create-order', auth, walletController.createTopUpOrder);
  router.post('/wallet/verify', auth, walletController.verifyTopUp);
  router.post('/wallet/pay', auth, walletController.pay);
  router.post('/wallet/pay-subscription', auth, walletController.paySubscription);

  // Admin feature routes
  // Subscription Plans
  router.post('/admin/subscription-plans', auth, isAdmin, adminFeatureController.createSubscriptionPlan);
  router.get('/admin/subscription-plans', auth, isAdmin, adminFeatureController.getSubscriptionPlans);
  router.put('/admin/subscription-plans/:id', auth, isAdmin, adminFeatureController.updateSubscriptionPlan);
  router.delete('/admin/subscription-plans/:id', auth, isAdmin, adminFeatureController.deleteSubscriptionPlan);

  // Manage Subscriptions
  router.get('/admin/subscriptions', auth, isAdmin, adminFeatureController.getAllSubscriptions);
  router.put('/admin/subscriptions/:id', auth, isAdmin, adminFeatureController.updateUserSubscription);
  router.put('/admin/subscriptions/:id/deactivate', auth, isAdmin, adminFeatureController.deactivateUserSubscription);

  // Premium Benefits
  router.post('/admin/premium-benefits', auth, isAdmin, adminFeatureController.createPremiumBenefit);
  router.get('/admin/premium-benefits', auth, isAdmin, adminFeatureController.getPremiumBenefits);
  router.put('/admin/premium-benefits/:id', auth, isAdmin, adminFeatureController.updatePremiumBenefit);
  router.delete('/admin/premium-benefits/:id', auth, isAdmin, adminFeatureController.deletePremiumBenefit);

  // FAQs
  router.post('/admin/faqs', auth, isAdmin, adminFeatureController.createFaq);
  router.get('/admin/faqs', auth, isAdmin, adminFeatureController.getFaqs);
  router.put('/admin/faqs/:id', auth, isAdmin, adminFeatureController.updateFaq);
  router.delete('/admin/faqs/:id', auth, isAdmin, adminFeatureController.deleteFaq);

  // Gift Card Management (Admin)
  router.post('/admin/giftcards', auth, isAdmin, giftCardController.createGiftCard);
  router.get('/admin/giftcards', auth, isAdmin, giftCardController.getGiftCards);
  router.put('/admin/giftcards/:id', auth, isAdmin, giftCardController.updateGiftCard);
  router.delete('/admin/giftcards/:id', auth, isAdmin, giftCardController.deleteGiftCard);

  // Gift Card Management (User)
  const userGiftCardController = require('../controllers/userGiftCardController');
  router.get('/gift-cards/unscratched', auth, userGiftCardController.getUnscractchedGiftCards);
  router.get('/gift-cards/scratched', auth, userGiftCardController.getScratcedGiftCards);
  router.post('/gift-cards/:userGiftCardId/scratch', auth, userGiftCardController.scratchGiftCard);
  router.get('/gift-cards/counts', auth, userGiftCardController.getGiftCardCounts);

  return router;
};
