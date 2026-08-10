module.exports = (router, { auth, sessionTimeout, loginLimiter, otpSendLimiter, otpVerifyLimiter, passwordResetLimiter, upload, isAdmin }) => {
  const userController = require('../../controllers/userController');
  const forgotPasswordController = require('../../controllers/forgotPasswordController');
  const profileController = require('../../controllers/profileController');
  const editProfileController = require('../../controllers/editProfileController');
  const settingsController = require('../../controllers/settingsController');
  const adminController = require('../../controllers/adminController');

  // Registration & login
  router.post('/users/register', userController.register);
  router.post('/users/verify-otp', otpVerifyLimiter, userController.verifyOtp);
  router.post('/users/resend-otp', otpSendLimiter, userController.resendOtp);
  router.post('/users/login', loginLimiter, userController.login);
  router.post('/users/google-login', userController.googleLogin);
  router.post('/users/check-username', userController.checkUsername);
  router.post('/users/check-email', userController.checkEmail);
  router.get('/users/list', auth, isAdmin, userController.listUsers);
  router.post('/users/send-login-otp', otpSendLimiter, userController.sendLoginOtp);
  router.post('/users/verify-login-otp', otpVerifyLimiter, userController.verifyLoginOtp);
  router.post('/users/login-with-otp', otpVerifyLimiter, userController.verifyLoginOtp);
  router.post('/users/recover-account', userController.recoverAccount);

  // Password reset (unauthenticated)
  router.post('/users/send-reset-otp', otpSendLimiter, forgotPasswordController.sendResetOtp);
  router.post('/users/verify-reset-otp', otpVerifyLimiter, forgotPasswordController.verifyResetOtp);
  router.post('/users/reset-password', passwordResetLimiter, forgotPasswordController.resetPassword);

  // Token & session management
  router.post('/users/refresh-token', userController.refreshToken);
  router.post('/users/fcm-token', auth, userController.saveFcmToken);
  router.post('/users/logout', userController.logout);
  router.post('/users/logout-all-devices', auth, userController.logoutAllDevices);
  router.get('/users/active-sessions', auth, userController.getActiveSessions);
  router.get('/users/devices', auth, sessionTimeout, userController.listDevices);
  router.post('/users/logout-device', auth, sessionTimeout, userController.logoutDevice);

  // Profile
  router.get('/users/me', auth, sessionTimeout, profileController.getUserProfile);
  router.post('/users/daily-login-reward', auth, sessionTimeout, userController.applyDailyLoginRewardOnAppOpen);
  router.get('/users/freebie-counts', auth, userController.getFreebieCounts);
  router.put('/users/me', auth, sessionTimeout, upload.single('profileImage'), editProfileController.updateUserProfile);
  router.put('/users/me/chat-public-key', auth, sessionTimeout, userController.updateChatEncryptionPublicKey);
  router.get('/users/:id/profile-image', profileController.getUserProfileImage);
  router.get('/users/profile-by-email', auth, profileController.getUserProfileByEmail);

  // Admin profile — rate-limit to prevent brute-forcing ADMIN_REGISTER_SECRET
  router.post('/admins/register', loginLimiter, adminController.register);
  router.get('/admins/me', auth, profileController.getAdminProfile);
  router.put('/admins/me', auth, upload.single('profileImage'), editProfileController.updateAdminProfile);
  router.get('/admins/:id/profile-image', profileController.getAdminProfileImage);

  // Settings: change/set password
  router.post('/users/change-password', auth, settingsController.changePassword);
  router.post('/users/set-password/send-otp', auth, otpSendLimiter, settingsController.sendSetPasswordOtp);
  router.post('/users/set-password/verify-identity', auth, otpVerifyLimiter, settingsController.verifySetPasswordIdentity);
  router.post('/users/set-password/confirm', auth, settingsController.confirmSetPassword);
  router.post('/users/change-password/send-otp', auth, otpSendLimiter, settingsController.sendChangePasswordOtp);
  router.post('/users/change-password/verify-identity', auth, otpVerifyLimiter, settingsController.verifyChangePasswordIdentity);

  // Settings: alternative email
  router.post('/users/alternative-email/send-otp', auth, otpSendLimiter, settingsController.sendAlternativeEmailOTP);
  router.post('/users/alternative-email/verify-otp', auth, otpVerifyLimiter, settingsController.verifyAlternativeEmailOTP);
  router.put('/users/alternative-email', auth, settingsController.updateAlternativeEmail);
  router.delete('/users/alternative-email', auth, settingsController.removeAlternativeEmail);

  // Settings: notification & privacy
  router.get('/users/notification-settings', auth, settingsController.getNotificationSettings);
  router.put('/users/notification-settings', auth, settingsController.updateNotificationSettings);
  router.get('/users/privacy-settings', auth, sessionTimeout, settingsController.getPrivacySettings);
  router.put('/users/privacy-settings', auth, sessionTimeout, settingsController.updatePrivacySettings);

  // Settings: account & data
  router.put('/users/account-information', auth, settingsController.updateAccountInformation);
  router.get('/users/export-data', auth, sessionTimeout, settingsController.exportUserData);
  router.delete('/users/delete-account', auth, sessionTimeout, settingsController.deleteAccount);

  // Wildcard — must be AFTER all specific /users/... routes
  router.get('/users/:id', auth, userController.getUserById);
};
