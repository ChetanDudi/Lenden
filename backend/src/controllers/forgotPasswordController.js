const User = require('../models/user');
const Admin = require('../models/admin');
const bcrypt = require('bcrypt');
const { sendPasswordResetOTP } = require('../utils/passwordresetemailotp');

const OTP_EXPIRY_MS = 2 * 60 * 1000; // 2 minutes

function isPasswordValid(password) {
  if (!password || password.length < 8 || password.length > 30) return false;
  if (!/[A-Z]/.test(password)) return false;
  if (!/[a-z]/.test(password)) return false;
  if (!/[^A-Za-z0-9]/.test(password)) return false;
  return true;
}

// Send OTP for password reset
exports.sendResetOtp = async (req, res) => {
  try {
    const { email } = req.body;
    const user = await User.findOne({ email });
    const admin = !user ? await Admin.findOne({ email }) : null;
    const record = user || admin;
    if (!record) return res.status(404).json({ error: 'User not found' });
    const userType = user ? 'user' : 'admin';

    const otp = Math.floor(100000 + Math.random() * 900000).toString();
    record.resetOTP = { code: otp, expiry: new Date(Date.now() + OTP_EXPIRY_MS), sentAt: new Date() };
    await record.save();

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
    const user = await User.findOne({ email });
    const admin = !user ? await Admin.findOne({ email }) : null;
    const record = user || admin;
    if (!record) return res.status(404).json({ error: 'User not found' });

    const stored = record.resetOTP;
    if (!stored || !stored.code) return res.status(400).json({ error: 'No OTP found for this email' });
    if (new Date() > stored.expiry) {
      record.resetOTP = undefined;
      await record.save();
      return res.status(400).json({ error: 'OTP expired. Please request a new OTP.' });
    }
    if (stored.code !== otp) return res.status(400).json({ error: 'Invalid OTP' });

    const userType = user ? 'user' : 'admin';
    res.status(200).json({ message: 'OTP verified', userType });
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
    if (!isPasswordValid(newPassword)) {
      return res.status(400).json({ error: 'Password must be 8–30 characters and include uppercase, lowercase, and a special character.' });
    }

    const Model = userType === 'admin' ? Admin : User;
    const record = await Model.findOne({ email });
    if (!record) return res.status(404).json({ error: 'User not found' });

    // Verify the OTP was actually confirmed (stored code must exist and be unexpired)
    const stored = record.resetOTP;
    if (!stored || !stored.code || new Date() > stored.expiry) {
      return res.status(400).json({ error: 'OTP not verified or expired. Please restart the reset flow.' });
    }

    record.password = await bcrypt.hash(newPassword, 10);
    record.resetOTP = undefined;
    if (record.forceLogoutAfter !== undefined) record.forceLogoutAfter = new Date();
    await record.save();

    res.status(200).json({ message: 'Password reset successful' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
};
