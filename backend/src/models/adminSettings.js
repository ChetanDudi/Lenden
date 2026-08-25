const mongoose = require('mongoose');

const adminSettingsSchema = new mongoose.Schema({
  _singleton: { type: String, default: 'global', unique: true },

  // System settings
  maintenanceMode: { type: Boolean, default: false },
  userRegistrationEnabled: { type: Boolean, default: true },
  emailVerificationRequired: { type: Boolean, default: true },
  phoneVerificationRequired: { type: Boolean, default: false },
  autoApproveUsers: { type: Boolean, default: false },
  enableNotifications: { type: Boolean, default: true },
  enableAnalytics: { type: Boolean, default: true },
  maxTransactionAmount: { type: Number, default: 10000 },
  minTransactionAmount: { type: Number, default: 1 },
  dailyTransactionLimit: { type: Number, default: 50000 },
  monthlyTransactionLimit: { type: Number, default: 500000 },
  maxCommunitiesPerUser: { type: Number, default: 1 },
  defaultCurrency: { type: String, default: 'USD' },
  timezone: { type: String, default: 'UTC' },
  dateFormat: { type: String, default: 'MM/DD/YYYY' },
  timeFormat: { type: String, default: '12-hour' },
  language: { type: String, default: 'English' },

  // Analytics settings
  enableUserTracking: { type: Boolean, default: true },
  enableTransactionAnalytics: { type: Boolean, default: true },
  enablePerformanceMonitoring: { type: Boolean, default: true },
  enableErrorTracking: { type: Boolean, default: true },
  enableUsageAnalytics: { type: Boolean, default: true },
  reportFrequency: { type: String, default: 'daily' },
  reportFormat: { type: String, default: 'pdf' },
  autoGenerateReports: { type: Boolean, default: true },
  emailReports: { type: Boolean, default: false },
  reportEmail: { type: String, default: '' },
  dataRetentionPeriod: { type: String, default: '1_year' },
  anonymizeData: { type: Boolean, default: false },
  enableDataExport: { type: Boolean, default: true },
  enableDataBackup: { type: Boolean, default: true },

  // Security settings
  requireTwoFactorAuth: { type: Boolean, default: false },
  enableSessionTimeout: { type: Boolean, default: true },
  sessionTimeoutMinutes: { type: Number, default: 30 },
  enableLoginNotifications: { type: Boolean, default: true },
  enableFailedLoginAlerts: { type: Boolean, default: true },
  maxFailedAttempts: { type: Number, default: 5 },
  lockoutDuration: { type: Number, default: 15 },
  enableIpWhitelist: { type: Boolean, default: false },
  allowedIps: { type: String, default: '' },
  enableGeolocationRestriction: { type: Boolean, default: false },
  allowedCountries: { type: String, default: '' },
  enableTimeBasedAccess: { type: Boolean, default: false },
  accessStartTime: { type: String, default: '09:00' },
  accessEndTime: { type: String, default: '17:00' },
  requireStrongPasswords: { type: Boolean, default: true },
  enablePasswordExpiry: { type: Boolean, default: false },
  passwordExpiryDays: { type: Number, default: 90 },
  preventPasswordReuse: { type: Boolean, default: true },
  passwordHistoryCount: { type: Number, default: 5 },
  enableAccountLockout: { type: Boolean, default: true },
}, { timestamps: true });

const AdminSettings = mongoose.model('AdminSettings', adminSettingsSchema);

async function getOrCreate() {
  let doc = await AdminSettings.findOne({ _singleton: 'global' });
  if (!doc) doc = await AdminSettings.create({ _singleton: 'global' });
  return doc;
}

module.exports = AdminSettings;
module.exports.getOrCreate = getOrCreate;
