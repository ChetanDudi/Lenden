const User = require('../models/user');
const Note = require('../models/note');
const Admin = require('../models/admin');
const PendingRegistration = require('../models/pendingRegistration');
const bcrypt = require('bcrypt');
const { sendRegistrationOTP } = require('../utils/registrationemailotp');
const { sendLoginOTP } = require('../utils/loginsendotp');
const { sendLoginNotificationEmail } = require('../utils/loginNotificationEmail');
const jwt = require('jsonwebtoken');
const { logProfileActivity } = require('./activityController');
const { v4: uuidv4 } = require('uuid');
const TokenService = require('../utils/tokenService');
const {
  generateUniqueReferralCode,
} = require('../utils/referralService');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');
const { handleRouteError } = require('../utils/apiError');
const Notification = require('../models/notification');
const { getCoinPricing } = require('../utils/coinPricing');
const { sendToUser } = require('../services/notificationService');

const OTP_EXPIRY_MS = 2 * 60 * 1000; // 2 minutes

function isPasswordValid(password) {
  const lengthValid = password.length >= 8 && password.length <= 30;
  const hasUpper = /[A-Z]/.test(password);
  const hasLower = /[a-z]/.test(password);
  const hasSpecial = /[^A-Za-z0-9]/.test(password);
  return lengthValid && hasUpper && hasLower && hasSpecial;
}

function getUtcDateKey(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

async function applyDailyLoginReward(user) {
  const todayKey = getUtcDateKey();
  if (user.lastDailyLoginRewardDate === todayKey) {
    return { awarded: false, coinsAwarded: 0 };
  }

  const pricing = await getCoinPricing();
  const DAILY_LOGIN_COINS = pricing.dailyLoginReward;
  user.lenDenCoins = (user.lenDenCoins || 0) + DAILY_LOGIN_COINS;
  user.lastDailyLoginRewardDate = todayKey;
  user.lastDailyLoginRewardAt = new Date();
  return { awarded: true, coinsAwarded: DAILY_LOGIN_COINS };
}

async function recordDailyLoginRewardIfNeeded(user, dailyReward) {
  if (!dailyReward?.awarded) {
    return;
  }

  await recordCoinLedgerEntry({
    userId: user._id,
    direction: 'earned',
    coins: dailyReward.coinsAwarded,
    source: 'daily_login',
    title: 'Daily Login Reward',
    description: `Earned ${dailyReward.coinsAwarded} LenDen coin for logging in today.`,
    occurredAt: user.lastDailyLoginRewardAt || new Date(),
  });
}

function getLogoutActorFromAccessToken(req) {
  try {
    const authHeader = req.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) return null;

    const token = authHeader.slice(7).trim();
    if (!token) return null;

    if (!process.env.JWT_SECRET) return null;
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    if (decoded?.role !== 'user') return null;

    return {
      userId: decoded.userId || decoded._id || null,
      userType: decoded.role,
      deviceId: decoded.deviceId || null,
    };
  } catch (_error) {
    return null;
  }
}

// Register user with OTP
exports.register = async (req, res) => {
  try {
  let { name, username, email, password, gender, referralCode } = req.body;
    email = email.trim().toLowerCase();
    if (!name || !username || !email || !password || !gender || !['Male', 'Female', 'Other'].includes(gender)) {
      return res.status(400).json({ error: 'All fields including gender are required and must be valid.' });
    }
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({ error: 'Invalid email format.' });
    }
    
  // Rating validation removed
    
    // Check if email exists
    const emailExists = await User.findOne({ email }) || await Admin.findOne({ email });
    if (emailExists) {
      return res.status(409).json({ error: 'Email already registered. Please login.' });
    }

    // Check if username exists
    const usernameExists = await User.findOne({ username }) || await Admin.findOne({ username });
    if (usernameExists) {
      return res.status(409).json({ error: 'Username already exists' });
    }
    // Password constraints
    if (!isPasswordValid(password)) {
      return res.status(400).json({ error: 'Password must be 8-30 characters, include uppercase, lowercase, and special character.' });
    }
    // Generate OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    referralCode = referralCode ? referralCode.toString().trim().toUpperCase() : null;
    if (referralCode) {
      const referrer = await User.findOne({ referralCode }).select('_id');
      if (!referrer) {
        return res.status(400).json({ error: 'Invalid referral code.' });
      }
    }
    await PendingRegistration.findOneAndUpdate(
      { email },
      { otp, data: { name, username, password, email, gender, referralCode }, createdAt: new Date() },
      { upsert: true, new: true },
    );
    try {
      await sendRegistrationOTP(email, otp);
    } catch (emailErr) {
      console.error('[register] Email send failed after retries:', emailErr.message);
      await PendingRegistration.deleteOne({ email });
      return res.status(503).json({ error: 'Could not send OTP email. Please check your email address and try again.' });
    }
    res.status(200).json({ message: 'OTP sent to email' });
  } catch (err) {
    console.error('[register] Error:', err.message);
    if (err.name === 'MongoNetworkError' || err.name === 'MongoTimeoutError' || err.message?.includes('connect')) {
      return res.status(503).json({ error: 'Server is temporarily unavailable. Please try again in a moment.' });
    }
    res.status(400).json({ error: err.message });
  }
};

// Resend OTP
exports.resendOtp = async (req, res) => {
  try {
    const { email } = req.body;
    const entry = await PendingRegistration.findOne({ email });
    if (!entry) {
      return res.status(400).json({ error: 'No registration in progress for this email.' });
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    entry.otp = otp;
    entry.createdAt = new Date();
    await entry.save();
    try {
      await sendRegistrationOTP(email, otp);
    } catch (emailErr) {
      console.error('[resendOtp] Email send failed:', emailErr.message);
      return res.status(503).json({ error: 'Could not send OTP email. Please try again.' });
    }
    res.status(200).json({ message: 'New OTP sent to email' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Verify OTP and complete registration
exports.verifyOtp = async (req, res) => {
  try {
    const { email, otp } = req.body;
    const entry = await PendingRegistration.findOne({ email });
    if (!entry) {
      return res.status(400).json({ error: 'No OTP found for this email' });
    }
    const now = Date.now();
    if (now - entry.createdAt.getTime() > OTP_EXPIRY_MS) {
      await PendingRegistration.deleteOne({ email });
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    if (entry.otp !== otp) {
      return res.status(400).json({ error: 'Invalid OTP' });
    }
    // Register user
    const { name, username, password, gender, referralCode } = entry.data;
    const hashedPassword = await bcrypt.hash(password, 10);
    let referredByUser = null;
    if (referralCode) {
      const referrer = await User.findOne({ referralCode }).select('_id');
      if (referrer) referredByUser = referrer._id;
    }
    const uniqueReferralCode = await generateUniqueReferralCode();
    const newUser = new User({
      name,
      username,
      email,
      password: hashedPassword,
      gender,
      isVerified: true,
      referralCode: uniqueReferralCode,
      referredByUser,
      referredByCode: referralCode || null,
      memberSince: new Date(), // Set member since date
    });
    await newUser.save();
    await PendingRegistration.deleteOne({ email });
    res.status(201).json({ message: 'User registered successfully' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Login user or admin
exports.login = async (req, res) => {
  try {
    let { username, password } = req.body;
    
    if (username && username.includes('@')) username = username.trim().toLowerCase();
    
    // Search in both User and Admin tables
    const user = await User.findOne({ $or: [{ username }, { email: username }] });
    const admin = await Admin.findOne({ $or: [{ username }, { email: username }] });

    if (!user && !admin) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Check if it's a user
    if (user) {
      if (user.deactivatedAccount) {
        return res.status(403).json({
          error: 'This account has been deactivated. Would you like to recover it?',
          canRecover: true,
          email: user.email,
          username: user.username
        });
      }
      if (!user.password) {
        return res.status(400).json({
          error: 'This account was created with Google Sign-In. Please log in with Google, or use "Forgot Password" to set a password.',
          authProvider: 'google',
        });
      }
      const match = await bcrypt.compare(password, user.password);

      if (!match) {
        return res.status(401).json({ error: 'Incorrect password' });
      }

      // 2FA: send OTP and pause login if the user has twoFactorAuth enabled
      if (user.privacySettings?.twoFactorAuth === true) {
        const otp = Math.floor(100000 + Math.random() * 900000).toString();
        user.loginOTP = { code: otp, expiry: new Date(Date.now() + OTP_EXPIRY_MS), sentAt: new Date() };
        try {
          await sendLoginOTP(user.email, otp);
        } catch {
          return res.status(503).json({ error: 'Could not send 2FA OTP. Please try again.' });
        }
        await user.save();
        return res.status(202).json({ requires2FA: true, email: user.email });
      }

      // Generate tokens for user
      const deviceId = req.body.deviceId || uuidv4();
      const deviceName = req.body.deviceName || req.get('User-Agent');
      const ipAddress = req.ip;
      
      // Generate access token (short-lived)
      const accessToken = TokenService.generateAccessToken({
        _id: user._id,
        email: user.email,
        role: 'user',
        deviceId
      });

      // Generate refresh token (long-lived)
      const refreshToken = TokenService.generateRefreshToken();
      
      // Save refresh token to database
      await TokenService.saveRefreshToken({
        token: refreshToken,
        userId: user._id,
        userType: 'user',
        deviceId,
        deviceName,
        ipAddress,
        userAgent: req.get('User-Agent'),
        expiresAt: TokenService.calculateTokenExpiry()
      });

      
      // Log login activity
      try {
        await logProfileActivity(user._id, 'login', {
          ipAddress: req.ip,
          userAgent: req.get('User-Agent')
        });
      } catch (e) {
        console.error('Failed to log login activity:', e);
      }

      // Send login notification email + in-app security alert if enabled
      if (user.privacySettings?.loginNotifications !== false) {
        sendLoginNotificationEmail({
          to: user.email,
          name: user.name,
          ipAddress: req.ip,
          userAgent: req.get('User-Agent'),
          loginTime: new Date()
        }).catch(e => console.error('Failed to send login notification email:', e));

        Notification.create({
          sender: user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [user._id], recipientModel: 'User', category: 'system',
          title: 'New Login Detected 🔐',
          message: `New login to your account from ${req.ip || 'unknown location'}.`,
        }).catch((e) => console.error('Login notification failed:', e.message));
        sendToUser(User, user._id, { title: 'New Login Detected 🔐', body: `New login from ${req.ip || 'unknown'}.`, data: { type: 'security_login' } });
      }

      // Device management: enforce single-device login if needed
      if (user.deviceManagement === false) {
        if (user.devices && user.devices.length > 0 && user.devices[0].deviceId !== deviceId) {
          return res.status(409).json({ error: 'This account is already logged in on another device.' });
        }
        user.devices = [];
      }
      // Add/update this device
      const now = new Date();
      // Remove any existing entry for this deviceId
      user.devices = user.devices.filter(d => d.deviceId !== deviceId);
      user.devices.push({
        deviceId,
        userAgent: deviceName,
        ipAddress,
        lastActive: now,
        createdAt: now
      });
      const dailyReward = await applyDailyLoginReward(user);
      await user.save();
      await recordDailyLoginRewardIfNeeded(user, dailyReward);

      const userResponse = user.toObject();
      delete userResponse.password;

      res.json({
        message: 'Login successful',
        user: userResponse,
        accessToken,
        refreshToken,
        deviceId,
        dailyLoginReward: dailyReward,
      });
      return;
    }

    // Check if it's an admin
    if (admin) {
      const match = await bcrypt.compare(password, admin.password);
      
      if (!match) {
        return res.status(401).json({ error: 'Incorrect password' });
      }
      
      // Generate tokens for admin
      const deviceId = req.body.deviceId || uuidv4();
      const deviceName = req.body.deviceName || req.get('User-Agent');
      const ipAddress = req.ip;
      
      // Generate access token (short-lived)
      const accessToken = TokenService.generateAccessToken({
        _id: admin._id,
        userId: admin._id,
        email: admin.email,
        role: 'admin',
        deviceId,
        isSuperAdmin: admin.isSuperAdmin === true,
      });

      // Generate refresh token (long-lived)
      const refreshToken = TokenService.generateRefreshToken();
      
      // Save refresh token to database
      await TokenService.saveRefreshToken({
        token: refreshToken,
        userId: admin._id,
        userType: 'admin',
        deviceId,
        deviceName,
        ipAddress,
        userAgent: req.get('User-Agent'),
        expiresAt: TokenService.calculateTokenExpiry()
      });


      const adminResponse = admin.toObject();
      delete adminResponse.password;

      res.json({
        message: 'Login successful',
        admin: adminResponse,
        accessToken,
        refreshToken,
        deviceId,
      });
      return;
    }

  } catch (err) {
    console.error('âŒ Login error:', err.message);
    console.error('âŒ Full error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

async function generateUniqueUsernameFromEmail(email) {
  const base = email.split('@')[0].replace(/[^a-zA-Z0-9_]/g, '').toLowerCase() || 'user';
  let candidate = base;
  let suffix = 0;
  while (await User.findOne({ username: candidate }) || await Admin.findOne({ username: candidate })) {
    suffix += 1;
    candidate = `${base}${suffix}`;
  }
  return candidate;
}

// Sign in (or auto-register) with a Google ID token
exports.googleLogin = async (req, res) => {
  try {
    const { idToken } = req.body;
    if (!idToken) {
      return res.status(400).json({ error: 'idToken is required' });
    }
    if (!process.env.GOOGLE_WEB_CLIENT_ID) {
      console.error('GOOGLE_WEB_CLIENT_ID is not configured on the server.');
      return res.status(500).json({ error: 'Google Sign-In is not configured on the server.' });
    }

    const { OAuth2Client } = require('google-auth-library');
    const client = new OAuth2Client(process.env.GOOGLE_WEB_CLIENT_ID);

    let payload;
    try {
      const ticket = await client.verifyIdToken({
        idToken,
        audience: process.env.GOOGLE_WEB_CLIENT_ID,
      });
      payload = ticket.getPayload();
    } catch (verifyErr) {
      console.error('Google ID token verification failed:', verifyErr.message);
      return res.status(401).json({ error: 'Invalid Google credential.' });
    }

    if (!payload?.email || payload.email_verified !== true) {
      return res.status(401).json({ error: 'Google account email is not verified.' });
    }

    const email = payload.email.trim().toLowerCase();
    const googleId = payload.sub;

    const adminWithEmail = await Admin.findOne({ email });
    if (adminWithEmail) {
      // Link Google ID to admin account on first Google sign-in
      if (!adminWithEmail.googleId) {
        adminWithEmail.googleId = googleId;
        await adminWithEmail.save();
      }
      const deviceId = req.body.deviceId || uuidv4();
      const deviceName = req.body.deviceName || req.get('User-Agent');
      const ipAddress = req.ip;
      const accessToken = TokenService.generateAccessToken({
        _id: adminWithEmail._id,
        email: adminWithEmail.email,
        role: 'admin',
        deviceId,
      });
      const refreshToken = TokenService.generateRefreshToken();
      await TokenService.saveRefreshToken({
        token: refreshToken,
        userId: adminWithEmail._id,
        userType: 'admin',
        deviceId,
        deviceName,
        ipAddress,
        userAgent: deviceName,
        expiresAt: TokenService.calculateTokenExpiry(),
      });
      try {
        await logProfileActivity(adminWithEmail._id, 'login', { ipAddress, userAgent: deviceName });
      } catch (_) {}
      const adminResponse = adminWithEmail.toObject();
      delete adminResponse.password;
      return res.status(200).json({
        message: 'Admin login successful',
        admin: adminResponse,
        accessToken,
        refreshToken,
        deviceId,
        userType: 'admin',
      });
    }

    let user = await User.findOne({ $or: [{ googleId }, { email }] });

    if (!user) {
      const username = await generateUniqueUsernameFromEmail(email);
      const uniqueReferralCode = await generateUniqueReferralCode();
      user = new User({
        name: payload.name || email.split('@')[0],
        username,
        email,
        authProvider: 'google',
        googleId,
        isVerified: true,
        referralCode: uniqueReferralCode,
        memberSince: new Date(),
      });
      await user.save();
    } else if (!user.googleId) {
      // Existing local account signing in with Google for the first time â€” link it.
      // authProvider stays 'local' so the account still requires its original
      // password for non-Google logins; googleId alone is enough to allow Google sign-in.
      user.googleId = googleId;
    }

    if (user.deactivatedAccount) {
      return res.status(403).json({
        error: 'This account has been deactivated. Would you like to recover it?',
        canRecover: true,
        email: user.email,
        username: user.username,
      });
    }

    if (user.privacySettings?.twoFactorAuth === true) {
      const otp = Math.floor(100000 + Math.random() * 900000).toString();
      user.loginOTP = { code: otp, expiry: new Date(Date.now() + OTP_EXPIRY_MS), sentAt: new Date() };
      try {
        await sendLoginOTP(user.email, otp);
      } catch {
        return res.status(503).json({ error: 'Could not send 2FA OTP. Please try again.' });
      }
      await user.save();
      return res.status(202).json({ requires2FA: true, email: user.email });
    }

    const deviceId = req.body.deviceId || uuidv4();
    const deviceName = req.body.deviceName || req.get('User-Agent');
    const ipAddress = req.ip;

    const accessToken = TokenService.generateAccessToken({
      _id: user._id,
      email: user.email,
      role: 'user',
      deviceId,
    });
    const refreshToken = TokenService.generateRefreshToken();
    await TokenService.saveRefreshToken({
      token: refreshToken,
      userId: user._id,
      userType: 'user',
      deviceId,
      deviceName,
      ipAddress,
      userAgent: req.get('User-Agent'),
      expiresAt: TokenService.calculateTokenExpiry(),
    });

    try {
      await logProfileActivity(user._id, 'login', { ipAddress, userAgent: req.get('User-Agent') });
    } catch (e) {
      console.error('Failed to log Google login activity:', e);
    }

    if (user.deviceManagement === false) {
      if (user.devices && user.devices.length > 0 && user.devices[0].deviceId !== deviceId) {
        return res.status(409).json({ error: 'This account is already logged in on another device.' });
      }
      user.devices = [];
    }
    const now = new Date();
    user.devices = (user.devices || []).filter((d) => d.deviceId !== deviceId);
    user.devices.push({ deviceId, userAgent: deviceName, ipAddress, lastActive: now, createdAt: now });

    const dailyReward = await applyDailyLoginReward(user);
    await user.save();
    await recordDailyLoginRewardIfNeeded(user, dailyReward);

    const userResponse = user.toObject();
    delete userResponse.password;

    res.json({
      message: 'Login successful',
      user: userResponse,
      accessToken,
      refreshToken,
      deviceId,
      dailyLoginReward: dailyReward,
    });
  } catch (err) {
    console.error('âŒ Google login error:', err.message);
    res.status(500).json({ error: 'Server error' });
  }
};

// Check if username is unique across users and admins
exports.checkUsername = async (req, res) => {
  try {
    const { username } = req.body;
    const userExists = await User.findOne({ username });
    const adminExists = await Admin.findOne({ username });
    if (userExists || adminExists) {
      return res.status(200).json({ unique: false });
    }
    return res.status(200).json({ unique: true });
  } catch (err) {
    res.status(500).json({ unique: false });
  }
};

// Check if email is unique across users and admins
exports.checkEmail = async (req, res) => {
  try {
    let { email } = req.body;
    email = email.trim().toLowerCase();
    const userExists = await User.findOne({ email });
    if (userExists) {
      return res.status(200).json({ unique: false });
    }
    return res.status(200).json({ unique: true });
  } catch (err) {
    res.status(500).json({ unique: false });
  }
};

// Debug endpoint to list all users (for testing)
exports.listUsers = async (req, res) => {
  try {
    const users = await User.find({}).select('username email name');
    res.json({ users });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Send OTP for login (checks both admin and user tables)
exports.sendLoginOtp = async (req, res) => {
  try {
    const { email } = req.body;

    const user = await User.findOne({ email });
    const admin = !user ? await Admin.findOne({ email }) : null;
    const record = user || admin;
    if (!record) return res.status(404).json({ error: 'User not found' });
    const userType = user ? 'user' : 'admin';

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    const expiry = new Date(Date.now() + OTP_EXPIRY_MS);
    record.loginOTP = { code: otp, expiry, sentAt: new Date() };
    await record.save(); // persist before emailing so OTP is never lost

    try {
      await sendLoginOTP(email, otp);
    } catch (emailErr) {
      console.error('[sendLoginOtp] Email send failed:', emailErr.message);
      return res.status(503).json({ error: 'Could not send OTP email. Please check your email address and try again.' });
    }
    res.status(200).json({ message: 'OTP sent to email', userType, name: record.name });
  } catch (err) {
    console.error('âŒ Error in sendLoginOtp:', err.message);
    res.status(503).json({ error: 'Server is temporarily unavailable. Please try again in a moment.' });
  }
};

// Verify OTP for login
exports.verifyLoginOtp = async (req, res) => {
  try {
    const { email, otp } = req.body;

    const user = await User.findOne({ email });
    const admin = !user ? await Admin.findOne({ email }) : null;
    const record = user || admin;
    if (!record) return res.status(404).json({ error: 'User not found' });
    const userType = user ? 'user' : 'admin';

    const stored = record.loginOTP;
    if (!stored || !stored.code) return res.status(400).json({ error: 'No OTP found for this email' });
    if (new Date() > stored.expiry) {
      record.loginOTP = undefined;
      await record.save();
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    if (stored.code !== otp) return res.status(400).json({ error: 'Invalid OTP' });

    // Clear OTP
    record.loginOTP = undefined;

    if (userType === 'user') {
      if (user.deactivatedAccount) {
        await user.save();
        return res.status(403).json({
          error: 'This account has been deactivated. Would you like to recover it?',
          canRecover: true,
          email: user.email,
          username: user.username,
        });
      }

      const deviceId = req.body.deviceId || uuidv4();
      const deviceName = req.body.deviceName || req.get('User-Agent');
      const ipAddress = req.ip;

      const accessToken = TokenService.generateAccessToken({ _id: user._id, email: user.email, role: 'user', deviceId });
      const refreshToken = TokenService.generateRefreshToken();
      await TokenService.saveRefreshToken({
        token: refreshToken, userId: user._id, userType: 'user',
        deviceId, deviceName, ipAddress, userAgent: req.get('User-Agent'),
        expiresAt: TokenService.calculateTokenExpiry(),
      });

      // Log login activity (same as regular login)
      try {
        await logProfileActivity(user._id, 'login', { ipAddress, userAgent: req.get('User-Agent') });
      } catch (e) {
        console.error('Failed to log OTP login activity:', e);
      }

      // Login notification (if enabled)
      if (user.privacySettings?.loginNotifications !== false) {
        sendLoginNotificationEmail({
          to: user.email,
          name: user.name,
          ipAddress,
          userAgent: req.get('User-Agent'),
          loginTime: new Date()
        }).catch(e => console.error('Failed to send OTP login notification email:', e));

        Notification.create({
          sender: user._id, senderModel: 'User', recipientType: 'specific-users',
          recipients: [user._id], recipientModel: 'User', category: 'system',
          title: 'New Login Detected 🔐',
          message: `New login to your account from ${ipAddress || 'unknown location'}.`,
        }).catch((e) => console.error('OTP login notification failed:', e.message));
        sendToUser(User, user._id, { title: 'New Login Detected 🔐', body: `New login from ${ipAddress || 'unknown'}.`, data: { type: 'security_login' } });
      }

      // Register device
      user.devices = (user.devices || []).filter(d => d.deviceId !== deviceId);
      const now = new Date();
      user.devices.push({ deviceId, userAgent: deviceName, ipAddress, lastActive: now, createdAt: now });

      const dailyReward = await applyDailyLoginReward(user);
      await user.save();
      await recordDailyLoginRewardIfNeeded(user, dailyReward);

      const userResponse = user.toObject();
      delete userResponse.password;
      return res.status(200).json({ message: 'Login successful', userType: 'user', user: userResponse, accessToken, refreshToken, deviceId, dailyLoginReward: dailyReward });
    } else {
      const deviceId = req.body.deviceId || uuidv4();
      const deviceName = req.body.deviceName || req.get('User-Agent');
      const ipAddress = req.ip;

      const accessToken = TokenService.generateAccessToken({ _id: admin._id, userId: admin._id, email: admin.email, role: 'admin', deviceId, isSuperAdmin: admin.isSuperAdmin === true });
      const refreshToken = TokenService.generateRefreshToken();
      await TokenService.saveRefreshToken({
        token: refreshToken, userId: admin._id, userType: 'admin',
        deviceId, deviceName, ipAddress, userAgent: req.get('User-Agent'),
        expiresAt: TokenService.calculateTokenExpiry(),
      });

      await admin.save();
      const adminResponse = admin.toObject();
      delete adminResponse.password;
      return res.status(200).json({ message: 'Login successful', userType: 'admin', admin: adminResponse, accessToken, refreshToken, deviceId });
    }
  } catch (err) {
    console.error('âŒ Error in verifyLoginOtp:', err);
    res.status(400).json({ error: err.message });
  }
};

// List active devices for the current user
exports.listDevices = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('devices');
    if (!user) return res.status(404).json({ error: 'User not found' });
    res.json({ devices: user.devices || [] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// Logout a specific device
exports.logoutDevice = async (req, res) => {
  try {
    const { deviceId } = req.body;
    if (!deviceId) return res.status(400).json({ error: 'deviceId required' });
    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ error: 'User not found' });
    user.devices = (user.devices || []).filter(d => d.deviceId !== deviceId);
    await user.save();
    await logProfileActivity(req.user._id, 'logout');
    res.json({ message: 'Device logged out successfully' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// Recover deactivated account
exports.recoverAccount = async (req, res) => {
  try {
    const { emailOrUsername } = req.body;
    if (!emailOrUsername) {
      return res.status(400).json({ error: 'Email or username is required.' });
    }
    const user = await User.findOne({
      $or: [
        { email: emailOrUsername.trim().toLowerCase() },
        { username: emailOrUsername }
      ]
    });
    if (!user) {
      return res.status(404).json({ error: 'User not found.' });
    }
    if (!user.deactivatedAccount) {
      return res.status(400).json({ error: 'Account is already active.' });
    }
    user.deactivatedAccount = false;
    user.isActive = true;
    await user.save();
    res.json({ message: 'Account recovered successfully. You can now log in.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

// Get user by ID
exports.getUserById = async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('name email gender chatEncryptionDevices');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(user);
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateChatEncryptionPublicKey = async (req, res) => {
  try {
    const { chatEncryptionPublicKey, deviceId } = req.body || {};

    if (!chatEncryptionPublicKey || typeof chatEncryptionPublicKey !== 'string') {
      return res.status(400).json({ message: 'chatEncryptionPublicKey is required' });
    }
    if (!deviceId || typeof deviceId !== 'string') {
      return res.status(400).json({ message: 'deviceId is required' });
    }

    const user = await User.findById(req.user._id);
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    const trimmedKey = chatEncryptionPublicKey.trim();
    const existingDevice = user.chatEncryptionDevices.find((d) => d.deviceId === deviceId);
    if (existingDevice) {
      existingDevice.publicKey = trimmedKey;
      existingDevice.updatedAt = new Date();
    } else {
      user.chatEncryptionDevices.push({ deviceId, publicKey: trimmedKey, updatedAt: new Date() });
    }
    // Deprecated field kept roughly in sync for any stale readers; not used for encryption anymore.
    user.chatEncryptionPublicKey = trimmedKey;
    await user.save();

    res.json({
      message: 'Chat encryption public key updated successfully',
      chatEncryptionDevices: user.chatEncryptionDevices,
    });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

// Refresh access token using refresh token
exports.refreshToken = async (req, res) => {
  try {
    const { refreshToken } = req.body;
    
    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token is required' });
    }

    // Validate refresh token
    const tokenData = await TokenService.validateRefreshToken(refreshToken);
    if (!tokenData) {
      return res.status(401).json({ error: 'Invalid or expired refresh token' });
    }

    // Generate new access token
    let tokenSubject = null;
    if (tokenData.userType === 'user') {
      tokenSubject = await User.findById(tokenData.userId).select('_id email').lean();
    } else {
      tokenSubject = await Admin.findById(tokenData.userId)
        .select('_id email isSuperAdmin')
        .lean();
    }

    const newAccessToken = TokenService.generateAccessToken({
      _id: tokenData.userId,
      userId: tokenData.userId,
      email: tokenSubject?.email,
      role: tokenData.userType,
      deviceId: tokenData.deviceId,
      ...(tokenData.userType === 'admin'
          ? { isSuperAdmin: tokenSubject?.isSuperAdmin === true }
          : {}),
    });

    
    res.json({
      message: 'Token refreshed successfully',
      accessToken: newAccessToken
    });

  } catch (error) {
    console.error('âŒ Token refresh error:', error);
    res.status(500).json({ error: 'Server error during token refresh' });
  }
};

// Logout user by revoking refresh token
exports.saveFcmToken = async (req, res) => {
  try {
    const { fcmToken } = req.body;
    if (!fcmToken) return res.status(400).json({ error: 'fcmToken is required' });
    await User.findByIdAndUpdate(req.user._id, { fcmToken });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.logout = async (req, res) => {
  try {
    const { refreshToken } = req.body;
    let logoutActor = null;

    if (refreshToken) {
      const tokenData = await TokenService.validateRefreshToken(refreshToken);

      if (tokenData?.userType === 'user' && tokenData?.userId) {
        logoutActor = {
          userId: tokenData.userId,
          userType: tokenData.userType,
          deviceId: tokenData.deviceId,
        };
      }
    }

    if (!logoutActor) {
      logoutActor = getLogoutActorFromAccessToken(req);
    }

    if (logoutActor?.userType === 'user' && logoutActor?.userId) {
      try {
        await logProfileActivity(logoutActor.userId, 'logout', {
          ipAddress: req.ip,
          userAgent: req.get('User-Agent'),
          deviceId: logoutActor.deviceId,
        });
      } catch (activityError) {
        console.error('Failed to log logout activity:', activityError);
      }
    }

    if (refreshToken) {
      await TokenService.revokeRefreshToken(refreshToken);
    }
    
    res.json({ message: 'Logged out successfully' });
  } catch (error) {
    console.error('âŒ Logout error:', error);
    res.status(500).json({ error: 'Server error during logout' });
  }
};

// Logout from all devices
exports.logoutAllDevices = async (req, res) => {
  try {
    const userId = req.user._id || req.user.userId;
    const userType = req.user.role;
    const { currentDeviceId } = req.body || {};

    // Revoke all refresh tokens
    await TokenService.revokeAllUserTokens(userId, userType);

    // Force all existing access tokens to be invalid immediately
    const user = await User.findById(userId);
    if (user) {
      user.forceLogoutAfter = new Date();
      // Keep only the current device in the devices array
      if (currentDeviceId) {
        user.devices = (user.devices || []).filter(d => d.deviceId === currentDeviceId);
      } else {
        user.devices = [];
      }
      await user.save();
    }

    res.json({ message: 'Logged out from all devices successfully' });
  } catch (error) {
    console.error('âŒ Logout all devices error:', error);
    res.status(500).json({ error: 'Server error during logout from all devices' });
  }
};

// Get active sessions for a user
exports.getActiveSessions = async (req, res) => {
  try {
    const userId = req.user._id || req.user.userId;
    const userType = req.user.role;

    const activeTokens = await TokenService.getUserActiveTokens(userId, userType);
    
    res.json({ 
      activeSessions: activeTokens.map(token => ({
        deviceId: token.deviceId,
        deviceName: token.deviceName,
        ipAddress: token.ipAddress,
        userAgent: token.userAgent,
        createdAt: token.createdAt,
        lastUsed: token.lastUsed,
        expiresAt: token.expiresAt
      }))
    });
  } catch (error) {
    console.error('âŒ Get active sessions error:', error);
    res.status(500).json({ error: 'Server error while fetching active sessions' });
  }
};

exports.getFreebieCounts = async (req, res) => {
  try {
    const [user, pricing] = await Promise.all([
      User.findById(req.user._id),
      getCoinPricing(),
    ]);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.status(200).json({
      freeQuickTransactionsRemaining: user.freeQuickTransactionsRemaining,
      freeUserTransactionsRemaining: user.freeUserTransactionsRemaining,
      freeGroupsRemaining: user.freeGroupsRemaining,
      lenDenCoins: user.lenDenCoins,
      coinPricing: {
        privateChatMessageCost: pricing.privateChatMessageCost,
        groupChatMessageCost:   pricing.groupChatMessageCost,
        quickTransactionCost:   pricing.quickTransactionCost,
        secureTransactionCost:  pricing.secureTransactionCost,
        groupCreationCost:      pricing.groupCreationCost,
        groupExpenseCost:       pricing.groupExpenseCost,
        dailyLoginReward:       pricing.dailyLoginReward,
        leaderboardRank1Reward: pricing.leaderboardRank1Reward,
        leaderboardRank2Reward: pricing.leaderboardRank2Reward,
        leaderboardRank3Reward: pricing.leaderboardRank3Reward,
        coinValueCurrency:      pricing.coinValueCurrency,
        coinValue:              pricing.coinValue,
      },
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.applyDailyLoginRewardOnAppOpen = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const dailyLoginReward = await applyDailyLoginReward(user);
    if (dailyLoginReward.awarded) {
      await user.save();
      await recordDailyLoginRewardIfNeeded(user, dailyLoginReward);
    }

    res.status(200).json({
      dailyLoginReward,
      lenDenCoins: user.lenDenCoins,
      lastDailyLoginRewardDate: user.lastDailyLoginRewardDate,
      lastDailyLoginRewardAt: user.lastDailyLoginRewardAt,
    });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

// GET /api/user/favourites — returns all 3 lists populated
exports.getFavourites = async (req, res) => {
  try {
    const user = await User.findById(req.user._id)
      .populate('closeFriends', 'name username email profileImage avgRating')
      .populate('closeCounterparties', 'name username email profileImage avgRating')
      .populate('bookmarkedNotes', 'title content createdAt updatedAt')
      .lean();
    res.json({
      closeFriends: user.closeFriends || [],
      closeCounterparties: user.closeCounterparties || [],
      bookmarkedNotes: user.bookmarkedNotes || [],
    });
  } catch (err) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

// POST /api/user/favourites/close-friend/:userId — toggle
exports.toggleCloseFriend = async (req, res) => {
  try {
    const targetId = req.params.userId;
    const user = await User.findById(req.user._id).select('closeFriends friends');
    if (!user) return res.status(404).json({ message: 'User not found' });
    // Must already be a friend
    const isFriend = user.friends.some(id => id.toString() === targetId);
    if (!isFriend) return res.status(400).json({ message: 'User is not in your friends list' });
    const isClose = user.closeFriends.some(id => id.toString() === targetId);
    if (isClose) {
      await User.findByIdAndUpdate(req.user._id, { $pull: { closeFriends: targetId } });
      return res.json({ added: false, message: 'Removed from close friends' });
    } else {
      await User.findByIdAndUpdate(req.user._id, { $addToSet: { closeFriends: targetId } });
      return res.json({ added: true, message: 'Added to close friends' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

// POST /api/user/favourites/close-counterparty/:userId — toggle
exports.toggleCloseCounterparty = async (req, res) => {
  try {
    const targetId = req.params.userId;
    const user = await User.findById(req.user._id).select('closeCounterparties');
    if (!user) return res.status(404).json({ message: 'User not found' });
    const isClose = user.closeCounterparties.some(id => id.toString() === targetId);
    if (isClose) {
      await User.findByIdAndUpdate(req.user._id, { $pull: { closeCounterparties: targetId } });
      return res.json({ added: false, message: 'Removed from close counterparties' });
    } else {
      await User.findByIdAndUpdate(req.user._id, { $addToSet: { closeCounterparties: targetId } });
      return res.json({ added: true, message: 'Added to close counterparties' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

// POST /api/user/favourites/bookmarked-note/:noteId — toggle
exports.toggleBookmarkedNote = async (req, res) => {
  try {
    const noteId = req.params.noteId;
    const user = await User.findById(req.user._id).select('bookmarkedNotes');
    if (!user) return res.status(404).json({ message: 'User not found' });
    const isBookmarked = user.bookmarkedNotes.some(id => id.toString() === noteId);
    if (isBookmarked) {
      await User.findByIdAndUpdate(req.user._id, { $pull: { bookmarkedNotes: noteId } });
      return res.json({ added: false, message: 'Note unbookmarked' });
    } else {
      await User.findByIdAndUpdate(req.user._id, { $addToSet: { bookmarkedNotes: noteId } });
      return res.json({ added: true, message: 'Note bookmarked' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Internal server error' });
  }
};

