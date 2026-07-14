const User = require('../models/user');
const Admin = require('../models/admin');
const bcrypt = require('bcrypt');
const { sendPasswordResetOTP } = require('../utils/passwordresetemailotp');

// In-memory OTP store for password reset
const resetOtpStore = {};
const OTP_EXPIRY_MS = 2 * 60 * 1000; // 2 minutes

// Send OTP for password reset
exports.sendResetOtp = async (req, res) => {
  try {
    const { email } = req.body;
    let userType = null;
    const user = await User.findOne({ email });
    const admin = await Admin.findOne({ email });
    if (user) {
      userType = 'user';
    } else if (admin) {
      userType = 'admin';
    } else {
      return res.status(404).json({ error: 'User not found' });
    }
    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    resetOtpStore[email] = { otp, userType, created: Date.now() };
    // Send a password reset email (custom subject/text)
    await sendPasswordResetOTP(email, otp);
    res.status(200).json({ message: 'OTP sent to email', userType });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Verify OTP for password reset
exports.verifyResetOtp = async (req, res) => {
  try {
    const { email, otp } = req.body;
    const entry = resetOtpStore[email];
    if (!entry) {
      return res.status(400).json({ error: 'No OTP found for this email' });
    }
    const now = Date.now();
    if (now - entry.created > OTP_EXPIRY_MS) {
      delete resetOtpStore[email];
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    if (entry.otp !== otp) {
      return res.status(400).json({ error: 'Invalid OTP' });
    }
    res.status(200).json({ message: 'OTP verified', userType: entry.userType });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};

// Reset password
exports.resetPassword = async (req, res) => {
  try {
    const { email, userType, newPassword } = req.body;
    if (!email || !userType || !newPassword) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    if (userType === 'user') {
      const user = await User.findOneAndUpdate({ email }, { password: hashedPassword });
      if (!user) return res.status(404).json({ error: 'User not found' });
    } else if (userType === 'admin') {
      const admin = await Admin.findOneAndUpdate({ email }, { password: hashedPassword });
      if (!admin) return res.status(404).json({ error: 'User not found' });
    } else {
      return res.status(400).json({ error: 'Invalid user type' });
    }
    delete resetOtpStore[email];
    res.status(200).json({ message: 'Password reset successful' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}; 