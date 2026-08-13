const User = require('../models/user');
const Admin = require('../models/admin');
const Transaction = require('../models/transaction');
const GroupTransaction = require('../models/groupTransaction');
const WalletTransaction = require('../models/walletTransaction');
const Subscription = require('../models/subscription');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { sendAlternativeEmailOTP: sendEmail } = require('../utils/alternativeEmailOtp');
const { sendSetPasswordOTP: sendSetPasswordEmail } = require('../utils/setPasswordOtp');
const { sendChangePasswordOTP: sendChangePasswordEmail } = require('../utils/changePasswordOtp');
const { sendAccountDeletedEmail } = require('../utils/accountDeletedEmail');
const Notification = require('../models/notification');
const { sendToUser } = require('../services/notificationService');
const { handleRouteError } = require('../utils/apiError');

// Change Password
const changePassword = async (req, res) => {
  try {
    const { currentPassword, newPassword, forgotMode } = req.body;
    const userId = req.user._id;

    // Find user
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    if (forgotMode) {
      // Forgot-current-password path: identity must have been verified via OTP/PIN
      const v = user.changePasswordOTP;
      const isVerified = v?.verified === true
        && v?.verifiedAt
        && (new Date() - new Date(v.verifiedAt)) < 15 * 60 * 1000;
      if (!isVerified) {
        return res.status(400).json({ message: 'Identity not verified. Please verify via OTP or PIN first.' });
      }
    } else {
      // Normal path: verify current password
      if (!currentPassword) {
        return res.status(400).json({ message: 'Current password is required.' });
      }
      const isCurrentPasswordValid = await bcrypt.compare(currentPassword, user.password);
      if (!isCurrentPasswordValid) {
        return res.status(400).json({ message: 'Current password is incorrect' });
      }
    }

    // Password strength: min 8 chars, at least one letter and one digit
    if (!newPassword || newPassword.length < 8) {
      return res.status(400).json({ message: 'New password must be at least 8 characters' });
    }
    if (!/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
      return res.status(400).json({ message: 'New password must contain at least one letter and one number' });
    }

    // Check if new password is different from current
    const isNewPasswordSame = await bcrypt.compare(newPassword, user.password);
    if (isNewPasswordSame) {
      return res.status(400).json({ message: 'New password must be different from current password' });
    }

    // Hash new password
    const saltRounds = 10;
    const hashedNewPassword = await bcrypt.hash(newPassword, saltRounds);

    // Update password and invalidate all outstanding access tokens immediately
    user.password = hashedNewPassword;
    user.forceLogoutAfter = new Date();
    user.changePasswordOTP = undefined;
    await user.save();

    res.json({ message: 'Password changed successfully' });

    if (user.privacySettings?.loginNotifications !== false) {
      Notification.create({
        sender: userId, senderModel: 'User', recipientType: 'specific-users',
        recipients: [userId], recipientModel: 'User', category: 'system',
        message: "Your password was changed successfully. If this wasn't you, contact support immediately.",
      }).catch(() => {});
      sendToUser(User, userId, { title: 'Password Changed 🔐', body: "Your password was changed. If this wasn't you, contact support.", data: { type: 'security' } });
    }
  } catch (error) {
    console.error('Error changing password:', error);
    handleRouteError(res, error);
  }
};

// Alternative Email OTP Management
const sendAlternativeEmailOTP = async (req, res) => {
  try {
    const { altEmail } = req.body;
    const userId = req.user._id;

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(altEmail)) {
      return res.status(400).json({ message: 'Invalid email format' });
    }

    // Check if email is already used by another user
    const existingUser = await User.findOne({ email: altEmail });
    if (existingUser && existingUser._id.toString() !== userId) {
      return res.status(400).json({ message: 'Email is already in use' });
    }

    // Get user details
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    const now = new Date();
    const existing = user.altEmailOTP;

    // Enforce 60-second cooldown between sends
    if (existing?.sentAt && (now - existing.sentAt) < 60 * 1000) {
      const secondsLeft = Math.ceil((60 * 1000 - (now - existing.sentAt)) / 1000);
      return res.status(429).json({ message: `Please wait ${secondsLeft} seconds before requesting another OTP` });
    }

    // Enforce max 3 sends per hour (rolling 1-hour window)
    const hourAgo = new Date(now - 60 * 60 * 1000);
    const windowStart = existing?.windowStart && existing.windowStart > hourAgo ? existing.windowStart : now;
    const attemptCount = existing?.windowStart && existing.windowStart > hourAgo ? (existing.attemptCount || 0) : 0;
    if (attemptCount >= 3) {
      return res.status(429).json({ message: 'Too many OTP requests. Please try again in an hour.' });
    }

    // Generate 6-digit OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();

    // Store OTP with expiry (2 minutes)
    const otpExpiry = new Date(Date.now() + 2 * 60 * 1000); // 2 minutes

    user.altEmailOTP = {
      code: otp,
      email: altEmail,
      expiry: otpExpiry,
      sentAt: now,
      attemptCount: attemptCount + 1,
      windowStart,
    };
    await user.save();

    // Send OTP email using the utility function
    await sendEmail(altEmail, otp, user.name);

    res.json({ 
      message: 'OTP sent successfully to alternative email',
      email: altEmail
    });
  } catch (error) {
    console.error('Error sending alternative email OTP:', error);
    handleRouteError(res, error);
  }
};

const verifyAlternativeEmailOTP = async (req, res) => {
  try {
    const { altEmail, otp } = req.body;
    const userId = req.user._id;

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(altEmail)) {
      return res.status(400).json({ message: 'Invalid email format' });
    }

    // Get user
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Check if OTP exists and matches
    if (!user.altEmailOTP || 
        user.altEmailOTP.code !== otp || 
        user.altEmailOTP.email !== altEmail) {
      return res.status(400).json({ message: 'Invalid OTP' });
    }

    // Check if OTP is expired
    if (new Date() > user.altEmailOTP.expiry) {
      return res.status(400).json({ message: 'OTP has expired' });
    }

    // Update alternative email
    user.altEmail = altEmail;
    user.altEmailOTP = null; // Clear OTP after successful verification
    await user.save();

    res.json({
      message: 'Alternative email verified and updated successfully',
      altEmail: user.altEmail
    });

    if (user.privacySettings?.loginNotifications !== false) {
      Notification.create({
        sender: userId, senderModel: 'User', recipientType: 'specific-users',
        recipients: [userId], recipientModel: 'User', category: 'system',
        message: `Your alternative email was updated to ${altEmail}.`,
      }).catch(() => {});
    }
  } catch (error) {
    console.error('Error verifying alternative email OTP:', error);
    handleRouteError(res, error);
  }
};

// Alternative Email Management (Legacy - now requires OTP verification)
const updateAlternativeEmail = async (req, res) => {
  try {
    const { altEmail } = req.body;
    const userId = req.user._id;

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(altEmail)) {
      return res.status(400).json({ message: 'Invalid email format' });
    }

    // Check if email is already used by another user
    const existingUser = await User.findOne({ email: altEmail });
    if (existingUser && existingUser._id.toString() !== userId) {
      return res.status(400).json({ message: 'Email is already in use' });
    }

    // Update alternative email
    const user = await User.findByIdAndUpdate(
      userId,
      { altEmail },
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ 
      message: 'Alternative email updated successfully',
      altEmail: user.altEmail 
    });
  } catch (error) {
    console.error('Error updating alternative email:', error);
    handleRouteError(res, error);
  }
};

const removeAlternativeEmail = async (req, res) => {
  try {
    const userId = req.user._id;

    const user = await User.findByIdAndUpdate(
      userId,
      { altEmail: null },
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ message: 'Alternative email removed successfully' });
  } catch (error) {
    console.error('Error removing alternative email:', error);
    handleRouteError(res, error);
  }
};

// Notification Settings
const getNotificationSettings = async (req, res) => {
  try {
    const userId = req.user._id;

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Return default settings if not set
    const settings = {
      transactionNotifications: user.notificationSettings?.transactionNotifications ?? true,
      paymentReminders: user.notificationSettings?.paymentReminders ?? true,
      chatNotifications: user.notificationSettings?.chatNotifications ?? true,
      groupNotifications: user.notificationSettings?.groupNotifications ?? true,
      friendNotifications: user.notificationSettings?.friendNotifications ?? true,
      subscriptionNotifications: user.notificationSettings?.subscriptionNotifications ?? true,
      emailNotifications: user.notificationSettings?.emailNotifications ?? true,
      pushNotifications: user.notificationSettings?.pushNotifications ?? true,
      smsNotifications: user.notificationSettings?.smsNotifications ?? false,
      notificationSound: user.notificationSettings?.notificationSound ?? true,
      vibrationEnabled: user.notificationSettings?.vibrationEnabled ?? true,
      reminderFrequency: user.notificationSettings?.reminderFrequency ?? 'daily',
      quietHoursStart: user.notificationSettings?.quietHoursStart ?? '22:00',
      quietHoursEnd: user.notificationSettings?.quietHoursEnd ?? '08:00',
      quietHoursEnabled: user.notificationSettings?.quietHoursEnabled ?? false,
      displayNotificationCount: user.notificationSettings?.displayNotificationCount ?? true,
    };

    res.set('Cache-Control', 'private, max-age=300');
    res.json(settings);
  } catch (error) {
    console.error('Error getting notification settings:', error);
    handleRouteError(res, error);
  }
};

const updateNotificationSettings = async (req, res) => {
  try {
    const userId = req.user._id;
    const {
      transactionNotifications,
      paymentReminders,
      chatNotifications,
      groupNotifications,
      friendNotifications,
      subscriptionNotifications,
      emailNotifications,
      pushNotifications,
      smsNotifications,
      notificationSound,
      vibrationEnabled,
      reminderFrequency,
      quietHoursStart,
      quietHoursEnd,
      quietHoursEnabled,
      displayNotificationCount,
    } = req.body;

    const user = await User.findByIdAndUpdate(
      userId,
      {
        notificationSettings: {
          transactionNotifications,
          paymentReminders,
          chatNotifications,
          groupNotifications,
          friendNotifications,
          subscriptionNotifications,
          emailNotifications,
          pushNotifications,
          smsNotifications,
          notificationSound,
          vibrationEnabled,
          reminderFrequency,
          quietHoursStart,
          quietHoursEnd,
          quietHoursEnabled,
          displayNotificationCount,
        }
      },
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({ 
      message: 'Notification settings updated successfully',
      settings: user.notificationSettings 
    });
  } catch (error) {
    console.error('Error updating notification settings:', error);
    handleRouteError(res, error);
  }
};

// Privacy Settings
const getPrivacySettings = async (req, res) => {
  try {
    const userId = req.user._id;

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    // Return default settings if not set
    const settings = {
      profileVisibility: user.privacySettings?.profileVisibility ?? true,
      transactionHistory: user.privacySettings?.transactionHistory ?? true,
      contactSharing: user.privacySettings?.contactSharing ?? false,
      analyticsSharing: user.privacySettings?.analyticsSharing ?? true,
      marketingEmails: user.privacySettings?.marketingEmails ?? false,
      dataCollection: user.privacySettings?.dataCollection ?? true,
      twoFactorAuth: user.privacySettings?.twoFactorAuth ?? false,
      loginNotifications: user.privacySettings?.loginNotifications ?? true,
      deviceManagement: user.privacySettings?.deviceManagement ?? true,
      sessionTimeout: user.privacySettings?.sessionTimeout ?? 30,
    };

    res.json(settings);
  } catch (error) {
    console.error('Error getting privacy settings:', error);
    handleRouteError(res, error);
  }
};

const updatePrivacySettings = async (req, res) => {
  try {
    const userId = req.user._id;
    const {
      profileVisibility,
      transactionHistory,
      contactSharing,
      analyticsSharing,
      marketingEmails,
      dataCollection,
      twoFactorAuth,
      loginNotifications,
      deviceManagement,
      sessionTimeout,
    } = req.body;

    const updatePayload = {
      privacySettings: {
        profileVisibility,
        transactionHistory,
        contactSharing,
        analyticsSharing,
        marketingEmails,
        dataCollection,
        twoFactorAuth,
        loginNotifications,
        deviceManagement,
        ...(typeof sessionTimeout === 'number' && { sessionTimeout }),
      },
    };

    const user = await User.findByIdAndUpdate(userId, updatePayload, { new: true });
    if (!user) return res.status(404).json({ message: 'User not found' });

    res.json({ message: 'Privacy settings updated successfully' });
  } catch (error) {
    console.error('Error updating privacy settings:', error);
    handleRouteError(res, error);
  }
};

// Account Information
const updateAccountInformation = async (req, res) => {
  try {
    const userId = req.user._id;
    const { name, phone, address, gender, birthday } = req.body;

    if (!name || name.trim().length === 0) {
      return res.status(400).json({ message: 'Name is required' });
    }

    const updateData = {
      name: name.trim(),
      phone: phone?.trim() || '',
      address: address?.trim() || '',
      gender: gender || '',
      birthday: birthday || null,
    };

    const user = await User.findByIdAndUpdate(
      userId,
      updateData,
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({
      message: 'Account information updated successfully',
      user: {
        name: user.name,
        phone: user.phone,
        address: user.address,
        gender: user.gender,
        birthday: user.birthday,
        memberSince: user.memberSince,
      }
    });
  } catch (error) {
    console.error('Error updating account information:', error);
    handleRouteError(res, error);
  }
};

const deleteAccount = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    const userEmail = user.email;

    // 1. Check for uncleared transactions (as lender or borrower)
    // Transaction is uncleared if either userCleared or counterpartyCleared is false and remainingAmount > 0
    const unclearedTx = await Transaction.findOne({
      $and: [
        {
          $or: [
            { userEmail: userEmail },
            { counterpartyEmail: userEmail }
          ]
        },
        {
          $or: [
            { userCleared: false },
            { counterpartyCleared: false }
          ]
        },
        { remainingAmount: { $gt: 0 } }
      ]
    });

    if (unclearedTx) {
      let role = '';
      if (unclearedTx.userEmail === userEmail) role = unclearedTx.role; // 'lender' or 'borrower'
      if (unclearedTx.counterpartyEmail === userEmail) role = unclearedTx.role === 'lender' ? 'borrower' : 'lender';
      return res.status(400).json({
        message: `Cannot delete account. You still have an uncleared transaction as ${role}. Please clear all transactions before deleting your account.`
      });
    }

    // 2. Check for unsettled group splits
    // For each group, for each expense, for each split, if split.user matches userId and split.amount > 0 and not settled
    const groupTxs = await GroupTransaction.find({
      'expenses.split.user': userId
    });

    let unsettledSplit = false;
    let unsettledDetails = null;

    for (const group of groupTxs) {
      for (const expense of group.expenses || []) {
        for (const split of expense.split || []) {
          if (
            split.user.toString() === userId.toString() &&
            split.amount > 0 &&
            (!split.settled || split.settled === false)
          ) {
            unsettledSplit = true;
            unsettledDetails = {
              groupTitle: group.title,
              expenseDescription: expense.description,
              amount: split.amount
            };
            break;
          }
        }
        if (unsettledSplit) break;
      }
      if (unsettledSplit) break;
    }

    if (unsettledSplit) {
      return res.status(400).json({
        message: `Cannot delete account. You have unsettled group expenses (e.g., group: "${unsettledDetails.groupTitle}", expense: "${unsettledDetails.expenseDescription}", amount: ${unsettledDetails.amount}). Please settle all group splits before deleting your account.`
      });
    }

    // Passed all checks, mark user as deactivated and revoke all tokens immediately
    user.deactivatedAccount = true;
    user.isActive = false;
    user.forceLogoutAfter = new Date();
    user.devices = [];
    await user.save();

    const TokenService = require('../utils/tokenService');
    await TokenService.revokeAllUserTokens(user._id, 'user');

    // Send account deactivated email
    try {
      await sendAccountDeletedEmail({
        to: userEmail,
        name: user.name || user.username || 'User',
        deactivated: true
      });
    } catch (e) {
      console.error('Failed to send account deactivated email:', e);
    }

    res.json({ message: 'Account deactivated successfully.' });
  } catch (error) {
    console.error('Error deactivating account:', error);
    handleRouteError(res, error);
  }
};


const exportUserData = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId)
      .select('-password -refreshTokens -altEmailOTP -devices')
      .lean();
    if (!user) return res.status(404).json({ message: 'User not found' });

    const [txCount, walletCount, subCount] = await Promise.all([
      Transaction.countDocuments({
        $or: [{ userEmail: user.email }, { counterpartyEmail: user.email }],
      }),
      WalletTransaction.countDocuments({ user: userId }),
      Subscription.countDocuments({ user: userId }),
    ]);

    res.json({
      exportedAt: new Date().toISOString(),
      summary: {
        name: user.name,
        email: user.email,
        altEmail: user.altEmail || null,
        memberSince: user.memberSince,
        walletBalance: user.walletBalance ?? 0,
        transactionCount: txCount,
        walletTransactionCount: walletCount,
        subscriptionCount: subCount,
      },
      note: 'For a full data export (including all records), please contact support via Help & Support. We will send a complete export to your registered email within 24 hours.',
    });
  } catch (error) {
    console.error('Error exporting user data:', error);
    handleRouteError(res, error);
  }
};

const getAdminNotificationSettings = async (req, res) => {
  try {
    const adminId = req.user._id;

    const admin = await Admin.findById(adminId);
    if (!admin) {
      return res.status(404).json({ message: 'Admin not found' });
    }

    const settings = {
      systemAlerts: admin.notificationSettings?.systemAlerts ?? true,
      maintenanceAlerts: admin.notificationSettings?.maintenanceAlerts ?? true,
      errorAlerts: admin.notificationSettings?.errorAlerts ?? true,
      performanceAlerts: admin.notificationSettings?.performanceAlerts ?? true,
      securityAlerts: admin.notificationSettings?.securityAlerts ?? true,
      backupAlerts: admin.notificationSettings?.backupAlerts ?? true,
      newUserAlerts: admin.notificationSettings?.newUserAlerts ?? true,
      suspiciousActivityAlerts: admin.notificationSettings?.suspiciousActivityAlerts ?? true,
      accountLockoutAlerts: admin.notificationSettings?.accountLockoutAlerts ?? true,
      failedLoginAlerts: admin.notificationSettings?.failedLoginAlerts ?? true,
      userDeletionAlerts: admin.notificationSettings?.userDeletionAlerts ?? true,
      bulkActionAlerts: admin.notificationSettings?.bulkActionAlerts ?? true,
      largeTransactionAlerts: admin.notificationSettings?.largeTransactionAlerts ?? true,
      failedTransactionAlerts: admin.notificationSettings?.failedTransactionAlerts ?? true,
      suspiciousTransactionAlerts: admin.notificationSettings?.suspiciousTransactionAlerts ?? true,
      dailyTransactionSummary: admin.notificationSettings?.dailyTransactionSummary ?? true,
      weeklyTransactionSummary: admin.notificationSettings?.weeklyTransactionSummary ?? true,
      monthlyTransactionSummary: admin.notificationSettings?.monthlyTransactionSummary ?? false,
      emailNotifications: admin.notificationSettings?.emailNotifications ?? true,
      pushNotifications: admin.notificationSettings?.pushNotifications ?? true,
      smsNotifications: admin.notificationSettings?.smsNotifications ?? false,
      inAppNotifications: admin.notificationSettings?.inAppNotifications ?? true,
      notificationFrequency: admin.notificationSettings?.notificationFrequency ?? 'immediate',
      quietHoursEnabled: admin.notificationSettings?.quietHoursEnabled ?? false,
      quietHoursStart: admin.notificationSettings?.quietHoursStart ?? '22:00',
      quietHoursEnd: admin.notificationSettings?.quietHoursEnd ?? '08:00',
      timezone: admin.notificationSettings?.timezone ?? 'UTC',
      displayNotificationCount: admin.notificationSettings?.displayNotificationCount ?? true,
    };

    res.json(settings);
  } catch (error) {
    console.error('Error getting admin notification settings:', error);
    handleRouteError(res, error);
  }
};

const updateAdminNotificationSettings = async (req, res) => {
  try {
    const adminId = req.user._id;
    const {
      systemAlerts,
      maintenanceAlerts,
      errorAlerts,
      performanceAlerts,
      securityAlerts,
      backupAlerts,
      newUserAlerts,
      suspiciousActivityAlerts,
      accountLockoutAlerts,
      failedLoginAlerts,
      userDeletionAlerts,
      bulkActionAlerts,
      largeTransactionAlerts,
      failedTransactionAlerts,
      suspiciousTransactionAlerts,
      dailyTransactionSummary,
      weeklyTransactionSummary,
      monthlyTransactionSummary,
      emailNotifications,
      pushNotifications,
      smsNotifications,
      inAppNotifications,
      notificationFrequency,
      quietHoursEnabled,
      quietHoursStart,
      quietHoursEnd,
      timezone,
      displayNotificationCount,
    } = req.body;

    const admin = await Admin.findByIdAndUpdate(
      adminId,
      {
        notificationSettings: {
          systemAlerts,
          maintenanceAlerts,
          errorAlerts,
          performanceAlerts,
          securityAlerts,
          backupAlerts,
          newUserAlerts,
          suspiciousActivityAlerts,
          accountLockoutAlerts,
          failedLoginAlerts,
          userDeletionAlerts,
          bulkActionAlerts,
          largeTransactionAlerts,
          failedTransactionAlerts,
          suspiciousTransactionAlerts,
          dailyTransactionSummary,
          weeklyTransactionSummary,
          monthlyTransactionSummary,
          emailNotifications,
          pushNotifications,
          smsNotifications,
          inAppNotifications,
          notificationFrequency,
          quietHoursEnabled,
          quietHoursStart,
          quietHoursEnd,
          timezone,
          displayNotificationCount,
        }
      },
      { new: true }
    );

    if (!admin) {
      return res.status(404).json({ message: 'Admin not found' });
    }

    res.json({ 
      message: 'Admin notification settings updated successfully',
      settings: admin.notificationSettings 
    });
  } catch (error) {
    console.error('Error updating admin notification settings:', error);
    handleRouteError(res, error);
  }
};

// Set Initial Password (Google-login users only) â€” Step 1: send OTP to primary email
const sendSetPasswordOtp = async (req, res) => {
  try {
    const userId = req.user._id;
    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: 'User not found' });

    if (user.authProvider !== 'google') {
      return res.status(400).json({ message: 'Use Change Password for your account type.' });
    }

    const now = new Date();
    const existing = user.setPasswordOTP;

    // 60-second cooldown between sends
    if (existing?.sentAt && (now - existing.sentAt) < 60 * 1000) {
      const secondsLeft = Math.ceil((60 * 1000 - (now - existing.sentAt)) / 1000);
      return res.status(429).json({ message: `Please wait ${secondsLeft} seconds before requesting another OTP.` });
    }

    // Max 3 sends per hour (rolling window)
    const hourAgo = new Date(now - 60 * 60 * 1000);
    const windowStart = existing?.windowStart && existing.windowStart > hourAgo ? existing.windowStart : now;
    const attemptCount = existing?.windowStart && existing.windowStart > hourAgo ? (existing.attemptCount || 0) : 0;
    if (attemptCount >= 3) {
      return res.status(429).json({ message: 'Too many OTP requests. Please try again in an hour.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const otpExpiry = new Date(Date.now() + 2 * 60 * 1000);

    user.setPasswordOTP = {
      code: otp,
      expiry: otpExpiry,
      sentAt: now,
      attemptCount: attemptCount + 1,
      windowStart,
    };
    await user.save();

    await sendSetPasswordEmail(user.email, otp, user.name);
    res.json({ message: 'OTP sent to your email.' });
  } catch (error) {
    console.error('Error sending set-password OTP:', error);
    handleRouteError(res, error);
  }
};

// Set Initial Password â€” Step 2a: verify OTP or PIN and mark identity verified
// The client calls this after OTP/PIN entry; on success the password fields unlock.
const verifySetPasswordIdentity = async (req, res) => {
  try {
    const { otp, pin } = req.body;
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ message: 'User not found' });
    if (user.authProvider !== 'google') {
      return res.status(400).json({ message: 'Use Change Password for your account type.' });
    }

    if (pin) {
      // PIN path
      if (!user.walletPin) {
        return res.status(400).json({ message: 'No transaction PIN is set on your account.' });
      }
      if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
        return res.status(423).json({ message: 'PIN is locked due to too many wrong attempts. Try again later.' });
      }
      const pinOk = await bcrypt.compare(String(pin), user.walletPin);
      if (!pinOk) {
        user.walletPinAttempts = (user.walletPinAttempts || 0) + 1;
        if (user.walletPinAttempts >= 5) {
          user.walletPinLockedUntil = new Date(Date.now() + 15 * 60 * 1000);
          user.walletPinAttempts = 0;
        }
        await user.save();
        return res.status(400).json({ message: 'Incorrect PIN.' });
      }
      user.walletPinAttempts = 0;
    } else {
      // OTP path
      const otpData = user.setPasswordOTP;
      if (!otpData?.code) return res.status(400).json({ message: 'No OTP pending. Please request one first.' });
      if (new Date() > new Date(otpData.expiry)) return res.status(400).json({ message: 'OTP has expired. Please request a new one.' });
      if (otpData.code !== String(otp)) return res.status(400).json({ message: 'Invalid OTP.' });
    }

    user.setPasswordOTP = {
      ...(user.setPasswordOTP?.toObject?.() || user.setPasswordOTP || {}),
      verified: true,
      verifiedAt: new Date(),
    };
    await user.save();
    res.json({ verified: true });
  } catch (error) {
    console.error('Error verifying set-password identity:', error);
    handleRouteError(res, error);
  }
};

// Set Initial Password â€” Step 2b: set the password (identity already verified above)
const confirmSetPassword = async (req, res) => {
  try {
    const { newPassword } = req.body;
    const userId = req.user._id;

    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ message: 'User not found' });

    if (user.authProvider !== 'google') {
      return res.status(400).json({ message: 'Use Change Password for your account type.' });
    }

    // Identity must have been verified within the last 15 minutes
    const verifiedAt = user.setPasswordOTP?.verifiedAt;
    const isVerified = user.setPasswordOTP?.verified === true
      && verifiedAt
      && (new Date() - new Date(verifiedAt)) < 15 * 60 * 1000;

    if (!isVerified) {
      return res.status(400).json({ message: 'Identity not verified. Please verify your email OTP or PIN first.' });
    }

    if (!newPassword || newPassword.length < 8 || newPassword.length > 30) {
      return res.status(400).json({ message: 'Password must be 8â€“30 characters.' });
    }
    if (!/[A-Za-z]/.test(newPassword) || !/[0-9]/.test(newPassword)) {
      return res.status(400).json({ message: 'Password must contain at least one letter and one number.' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    user.password = hashedPassword;
    user.setPasswordOTP = undefined;
    await user.save();

    res.json({ message: 'Password set successfully. You can now log in with your email and password.' });

    if (user.privacySettings?.loginNotifications !== false) {
      Notification.create({
        sender: userId, senderModel: 'User', recipientType: 'specific-users',
        recipients: [userId], recipientModel: 'User', category: 'system',
        message: "A password has been set for your LenDen account. If this wasn't you, contact support immediately.",
      }).catch(() => {});
      sendToUser(User, userId, { title: 'Password Changed 🔐', body: "Your password was changed. If this wasn't you, contact support.", data: { type: 'security' } });
    }
  } catch (error) {
    console.error('Error confirming set-password:', error);
    handleRouteError(res, error);
  }
};

// Change Password â€” Forgot flow Step 1: send OTP to user's primary email
const sendChangePasswordOtp = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ message: 'User not found' });

    const now = new Date();
    const existing = user.changePasswordOTP;

    if (existing?.sentAt && (now - existing.sentAt) < 60 * 1000) {
      const wait = Math.ceil((60 * 1000 - (now - existing.sentAt)) / 1000);
      return res.status(429).json({ message: `Please wait ${wait} seconds before requesting another OTP.` });
    }

    const hourAgo = new Date(now - 60 * 60 * 1000);
    const windowStart = existing?.windowStart && existing.windowStart > hourAgo ? existing.windowStart : now;
    const attemptCount = existing?.windowStart && existing.windowStart > hourAgo ? (existing.attemptCount || 0) : 0;
    if (attemptCount >= 5) {
      return res.status(429).json({ message: 'Too many OTP requests. Please try again later.' });
    }

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    user.changePasswordOTP = {
      code: otp,
      expiry: new Date(Date.now() + 2 * 60 * 1000),
      sentAt: now,
      attemptCount: attemptCount + 1,
      windowStart,
      verified: false,
    };
    await user.save();

    await sendChangePasswordEmail(user.email, otp, user.name);
    res.json({ message: 'OTP sent to your email.' });
  } catch (error) {
    console.error('Error sending change-password OTP:', error);
    handleRouteError(res, error);
  }
};

// Change Password â€” Forgot flow Step 2: verify OTP or PIN
const verifyChangePasswordIdentity = async (req, res) => {
  try {
    const { otp, pin } = req.body;
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ message: 'User not found' });

    if (pin) {
      if (!user.walletPin) {
        return res.status(400).json({ message: 'No transaction PIN is set on your account.' });
      }
      if (user.walletPinLockedUntil && user.walletPinLockedUntil > new Date()) {
        return res.status(423).json({ message: 'PIN is locked due to too many wrong attempts. Try again later.' });
      }
      const pinOk = await bcrypt.compare(String(pin), user.walletPin);
      if (!pinOk) {
        user.walletPinAttempts = (user.walletPinAttempts || 0) + 1;
        if (user.walletPinAttempts >= 5) {
          user.walletPinLockedUntil = new Date(Date.now() + 15 * 60 * 1000);
          user.walletPinAttempts = 0;
        }
        await user.save();
        return res.status(400).json({ message: 'Incorrect PIN.' });
      }
      user.walletPinAttempts = 0;
    } else {
      const otpData = user.changePasswordOTP;
      if (!otpData?.code) return res.status(400).json({ message: 'No OTP pending. Please request one first.' });
      if (new Date() > new Date(otpData.expiry)) return res.status(400).json({ message: 'OTP has expired. Please request a new one.' });
      if (otpData.code !== String(otp)) return res.status(400).json({ message: 'Invalid OTP.' });
    }

    user.changePasswordOTP = {
      ...(user.changePasswordOTP?.toObject?.() || user.changePasswordOTP || {}),
      verified: true,
      verifiedAt: new Date(),
    };
    await user.save();
    res.json({ verified: true });
  } catch (error) {
    console.error('Error verifying change-password identity:', error);
    handleRouteError(res, error);
  }
};

module.exports = {
  exportUserData,
  changePassword,
  sendAlternativeEmailOTP,
  verifyAlternativeEmailOTP,
  updateAlternativeEmail,
  removeAlternativeEmail,
  getNotificationSettings,
  updateNotificationSettings,
  getPrivacySettings,
  updatePrivacySettings,
  updateAccountInformation,
  deleteAccount,
  getAdminNotificationSettings,
  updateAdminNotificationSettings,
  sendSetPasswordOtp,
  verifySetPasswordIdentity,
  confirmSetPassword,
  sendChangePasswordOtp,
  verifyChangePasswordIdentity,
};
