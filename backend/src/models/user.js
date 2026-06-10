const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
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
  walletBalance: { type: Number, default: 0 },
  altEmail: { type: String },
  altEmailOTP: {
    code: { type: String },
    email: { type: String },
    expiry: { type: Date }
  },
  memberSince: { type: Date, default: Date.now },
  avgRating: {
    type: Number,
    min: 0,
    max: 5,
    default: 0
  },
  profileImage: { type: Buffer }, // Store image as binary
  chatEncryptionPublicKey: { type: String, default: null },
  role: { type: String, enum: ['user', 'admin'], default: 'user' },
  isActive: { type: Boolean, default: true },
  isVerified: { type: Boolean, default: true },
  suspendedUntil: {
    type: Date,
    default: null,
  },
  suspensionReason: {
    type: String,
    default: null,
  },
  forceLogoutAfter: {
    type: Date,
    default: null,
  },
  adminNotes: [
    {
      admin: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'Admin',
        required: true,
      },
      noteText: {
        type: String,
        required: true,
        trim: true,
      },
      createdAt: {
        type: Date,
        default: Date.now,
      },
    },
  ],
  deactivatedAccount: {
    type: Boolean,
    default: false
  },
  freeQuickTransactionsRemaining: {
    type: Number,
    default: 10
  },
  freeUserTransactionsRemaining: {
    type: Number,
    default: 5
  },
  freeGroupsRemaining: {
    type: Number,
    default: 3
  },
  lenDenCoins: {
    type: Number,
    default: 20
  },
  lastDailyLoginRewardDate: {
    type: String,
    default: null,
  },
  lastDailyLoginRewardAt: {
    type: Date,
    default: null,
  },
  referralCode: {
    type: String,
    unique: true,
    sparse: true,
    trim: true,
  },
  referredByUser: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    default: null,
  },
  referredByCode: {
    type: String,
    default: null,
  },
  referralRewardGranted: {
    type: Boolean,
    default: false,
  },
  referralConvertedAt: {
    type: Date,
    default: null,
  },
  friends: [
    {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    }
  ],
  blockedUsers: [
    {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User'
    }
  ],
  
  // Notification Settings
  notificationSettings: {
    transactionNotifications: { type: Boolean, default: true },
    paymentReminders: { type: Boolean, default: true },
    chatNotifications: { type: Boolean, default: true },
    groupNotifications: { type: Boolean, default: true },
    emailNotifications: { type: Boolean, default: true },
    pushNotifications: { type: Boolean, default: true },
    smsNotifications: { type: Boolean, default: false },
    reminderFrequency: { type: String, enum: ['daily', 'weekly', 'monthly'], default: 'daily' },
    quietHoursStart: { type: String, default: '22:00' },
    quietHoursEnd: { type: String, default: '08:00' },
    quietHoursEnabled: { type: Boolean, default: false },
    displayNotificationCount: { type: Boolean, default: true },
  },
  
  // Privacy Settings
  privacySettings: {
    profileVisibility: { type: Boolean, default: true },
    transactionHistory: { type: Boolean, default: true },
    contactSharing: { type: Boolean, default: false },
    analyticsSharing: { type: Boolean, default: true },
    marketingEmails: { type: Boolean, default: false },
    dataCollection: { type: Boolean, default: true },
    twoFactorAuth: { type: Boolean, default: false },
    loginNotifications: { type: Boolean, default: true },
    deviceManagement: { type: Boolean, default: true },
    sessionTimeout: {
      type: Number,
      default: 30 // in minutes, 0 means never timeout
    },
    lastActivityAt: {
      type: Date,
      default: Date.now
    },
  },
  devices: [
    {
      deviceId: { type: String, required: true },
      userAgent: String,
      ipAddress: String,
      lastActive: { type: Date, default: Date.now },
      createdAt: { type: Date, default: Date.now }
    }
  ],
}, { timestamps: true });

userSchema.index({ email: 1 });
userSchema.index({ username: 1 });
userSchema.index({ phone: 1 });
userSchema.index({ referralCode: 1 });

module.exports = mongoose.model('User', userSchema);
