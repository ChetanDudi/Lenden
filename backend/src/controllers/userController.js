const User = require('../models/user');
const Admin = require('../models/admin');
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

// In-memory OTP store (for demo; use DB or cache in production)
const otpStore = {};
const OTP_EXPIRY_MS = 2 * 60 * 1000; // 2 minutes
const DAILY_LOGIN_COINS = 1;

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

function applyDailyLoginReward(user) {
  const todayKey = getUtcDateKey();
  if (user.lastDailyLoginRewardDate === todayKey) {
    return { awarded: false, coinsAwarded: 0 };
  }

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

    const jwtSecret =
      process.env.JWT_SECRET || 'fallback-secret-key-for-development';
    const decoded = jwt.verify(token, jwtSecret);

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
  otpStore[email] = { otp, data: { name, username, password, email, gender, referralCode }, created: Date.now() };
    await sendRegistrationOTP(email, otp);
    res.status(200).json({ message: 'OTP sent to email' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Resend OTP
exports.resendOtp = async (req, res) => {
  try {
    const { email } = req.body;
    const entry = otpStore[email];
    if (!entry) {
      return res.status(400).json({ error: 'No registration in progress for this email.' });
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    otpStore[email].otp = otp;
    otpStore[email].created = Date.now();
    await sendRegistrationOTP(email, otp);
    res.status(200).json({ message: 'New OTP sent to email' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Verify OTP and complete registration
exports.verifyOtp = async (req, res) => {
  try {
    const { email, otp } = req.body;
    const entry = otpStore[email];
    if (!entry) {
      return res.status(400).json({ error: 'No OTP found for this email' });
    }
    const now = Date.now();
    if (now - entry.created > OTP_EXPIRY_MS) {
      delete otpStore[email];
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
    delete otpStore[email];
    res.status(201).json({ message: 'User registered successfully' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Login user or admin
exports.login = async (req, res) => {
  try {
    let { username, password } = req.body;
    console.log('🔐 Login attempt for username/email:', username);
    console.log('📝 Request body:', req.body);
    
    if (username && username.includes('@')) username = username.trim().toLowerCase();
    console.log('🔍 Searching for user or admin with username or email:', username);
    
    // Search in both User and Admin tables
    const user = await User.findOne({ $or: [{ username }, { email: username }] });
    const admin = await Admin.findOne({ $or: [{ username }, { email: username }] });
    
    console.log('👤 User found:', !!user);
    console.log('👨‍💼 Admin found:', !!admin);
    
    if (user) {
      console.log('👤 User details:', { id: user._id, username: user.username, email: user.email });
    }
    if (admin) {
      console.log('👨‍💼 Admin details:', { id: admin._id, username: admin.username, email: admin.email });
    }
    
    if (!user && !admin) {
      console.log('❌ User/Admin not found for:', username);
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
      console.log('🔑 Comparing passwords for user...');
      console.log('🔑 Input password length:', password.length);
      console.log('🔑 Stored password hash length:', user.password.length);
      const match = await bcrypt.compare(password, user.password);
      console.log('🔑 Password match:', match);
      
      if (!match) {
        console.log('❌ Incorrect password for user:', username);
        return res.status(401).json({ error: 'Incorrect password' });
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

      console.log('✅ Login successful for user:', username);
      console.log('🎫 Access token generated successfully');
      console.log('🎫 Refresh token generated and saved');
      
      // Log login activity
      try {
        await logProfileActivity(user._id, 'login', {
          ipAddress: req.ip,
          userAgent: req.get('User-Agent')
        });
      } catch (e) {
        console.error('Failed to log login activity:', e);
      }

      // Send login notification email if enabled
      if (user.loginNotifications !== false) { // default true if undefined
        try {
          await sendLoginNotificationEmail({
            to: user.email,
            name: user.name,
            ipAddress: req.ip,
            userAgent: req.get('User-Agent'),
            loginTime: new Date()
          });
        } catch (e) {
          console.error('Failed to send login notification email:', e);
        }
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
      const dailyReward = applyDailyLoginReward(user);
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
      console.log('🔑 Comparing passwords for admin...');
      console.log('🔑 Input password length:', password.length);
      console.log('🔑 Stored password hash length:', admin.password.length);
      const match = await bcrypt.compare(password, admin.password);
      console.log('🔑 Password match:', match);
      
      if (!match) {
        console.log('❌ Incorrect password for admin:', username);
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

      console.log('✅ Login successful for admin:', username);
      console.log('🎫 Access token generated successfully');
      console.log('🎫 Refresh token generated and saved');

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
    console.error('❌ Login error:', err.message);
    console.error('❌ Full error:', err);
    res.status(500).json({ error: err.message });
  }
};

// Check if username is unique across users and admins
exports.checkUsername = async (req, res) => {
  try {
    const { username } = req.body;
    console.log('Checking username:', username);
    const userExists = await User.findOne({ username });
    const adminExists = await Admin.findOne({ username });
    console.log('User exists:', !!userExists, 'Admin exists:', !!adminExists);
    if (userExists || adminExists) {
      return res.status(200).json({ unique: false });
    }
    return res.status(200).json({ unique: true });
  } catch (err) {
    res.status(500).json({ unique: false, error: err.message });
  }
};

// Check if email is unique across users and admins
exports.checkEmail = async (req, res) => {
  try {
    let { email } = req.body;
    email = email.trim().toLowerCase();
    console.log('Checking email:', email);
    const userExists = await User.findOne({ email });
    console.log('User exists:', !!userExists);
    if (userExists) {
      return res.status(200).json({ unique: false });
    }
    return res.status(200).json({ unique: true });
  } catch (err) {
    res.status(500).json({ unique: false, error: err.message });
  }
};

// Debug endpoint to list all users (for testing)
exports.listUsers = async (req, res) => {
  try {
    const users = await User.find({}).select('username email name');
    console.log('📋 All users in database:', users);
    res.json({ users });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

// Send OTP for login (checks both admin and user tables)
exports.sendLoginOtp = async (req, res) => {
  try {
    const { email } = req.body;
    console.log('🔍 Looking for user with email:', email);
    
    let userType = null;
    let name = null;
    const user = await User.findOne({ email });
    const admin = await Admin.findOne({ email });
    
    console.log('👤 User found:', !!user);
    console.log('👨‍💼 Admin found:', !!admin);
    
    if (user) {
      userType = 'user';
      name = user.name;
      console.log('✅ User found, sending OTP to:', email);
    } else if (admin) {
      userType = 'admin';
      name = admin.name;
      console.log('✅ Admin found, sending OTP to:', email);
    } else {
      console.log('❌ No user or admin found with email:', email);
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Generate OTP
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    otpStore[email] = { otp, userType, created: Date.now() };
    
    console.log('📧 Sending OTP email to:', email);
    await sendLoginOTP(email, otp);
    console.log('✅ OTP sent successfully');
    
    res.status(200).json({ message: 'OTP sent to email', userType, name });
  } catch (err) {
    console.error('❌ Error in sendLoginOtp:', err.message);
    res.status(400).json({ error: err.message });
  }
};

// Verify OTP for login
exports.verifyLoginOtp = async (req, res) => {
  try {
    const { email, otp } = req.body;
    console.log('🔐 OTP verification attempt for email:', email);
    console.log('🔐 OTP provided:', otp);
    
    const entry = otpStore[email];
    if (!entry) {
      console.log('❌ No OTP found for email:', email);
      return res.status(400).json({ error: 'No OTP found for this email' });
    }
    
    const now = Date.now();
    if (now - entry.created > OTP_EXPIRY_MS) {
      console.log('❌ OTP expired for email:', email);
      delete otpStore[email];
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    
    if (entry.otp !== otp) {
      console.log('❌ Invalid OTP for email:', email);
      return res.status(400).json({ error: 'Invalid OTP' });
    }
    
    console.log('✅ OTP verified successfully for email:', email);
    console.log('👤 User type from OTP store:', entry.userType);
    
    // Find user or admin
    let user = null;
    let admin = null;
    if (entry.userType === 'user') {
      user = await User.findOne({ email });
      if (!user) {
        console.log('❌ User not found in database for email:', email);
        return res.status(404).json({ error: 'User not found' });
      }
      if (user.deactivatedAccount) {
        return res.status(403).json({
          error: 'This account has been deactivated. Would you like to recover it?',
          canRecover: true,
          email: user.email,
          username: user.username
        });
      }
      
      console.log('✅ User found in database:', { id: user._id, name: user.name, email: user.email });
      
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

      console.log('✅ OTP login successful for user:', email);
      console.log('🎫 Access token generated successfully');
      console.log('🎫 Refresh token generated and saved');

      const dailyReward = applyDailyLoginReward(user);
      await user.save();
      await recordDailyLoginRewardIfNeeded(user, dailyReward);

      const userResponse = user.toObject();
      delete userResponse.password;

      delete otpStore[email];
      return res.status(200).json({
        message: 'Login successful',
        userType: 'user',
        user: userResponse,
        accessToken,
        refreshToken,
        deviceId,
        dailyLoginReward: dailyReward,
      });
    } else if (entry.userType === 'admin') {
      admin = await Admin.findOne({ email });
      if (!admin) {
        console.log('❌ Admin not found in database for email:', email);
        return res.status(404).json({ error: 'User not found' });
      }
      
      console.log('✅ Admin found in database:', { id: admin._id, name: admin.name, email: admin.email });
      
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

      console.log('✅ OTP login successful for admin:', email);
      console.log('🎫 Access token generated successfully');
      console.log('🎫 Refresh token generated and saved');

      const adminResponse = admin.toObject();
      delete adminResponse.password;

      delete otpStore[email];
      return res.status(200).json({
        message: 'Login successful',
        userType: 'admin',
        admin: adminResponse,
        accessToken,
        refreshToken,
        deviceId,
      });
    }
    
    console.log('❌ Unknown user type:', entry.userType);
    return res.status(404).json({ error: 'User not found' });
  } catch (err) {
    console.error('❌ Error in verifyLoginOtp:', err);
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
    await user.save();
    res.json({ message: 'Account recovered successfully. You can now log in.' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
};

exports.getUserById = async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('name email chatEncryptionPublicKey');
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

// Get user by ID
exports.getUserById = async (req, res) => {
  try {
    const user = await User.findById(req.params.id).select('name email chatEncryptionPublicKey');
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.updateChatEncryptionPublicKey = async (req, res) => {
  try {
    const { chatEncryptionPublicKey } = req.body || {};

    if (!chatEncryptionPublicKey || typeof chatEncryptionPublicKey !== 'string') {
      return res.status(400).json({ message: 'chatEncryptionPublicKey is required' });
    }

    const user = await User.findByIdAndUpdate(
      req.user._id,
      { chatEncryptionPublicKey: chatEncryptionPublicKey.trim() },
      { new: true }
    ).select('chatEncryptionPublicKey');

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json({
      message: 'Chat encryption public key updated successfully',
      chatEncryptionPublicKey: user.chatEncryptionPublicKey,
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

    console.log('✅ Token refreshed successfully for user:', tokenData.userId);
    
    res.json({
      message: 'Token refreshed successfully',
      accessToken: newAccessToken
    });

  } catch (error) {
    console.error('❌ Token refresh error:', error);
    res.status(500).json({ error: 'Server error during token refresh' });
  }
};

// Logout user by revoking refresh token
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
    console.error('❌ Logout error:', error);
    res.status(500).json({ error: 'Server error during logout' });
  }
};

// Logout from all devices
exports.logoutAllDevices = async (req, res) => {
  try {
    const { userId, userType } = req.body;
    
    if (!userId || !userType) {
      return res.status(400).json({ error: 'User ID and user type are required' });
    }

    await TokenService.revokeAllUserTokens(userId, userType);
    
    res.json({ message: 'Logged out from all devices successfully' });
  } catch (error) {
    console.error('❌ Logout all devices error:', error);
    res.status(500).json({ error: 'Server error during logout from all devices' });
  }
};

// Get active sessions for a user
exports.getActiveSessions = async (req, res) => {
  try {
    const { userId, userType } = req.query;
    
    if (!userId || !userType) {
      return res.status(400).json({ error: 'User ID and user type are required' });
    }

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
    console.error('❌ Get active sessions error:', error);
    res.status(500).json({ error: 'Server error while fetching active sessions' });
  }
};

exports.getFreebieCounts = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.status(200).json({
      freeQuickTransactionsRemaining: user.freeQuickTransactionsRemaining,
      freeUserTransactionsRemaining: user.freeUserTransactionsRemaining,
      freeGroupsRemaining: user.freeGroupsRemaining,
      lenDenCoins: user.lenDenCoins,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.applyDailyLoginRewardOnAppOpen = async (req, res) => {
  try {
    const user = await User.findById(req.user._id);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const dailyLoginReward = applyDailyLoginReward(user);
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
    res.status(500).json({ error: error.message });
  }
};
