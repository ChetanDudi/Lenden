const mongoose = require('mongoose');
const PROTECTED_SUPERADMIN_EMAIL = 'chetandudi791@gmail.com';

const adminSchema = new mongoose.Schema({
  name: { type: String, required: true },
  username: { type: String, required: true, unique: true },
  password: { type: String, required: true }, // Will be hashed
  email: {
    type: String,
    required: true,
    unique: true,
  },
  gender: {
    type: String,
    enum: ['Male', 'Female', 'Other'],
    required: true,
  },
  birthday: { type: Date },
  address: { type: String },
  phone: { type: String },
  altEmail: { type: String },
  profileImage: { type: Buffer },
  loginOTP: {
    code: { type: String },
    expiry: { type: Date },
    sentAt: { type: Date },
  },
  resetOTP: {
    code: { type: String },
    expiry: { type: Date },
    sentAt: { type: Date },
  },
  isSuperAdmin: { 
    type: Boolean, 
    default: false 
  },
  permissions: {
    canManageUsers: { type: Boolean, default: true },
    canManageTransactions: { type: Boolean, default: true },
    canManageSupport: { type: Boolean, default: true },
    canManageContent: { type: Boolean, default: true },
    canManageDigitise: { type: Boolean, default: true },
    canManageSettings: { type: Boolean, default: true },
    canViewAuditLogs: { type: Boolean, default: true },
  },
  notificationSettings: {
    systemAlerts: { type: Boolean, default: true },
    maintenanceAlerts: { type: Boolean, default: true },
    errorAlerts: { type: Boolean, default: true },
    performanceAlerts: { type: Boolean, default: true },
    securityAlerts: { type: Boolean, default: true },
    backupAlerts: { type: Boolean, default: true },
    newUserAlerts: { type: Boolean, default: true },
    suspiciousActivityAlerts: { type: Boolean, default: true },
    accountLockoutAlerts: { type: Boolean, default: true },
    failedLoginAlerts: { type: Boolean, default: true },
    userDeletionAlerts: { type: Boolean, default: true },
    bulkActionAlerts: { type: Boolean, default: true },
    largeTransactionAlerts: { type: Boolean, default: true },
    failedTransactionAlerts: { type: Boolean, default: true },
    suspiciousTransactionAlerts: { type: Boolean, default: true },
    dailyTransactionSummary: { type: Boolean, default: true },
    weeklyTransactionSummary: { type: Boolean, default: true },
    monthlyTransactionSummary: { type: Boolean, default: false },
    emailNotifications: { type: Boolean, default: true },
    pushNotifications: { type: Boolean, default: true },
    smsNotifications: { type: Boolean, default: false },
    inAppNotifications: { type: Boolean, default: true },
    notificationFrequency: { type: String, default: 'immediate' },
    quietHoursEnabled: { type: Boolean, default: false },
    quietHoursStart: { type: String, default: '22:00' },
    quietHoursEnd: { type: String, default: '08:00' },
    timezone: { type: String, default: 'UTC' },
    displayNotificationCount: { type: Boolean, default: true },
  },
}, { timestamps: true });

// Add method to check if admin is protected
adminSchema.methods.isProtectedAdmin = function() {
  return this.email === PROTECTED_SUPERADMIN_EMAIL;
};

adminSchema.index({ email: 1 });
adminSchema.index({ username: 1 });
adminSchema.index({ phone: 1 });

adminSchema.statics.createDefaultAdmin = async function() {
  const Admin = this;
  const username = process.env.DEFAULT_ADMIN_USERNAME;
  const email = process.env.DEFAULT_ADMIN_EMAIL;
  const password = process.env.DEFAULT_ADMIN_PASSWORD;
  const name = process.env.DEFAULT_ADMIN_NAME;
  const gender = process.env.DEFAULT_ADMIN_GENDER;
  if (!username || !email || !password || !name || !gender) {
    console.warn('Default admin credentials not set in .env');
    return;
  }
  const normalizedEmail = email.trim().toLowerCase();
  const shouldBeSuperAdmin = normalizedEmail === PROTECTED_SUPERADMIN_EMAIL;
  const exists = await Admin.findOne({
    $or: [{ username }, { email: normalizedEmail }],
  });
  if (!exists) {
    const bcrypt = require('bcrypt');
    const hashedPassword = await bcrypt.hash(password, 10);
    await Admin.create({
      name,
      username,
      password: hashedPassword,
      email: normalizedEmail,
      gender,
      isSuperAdmin: shouldBeSuperAdmin,
    });
  } else if (
    exists.email?.trim?.().toLowerCase() === PROTECTED_SUPERADMIN_EMAIL &&
    exists.isSuperAdmin !== true
  ) {
    exists.isSuperAdmin = true;
    await exists.save();
  }
};

module.exports = mongoose.model('Admin', adminSchema);
