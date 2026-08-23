const User = require('../models/user');
const Admin = require('../models/admin');
const AdminSettings = require('../models/adminSettings');

const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const GroupTransaction = require('../models/groupTransaction');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const Activity = require('../models/activity');
const Subscription = require('../models/subscription');
const SupportQuery = require('../models/supportQuery');
const Notification = require('../models/notification');
const AppUpdate = require('../models/appUpdate');
const AppAd = require('../models/appAd');
const AppAdEvent = require('../models/appAdEvent');
const Feedback = require('../models/feedback');
const AdminAuditLog = require('../models/adminAuditLog');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { sendAdminWelcomeEmail, sendAdminRemovalEmail } = require('../utils/email/adminEmailNotifications');
const { logAdminAudit } = require('../utils/adminAuditLogger');

const roundToTwo = (value) => Number((Number(value || 0)).toFixed(2));

const startOfToday = () => {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
};

const endOfToday = () => {
  const start = startOfToday();
  return new Date(start.getTime() + 24 * 60 * 60 * 1000);
};

const normalizeSecureTransaction = (transaction, userEmail) => ({
  _id: transaction._id,
  transactionId: transaction.transactionId,
  source: 'secure',
  amount: Number(transaction.amount || 0),
  currency: transaction.currency || '',
  createdAt: transaction.createdAt || transaction.date || new Date(),
  date: transaction.date || transaction.createdAt || null,
  status:
    transaction.userCleared && transaction.counterpartyCleared
      ? 'completed'
      : transaction.isPartiallyPaid
          ? 'partially_paid'
          : 'pending',
  counterpart:
    transaction.userEmail === userEmail
      ? transaction.counterpartyEmail
      : transaction.userEmail,
  place: transaction.place || '',
  description: transaction.description || '',
  role: transaction.role || '',
});

const normalizeQuickTransaction = (transaction, userEmail) => ({
  _id: transaction._id,
  transactionId: transaction._id,
  source: 'quick',
  amount: Number(transaction.amount || 0),
  currency: transaction.currency || '',
  createdAt: transaction.createdAt || transaction.date || new Date(),
  date: transaction.date || transaction.createdAt || null,
  status: transaction.cleared ? 'completed' : 'pending',
  counterpart: (transaction.users || [])
    .filter((email) => email !== userEmail)
    .join(', '),
  place: '',
  description: transaction.description || '',
  role: transaction.role || '',
});

const buildAdminNotificationFilter = (adminId) => {
  if (!adminId) return { _id: null };

  return {
    recipientModel: 'Admin',
    $or: [
      { recipientType: 'all-admins' },
      {
        recipientType: 'specific-admins',
        recipients: adminId,
      },
    ],
    readBy: { $ne: adminId },
  };
};

const ADMIN_PERMISSION_KEYS = [
  'canManageUsers',
  'canManageTransactions',
  'canManageSupport',
  'canManageContent',
  'canManageDigitise',
  'canManageSettings',
  'canViewAuditLogs',
];

const normalizeAdminPermissions = (permissions = {}) => {
  const normalized = {};
  for (const key of ADMIN_PERMISSION_KEYS) {
    normalized[key] = permissions[key] !== false;
  }
  return normalized;
};

const hasAdminPermission = (admin, key) => {
  if (!admin) return false;
  if (admin.isSuperAdmin === true) return true;
  return normalizeAdminPermissions(admin.permissions || {})[key] === true;
};

const escapeCsv = (value) => {
  const stringValue =
    value === null || value === undefined ? '' : String(value);
  return `"${stringValue.replace(/"/g, '""')}"`;
};

const sendCsv = (res, filename, columns, rows) => {
  const header = columns.map((column) => escapeCsv(column.label)).join(',');
  const body = rows
    .map((row) =>
      columns.map((column) => escapeCsv(row[column.key])).join(',')
    )
    .join('\n');
  const csv = `${header}\n${body}`;

  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);
  return res.status(200).send(csv);
};

const ensureGroupBalanceEntries = (group) => {
  if (!group) return false;

  let changed = false;
  const existingUserIds = new Set(
    (group.balances || []).map((entry) => entry.user.toString())
  );

  for (const member of group.members || []) {
    const memberId = member.user?.toString();
    if (!memberId || existingUserIds.has(memberId)) continue;

    group.balances.push({ user: member.user, balance: 0 });
    existingUserIds.add(memberId);
    changed = true;
  }

  return changed;
};

const formatAdminGroupResponse = (group) => {
  const groupObj = group.toObject();
  groupObj.members = (groupObj.members || []).map((member) => ({
    _id: member.user._id,
    email: member.user.email,
    joinedAt: member.joinedAt,
    leftAt: member.leftAt
  }));
  groupObj.creator = groupObj.creator
    ? {
        _id: groupObj.creator._id,
        email: groupObj.creator.email
      }
    : null;

  return groupObj;
};

const rebuildGroupBalances = async (group) => {
  if (!group) return false;

  let changed = ensureGroupBalanceEntries(group);
  const balanceMap = new Map();

  for (const entry of group.balances || []) {
    balanceMap.set(entry.user.toString(), 0);
  }

  const payerCache = new Map();

  for (const expense of group.expenses || []) {
    for (const splitItem of expense.split || []) {
      const userId = splitItem.user?.toString();
      if (!userId) continue;
      balanceMap.set(
        userId,
        (balanceMap.get(userId) || 0) + Number(splitItem.amount || 0)
      );
    }

    if (expense.addedBy) {
      let payerId = payerCache.get(expense.addedBy);
      if (payerId === undefined) {
        const payer = await User.findOne({ email: expense.addedBy }).select('_id');
        payerId = payer?._id?.toString() || null;
        payerCache.set(expense.addedBy, payerId);
      }

      if (payerId) {
        if (!balanceMap.has(payerId)) {
          group.balances.push({ user: payerId, balance: 0 });
          balanceMap.set(payerId, 0);
          changed = true;
        }
        balanceMap.set(
          payerId,
          (balanceMap.get(payerId) || 0) - Number(expense.amount || 0)
        );
      }
    }
  }

  for (const entry of group.balances || []) {
    const userId = entry.user.toString();
    const nextBalance = Number((balanceMap.get(userId) || 0).toFixed(2));
    if (Number(entry.balance || 0) !== nextBalance) {
      entry.balance = nextBalance;
      changed = true;
    }
  }

  return changed;
};

const getCurrentAdmin = async (req) => {
  const adminId = req.user?._id || req.user?.userId || req.user?.id;
  let admin = null;

  if (adminId) {
    admin = await Admin.findById(adminId).select('-password');
  }
  if (!admin && req.user?.email) {
    admin = await Admin.findOne({ email: req.user.email }).select('-password');
  }

  return admin;
};

const toAdminNoteResponse = (note) => ({
  _id: note._id,
  noteText: note.noteText,
  createdAt: note.createdAt,
  admin: note.admin
    ? {
        _id: note.admin._id || note.admin,
        email: note.admin.email,
        name: note.admin.name,
      }
    : null,
});


// Admin registration
const register = async (req, res) => {
  try {
    const { username, email, password, name, adminSecret } = req.body;
    const expectedSecret = process.env.ADMIN_REGISTER_SECRET;
    if (!expectedSecret || adminSecret !== expectedSecret) {
      return res.status(403).json({ success: false, message: 'Forbidden' });
    }

    // Check if admin already exists
    const existingAdmin = await Admin.findOne({
      $or: [{ email }, { username }]
    });

    if (existingAdmin) {
      return res.status(400).json({
        success: false,
        message: 'Admin with this email or username already exists'
      });
    }

    // Hash password
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    // Create admin
    const admin = new Admin({
      username,
      email,
      password: hashedPassword,
      name,
      gender: 'Other', // Default gender for admin
    });

    await admin.save();

    // Generate JWT token
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      console.error('[AdminLogin] JWT_SECRET is not set — cannot issue admin token');
      return res.status(500).json({ error: 'Server misconfiguration' });
    }
    const token = jwt.sign(
      {
        _id: admin._id,
        userId: admin._id,
        email: admin.email,
        role: 'admin',
        isSuperAdmin: admin.isSuperAdmin === true,
      },
      jwtSecret,
      { expiresIn: '24h' }
    );

    res.status(201).json({
      success: true,
      message: 'Admin registered successfully',
      token,
      admin: {
        id: admin._id,
        username: admin.username,
        email: admin.email,
        name: admin.name,
        role: 'admin',
        isSuperAdmin: admin.isSuperAdmin === true,
      }
    });
  } catch (error) {
    console.error('Error registering admin:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to register admin'
    });
  }
};



// Get all users (for admin)
const getAllUsers = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const {
      search,
      statusFilter = 'all',
      sortBy = 'createdAt',
      sortOrder = 'desc',
      page = 1,
      limit = 50,
    } = req.query;

    const query = {};

    // Text search
    if (search && search.trim()) {
      const searchRegex = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      query.$or = [
        { name: searchRegex },
        { email: searchRegex },
        { username: searchRegex },
      ];
    }

    // Status filter
    const statusLower = (statusFilter || 'all').toLowerCase();
    if (statusLower === 'active') {
      query.isActive = true;
    } else if (statusLower === 'inactive') {
      query.isActive = false;
    } else if (statusLower === 'pending') {
      query.isVerified = false;
    } else if (statusLower === 'suspended') {
      query.suspended = true;
    } else if (statusLower === 'deactivated') {
      query.deactivated = true;
    }

    // Sort
    const allowedSortFields = new Set(['name', 'email', 'createdAt', 'status', 'isActive']);
    const sortField = allowedSortFields.has(sortBy) ? sortBy : 'createdAt';
    const sortDir = sortOrder === 'asc' ? 1 : -1;

    const pageNumber = Math.max(1, parseInt(page) || 1);
    const limitNumber = Math.max(1, Math.min(200, parseInt(limit) || 50));
    const skip = (pageNumber - 1) * limitNumber;

    const [users, total] = await Promise.all([
      User.find(query, '-password')
        .populate('adminNotes.admin', 'email name')
        .sort({ [sortField]: sortDir })
        .skip(skip)
        .limit(limitNumber),
      User.countDocuments(query),
    ]);

    res.json({
      success: true,
      users,
      total,
      page: pageNumber,
      limit: limitNumber,
      totalPages: Math.ceil(total / limitNumber),
      currentAdmin: currentAdmin
        ? {
            _id: currentAdmin._id,
            email: currentAdmin.email,
            isSuperAdmin: currentAdmin.isSuperAdmin === true,
            permissions: normalizeAdminPermissions(currentAdmin.permissions),
          }
        : null,
    });
  } catch (error) {
    console.error('Error fetching users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch users'
    });
  }
};

// Get user details with stats
const getUserDetails = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to view user details',
      });
    }

    const { userId } = req.params;
    
    const user = await User.findById(userId, '-password')
      .populate('adminNotes.admin', 'email name')
      .lean();
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const transactionFilter = {
      $or: [{ userEmail: user.email }, { counterpartyEmail: user.email }],
    };
    const quickTransactionFilter = {
      $or: [{ creatorEmail: user.email }, { users: user.email }],
    };

    const [
      secureTransactions,
      quickTransactions,
      secureAggregate,
      quickAggregate,
      secureCompletedCount,
      quickCompletedCount,
      groups,
      loginCount,
      latestActivity,
      recentActivities,
      activeSubscription,
    ] = await Promise.all([
      Transaction.find(transactionFilter).sort({ createdAt: -1 }).limit(8).lean(),
      QuickTransaction.find(quickTransactionFilter)
        .sort({ createdAt: -1 })
        .limit(8)
        .lean(),
      Transaction.aggregate([
        { $match: transactionFilter },
        {
          $group: {
            _id: null,
            totalTransactions: { $sum: 1 },
            totalAmount: { $sum: '$amount' },
            largestTransaction: { $max: '$amount' },
          },
        },
      ]),
      QuickTransaction.aggregate([
        { $match: quickTransactionFilter },
        {
          $group: {
            _id: null,
            totalTransactions: { $sum: 1 },
            totalAmount: { $sum: '$amount' },
            largestTransaction: { $max: '$amount' },
          },
        },
      ]),
      Transaction.countDocuments({
        ...transactionFilter,
        userCleared: true,
        counterpartyCleared: true,
      }),
      QuickTransaction.countDocuments({
        ...quickTransactionFilter,
        cleared: true,
      }),
      GroupTransaction.find({
        isActive: true,
        'members.user': user._id,
      })
        .select('creator members')
        .lean(),
      Activity.countDocuments({ user: user._id, type: 'login' }),
      Activity.findOne({ user: user._id }).sort({ createdAt: -1 }).lean(),
      Activity.find({ user: user._id }).sort({ createdAt: -1 }).limit(10).lean(),
      Subscription.findOne({
        user: user._id,
        subscribed: true,
        status: 'active',
        endDate: { $gte: new Date() },
      })
        .sort({ endDate: -1 })
        .lean(),
    ]);

    const secureSummary = secureAggregate[0] || {};
    const quickSummary = quickAggregate[0] || {};
    const totalTransactions =
      Number(secureSummary.totalTransactions || 0) +
      Number(quickSummary.totalTransactions || 0);
    const totalAmount =
      Number(secureSummary.totalAmount || 0) +
      Number(quickSummary.totalAmount || 0);
    const successfulTransactions =
      Number(secureCompletedCount || 0) + Number(quickCompletedCount || 0);
    const pendingTransactions = Math.max(
      totalTransactions - successfulTransactions,
      0
    );
    const largestTransaction = Math.max(
      Number(secureSummary.largestTransaction || 0),
      Number(quickSummary.largestTransaction || 0)
    );
    const averageTransaction =
      totalTransactions > 0 ? totalAmount / totalTransactions : 0;
    const totalGroups = groups.filter((group) =>
      (group.members || []).some(
        (member) =>
          member?.user?.toString?.() === user._id.toString() && !member.leftAt
      )
    ).length;
    const groupsCreated = groups.filter(
      (group) => group.creator?.toString?.() === user._id.toString()
    ).length;
    const recentTransactions = [...secureTransactions, ...quickTransactions]
      .map((transaction) =>
        transaction.userEmail || transaction.counterpartyEmail
          ? normalizeSecureTransaction(transaction, user.email)
          : normalizeQuickTransaction(transaction, user.email)
      )
      .sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
      )
      .slice(0, 10);

    const lastActivityAt =
      latestActivity?.createdAt ||
      user.privacySettings?.lastActivityAt ||
      user.updatedAt ||
      user.createdAt;

    const userStats = {
      totalTransactions,
      totalAmount: roundToTwo(totalAmount),
      successfulTransactions,
      pendingTransactions,
      averageTransaction: roundToTwo(averageTransaction),
      largestTransaction: roundToTwo(largestTransaction),
      totalGroups,
      groupsCreated,
      totalFriends: Array.isArray(user.friends) ? user.friends.length : 0,
      daysActive: Math.max(
        1,
        Math.ceil(
          (Date.now() - new Date(user.createdAt || Date.now()).getTime()) /
            (24 * 60 * 60 * 1000)
        )
      ),
      lastActivity: lastActivityAt,
      loginCount,
      profileViews: 0,
      secureTransactions:
        Number(secureSummary.totalTransactions || 0),
      quickTransactions:
        Number(quickSummary.totalTransactions || 0),
      activeSubscription: activeSubscription
        ? {
            subscribed: true,
            plan: activeSubscription.subscriptionPlan || 'Active plan',
            endDate: activeSubscription.endDate,
          }
        : null,
      lenDenCoins: Number(user.lenDenCoins || 0),
    };

    res.json({
      success: true,
      user: {
        ...user,
        adminNotes: Array.isArray(user.adminNotes)
          ? user.adminNotes.map((note) => toAdminNoteResponse(note))
          : [],
        isSuspended:
          !!user.suspendedUntil && new Date(user.suspendedUntil) > new Date(),
      },
      stats: userStats,
      recentTransactions: recentTransactions,
      userActivity: recentActivities.map((activity) => ({
        _id: activity._id,
        action: activity.type,
        title: activity.title,
        description: activity.description,
        amount: activity.amount,
        timestamp: activity.createdAt,
        metadata: activity.metadata || {},
      })),
    });
  } catch (error) {
    console.error('Error fetching user details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch user details'
    });
  }
};

// Update user status (activate/deactivate)
const updateUserStatus = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const { userId } = req.params;
    const { isActive } = req.body;

    const user = await User.findByIdAndUpdate(
      userId,
      { isActive: isActive },
      { new: true, select: '-password' }
    );

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    res.json({
      success: true,
      message: `User ${isActive ? 'activated' : 'deactivated'} successfully`,
      user: user
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_status_updated',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} ${isActive ? 'activated' : 'deactivated'} user ${user.email}`,
      details: { isActive },
      severity: 'warning',
    });
  } catch (error) {
    console.error('Error updating user status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update user status'
    });
  }
};

// Update user information
const updateUser = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to update users',
      });
    }

    const { userId } = req.params;
    const updateData = req.body;

    // Remove sensitive fields that shouldn't be updated directly
    delete updateData.password;
    delete updateData.email; // Email should be updated through a separate process
    delete updateData.username; // Username should be updated through a separate process

    const user = await User.findByIdAndUpdate(
      userId,
      updateData,
      { new: true, select: '-password' }
    );

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    res.json({
      success: true,
      message: 'User updated successfully',
      user: user
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_updated',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} updated user ${user.email}`,
      details: { updatedFields: Object.keys(updateData) },
    });
  } catch (error) {
    console.error('Error updating user:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update user'
    });
  }
};

// Delete user
const deleteUser = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to delete users',
      });
    }

    const { userId } = req.params;

    const user = await User.findByIdAndDelete(userId);
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Detach user reference from their app rating so the rating persists
    try {
      const { markRatingUserDeleted } = require('./AppratingController');
      await markRatingUserDeleted(user._id);
    } catch (_) {}

    res.json({
      success: true,
      message: 'User deleted successfully'
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_deleted',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} deleted user ${user.email}`,
      severity: 'critical',
    });
  } catch (error) {
    console.error('Error deleting user:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete user'
    });
  }
};

const SYSTEM_SETTINGS_KEYS = [
  'maintenanceMode','userRegistrationEnabled','emailVerificationRequired',
  'phoneVerificationRequired','autoApproveUsers','enableNotifications',
  'enableAnalytics','maxTransactionAmount','minTransactionAmount',
  'dailyTransactionLimit','monthlyTransactionLimit','defaultCurrency',
  'timezone','dateFormat','timeFormat','language',
];

const ANALYTICS_SETTINGS_KEYS = [
  'enableAnalytics','enableUserTracking','enableTransactionAnalytics',
  'enablePerformanceMonitoring','enableErrorTracking','enableUsageAnalytics',
  'reportFrequency','reportFormat','autoGenerateReports','emailReports',
  'reportEmail','dataRetentionPeriod','anonymizeData','enableDataExport','enableDataBackup',
];

const SECURITY_SETTINGS_KEYS = [
  'requireTwoFactorAuth','enableSessionTimeout','sessionTimeoutMinutes',
  'enableLoginNotifications','enableFailedLoginAlerts','maxFailedAttempts',
  'lockoutDuration','enableIpWhitelist','allowedIps','enableGeolocationRestriction',
  'allowedCountries','enableTimeBasedAccess','accessStartTime','accessEndTime',
  'requireStrongPasswords','enablePasswordExpiry','passwordExpiryDays',
  'preventPasswordReuse','passwordHistoryCount','enableAccountLockout',
];

function pickKeys(obj, keys) {
  const result = {};
  for (const k of keys) result[k] = obj[k];
  return result;
}

// Get system settings
const getSystemSettings = async (req, res) => {
  try {
    const doc = await AdminSettings.getOrCreate();
    res.json(pickKeys(doc, SYSTEM_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error fetching system settings:', error);
    res.status(500).json({ message: 'Failed to fetch system settings' });
  }
};

// Update system settings
const updateSystemSettings = async (req, res) => {
  try {
    const update = {};
    for (const k of SYSTEM_SETTINGS_KEYS) {
      if (req.body[k] !== undefined) update[k] = req.body[k];
    }
    const doc = await AdminSettings.findOneAndUpdate(
      { _singleton: 'global' },
      { $set: update },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    res.json(pickKeys(doc, SYSTEM_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error updating system settings:', error);
    res.status(500).json({ message: 'Failed to update system settings' });
  }
};

// Get analytics settings
const getAnalyticsSettings = async (req, res) => {
  try {
    const doc = await AdminSettings.getOrCreate();
    res.json(pickKeys(doc, ANALYTICS_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error fetching analytics settings:', error);
    res.status(500).json({ message: 'Failed to fetch analytics settings' });
  }
};

// Update analytics settings
const updateAnalyticsSettings = async (req, res) => {
  try {
    const update = {};
    for (const k of ANALYTICS_SETTINGS_KEYS) {
      if (req.body[k] !== undefined) update[k] = req.body[k];
    }
    const doc = await AdminSettings.findOneAndUpdate(
      { _singleton: 'global' },
      { $set: update },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    res.json(pickKeys(doc, ANALYTICS_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error updating analytics settings:', error);
    res.status(500).json({ message: 'Failed to update analytics settings' });
  }
};

// Get security settings
const getSecuritySettings = async (req, res) => {
  try {
    const doc = await AdminSettings.getOrCreate();
    res.json(pickKeys(doc, SECURITY_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error fetching security settings:', error);
    res.status(500).json({ message: 'Failed to fetch security settings' });
  }
};

// Update security settings
const updateSecuritySettings = async (req, res) => {
  try {
    const update = {};
    for (const k of SECURITY_SETTINGS_KEYS) {
      if (req.body[k] !== undefined) update[k] = req.body[k];
    }
    const doc = await AdminSettings.findOneAndUpdate(
      { _singleton: 'global' },
      { $set: update },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    res.json(pickKeys(doc, SECURITY_SETTINGS_KEYS));
  } catch (error) {
    console.error('Error updating security settings:', error);
    res.status(500).json({ message: 'Failed to update security settings' });
  }
};

// Get notification settings
const getNotificationSettings = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin) {
      return res.status(404).json({ success: false, message: 'Admin not found' });
    }

    res.json({
      success: true,
      settings: currentAdmin.notificationSettings
    });
  } catch (error) {
    console.error('Error fetching notification settings:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch notification settings'
    });
  }
};

// Update notification settings
const NOTIFICATION_SETTING_KEYS = [
  'systemAlerts', 'maintenanceAlerts', 'errorAlerts', 'performanceAlerts',
  'securityAlerts', 'backupAlerts', 'newUserAlerts', 'suspiciousActivityAlerts',
  'accountLockoutAlerts', 'failedLoginAlerts', 'userDeletionAlerts', 'bulkActionAlerts',
  'largeTransactionAlerts', 'failedTransactionAlerts', 'suspiciousTransactionAlerts',
  'dailyTransactionSummary', 'weeklyTransactionSummary', 'monthlyTransactionSummary',
  'emailNotifications', 'pushNotifications', 'smsNotifications', 'inAppNotifications',
  'notificationFrequency', 'quietHoursEnabled', 'quietHoursStart', 'quietHoursEnd',
  'timezone', 'displayNotificationCount',
];

const updateNotificationSettings = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin) {
      return res.status(404).json({ success: false, message: 'Admin not found' });
    }

    const settings = req.body || {};
    for (const key of NOTIFICATION_SETTING_KEYS) {
      if (Object.prototype.hasOwnProperty.call(settings, key)) {
        currentAdmin.notificationSettings[key] = settings[key];
      }
    }
    await currentAdmin.save();

    res.json({
      success: true,
      message: 'Notification settings updated successfully',
      settings: currentAdmin.notificationSettings
    });
  } catch (error) {
    console.error('Error updating notification settings:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update notification settings'
    });
  }
};

// Get all admins
const getAllAdmins = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin?.isSuperAdmin && !hasAdminPermission(currentAdmin, 'canManageSettings')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to view admin roles',
      });
    }

    const { search } = req.query;
    let query = {};

    if (search) {
      const safeSearch = escapeRegex(search.trim());
      query = {
        $or: [
          { email: { $regex: safeSearch, $options: 'i' } },
          { username: { $regex: safeSearch, $options: 'i' } },
          { name: { $regex: safeSearch, $options: 'i' } }
        ]
      };
    }

    const admins = await Admin.find(query, '-password').sort({ createdAt: -1 });
    
    res.json({
      success: true,
      admins: admins.map((admin) => ({
        ...admin.toObject(),
        permissions: normalizeAdminPermissions(admin.permissions || {}),
        isProtected: admin.isProtectedAdmin(),
        canToggleSuperAdmin:
          currentAdmin?.isSuperAdmin === true &&
          !admin.isProtectedAdmin() &&
          admin._id.toString() !== currentAdmin._id.toString(),
        canRemove:
          currentAdmin?.isSuperAdmin === true &&
          !admin.isProtectedAdmin() &&
          admin._id.toString() !== currentAdmin._id.toString(),
        canEditPermissions:
          currentAdmin?.isSuperAdmin === true &&
          !admin.isProtectedAdmin() &&
          admin._id.toString() !== currentAdmin._id.toString(),
      })),
      currentAdmin: currentAdmin
        ? {
            _id: currentAdmin._id,
            email: currentAdmin.email,
            isSuperAdmin: currentAdmin.isSuperAdmin === true,
            permissions: normalizeAdminPermissions(currentAdmin.permissions),
          }
        : null,
      total: admins.length
    });
  } catch (error) {
    console.error('Error fetching admins:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch admins'
    });
  }
};

function isPasswordValid(password) {
  return password.length >= 8 && password.length <= 30;
}

// Add new admin
const addAdmin = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin?.isSuperAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Only superadmins can create new admins'
      });
    }

    const { username, email, password, name, gender } = req.body;

    // Password validation
    if (!isPasswordValid(password)) {
      return res.status(400).json({
        success: false,
        message: 'Password must be 8–30 characters.'
      });
    }

    // Check in Admin collection
    const existingAdmin = await Admin.findOne({ 
      $or: [{ email }, { username }]
    });

    if (existingAdmin) {
      return res.status(400).json({
        success: false,
        message: existingAdmin.email === email ? 
          'Email already registered as an admin' : 
          'Username already taken by an admin'
      });
    }

    // Check in User collection
    const existingUser = await User.findOne({
      $or: [{ email }, { username }]
    });

    if (existingUser) {
      return res.status(400).json({
        success: false,
        message: existingUser.email === email ? 
          'Email already registered as a user' : 
          'Username already taken by a user'
      });
    }

    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash(password, salt);

    const admin = new Admin({
      username,
      email,
      password: hashedPassword,
      name,
      gender: gender || 'Other',
      isSuperAdmin: false,
      permissions: normalizeAdminPermissions(req.body.permissions || {}),
    });

    await admin.save();

    // Send welcome email with credentials
    await sendAdminWelcomeEmail(email, {
      name,
      username,
      email,
      password: password
    });

    res.status(201).json({
      success: true,
      message: 'Admin added successfully and welcome email sent',
      admin: {
        id: admin._id,
        username: admin.username,
        email: admin.email,
        name: admin.name,
        isSuperAdmin: admin.isSuperAdmin === true,
        permissions: normalizeAdminPermissions(admin.permissions),
      }
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'admin_created',
      targetType: 'admin',
      targetId: admin._id,
      summary: `${currentAdmin.email} created admin ${admin.email}`,
      details: { permissions: normalizeAdminPermissions(admin.permissions) },
      severity: 'critical',
    });
  } catch (error) {
    console.error('Error adding admin:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add admin'
    });
  }
};

// Remove admin
const removeAdmin = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin?.isSuperAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Only superadmins can remove admins'
      });
    }

    const { adminId } = req.params;
    
    const adminToRemove = await Admin.findById(adminId);
    
    if (!adminToRemove) {
      return res.status(404).json({
        success: false,
        message: 'Admin not found'
      });
    }

    // Check if trying to remove protected admin
    if (adminToRemove.isProtectedAdmin()) {
      return res.status(403).json({
        success: false,
        message: 'Cannot remove protected admin account'
      });
    }

    if (adminToRemove._id.toString() === currentAdmin._id.toString()) {
      return res.status(400).json({
        success: false,
        message: 'You cannot remove your own admin account from here'
      });
    }

    // Send removal notification email before deleting
    await sendAdminRemovalEmail(adminToRemove.email, adminToRemove.name);
    
    await Admin.findByIdAndDelete(adminId);

    res.json({
      success: true,
      message: 'Admin removed successfully and notification email sent'
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'admin_removed',
      targetType: 'admin',
      targetId: adminToRemove._id,
      summary: `${currentAdmin.email} removed admin ${adminToRemove.email}`,
      severity: 'critical',
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to remove admin'
    });
  }
};

const updateAdminPermissions = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin?.isSuperAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Only superadmins can change admin permissions',
      });
    }

    const { adminId } = req.params;
    const targetAdmin = await Admin.findById(adminId);

    if (!targetAdmin) {
      return res.status(404).json({
        success: false,
        message: 'Admin not found',
      });
    }

    if (targetAdmin.isProtectedAdmin()) {
      return res.status(403).json({
        success: false,
        message: 'Protected admin permissions cannot be changed',
      });
    }

    if (targetAdmin._id.toString() === currentAdmin._id.toString()) {
      return res.status(400).json({
        success: false,
        message: 'You cannot change your own permissions from here',
      });
    }

    targetAdmin.permissions = normalizeAdminPermissions(req.body.permissions || {});
    await targetAdmin.save();

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'admin_permissions_updated',
      targetType: 'admin',
      targetId: targetAdmin._id,
      summary: `${currentAdmin.email} updated permissions for ${targetAdmin.email}`,
      details: { permissions: normalizeAdminPermissions(targetAdmin.permissions) },
      severity: 'critical',
    });

    res.json({
      success: true,
      message: 'Admin permissions updated successfully',
      admin: {
        _id: targetAdmin._id,
        email: targetAdmin.email,
        permissions: normalizeAdminPermissions(targetAdmin.permissions),
      },
    });
  } catch (error) {
    console.error('Error updating admin permissions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update admin permissions',
    });
  }
};

const bulkUpdateUserStatus = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const userIds = Array.isArray(req.body.userIds) ? req.body.userIds : [];
    const isActive = req.body.isActive === true;

    if (userIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Select at least one user first',
      });
    }

    const result = await User.updateMany(
      { _id: { $in: userIds } },
      { $set: { isActive } }
    );

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'users_bulk_status_updated',
      targetType: 'user_bulk',
      targetId: userIds.join(','),
      summary: `${currentAdmin.email} ${isActive ? 'activated' : 'deactivated'} ${result.modifiedCount} users in bulk`,
      details: { userIds, isActive, matchedCount: result.matchedCount },
      severity: 'warning',
    });

    res.json({
      success: true,
      message: `${result.modifiedCount} users updated successfully`,
      matchedCount: result.matchedCount,
      modifiedCount: result.modifiedCount,
    });
  } catch (error) {
    console.error('Error bulk updating users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update users in bulk',
    });
  }
};

const exportUsers = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to export users',
      });
    }

    const userIds = (req.query.userIds || '')
      .toString()
      .split(',')
      .map((id) => id.trim())
      .filter(Boolean);

    const filter = userIds.length > 0 ? { _id: { $in: userIds } } : {};
    const users = await User.find(filter, '-password').sort({ createdAt: -1 }).lean();

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'users_exported',
      targetType: 'user_export',
      targetId: userIds.join(','),
      summary: `${currentAdmin.email} exported ${users.length} users`,
      details: { selectedCount: userIds.length, exportedCount: users.length },
    });

    return sendCsv(
      res,
      `users-export-${Date.now()}.csv`,
      [
        { key: 'name', label: 'Name' },
        { key: 'email', label: 'Email' },
        { key: 'username', label: 'Username' },
        { key: 'isActive', label: 'Active' },
        { key: 'isVerified', label: 'Verified' },
        { key: 'lenDenCoins', label: 'LenDen Coins' },
        { key: 'createdAt', label: 'Created At' },
      ],
      users.map((user) => ({
        name: user.name || '',
        email: user.email || '',
        username: user.username || '',
        isActive: user.isActive === true ? 'Yes' : 'No',
        isVerified: user.isVerified === true ? 'Yes' : 'No',
        lenDenCoins: user.lenDenCoins || 0,
        createdAt: user.createdAt ? new Date(user.createdAt).toISOString() : '',
      }))
    );
  } catch (error) {
    console.error('Error exporting users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to export users',
    });
  }
};

const clearPendingUsers = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const result = await User.updateMany(
      { isVerified: false },
      { $set: { isVerified: true } }
    );

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'users_pending_cleared',
      targetType: 'user_bulk',
      targetId: '',
      summary: `${currentAdmin.email} marked ${result.modifiedCount} pending users as verified`,
      details: {
        matchedCount: result.matchedCount,
        modifiedCount: result.modifiedCount,
      },
      severity: 'warning',
    });

    res.json({
      success: true,
      message:
          result.modifiedCount > 0
              ? `${result.modifiedCount} pending users marked as verified`
              : 'No pending users were left to review',
      matchedCount: result.matchedCount,
      modifiedCount: result.modifiedCount,
    });
  } catch (error) {
    console.error('Error clearing pending users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to clear pending users',
    });
  }
};

const reviewPendingUser = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const { userId } = req.params;
    const user = await User.findById(userId).select('-password');

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    if (user.isVerified === true) {
      return res.json({
        success: true,
        message: 'This user has already been reviewed and verified',
        user,
      });
    }

    user.isVerified = true;
    await user.save();

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_pending_reviewed',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} reviewed and verified pending user ${user.email}`,
      details: {
        userEmail: user.email,
        userName: user.name,
      },
      severity: 'info',
    });

    return res.json({
      success: true,
      message: `${user.name || user.email} was reviewed and marked as verified`,
      user,
    });
  } catch (error) {
    console.error('Error reviewing pending user:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to review pending user',
    });
  }
};

const addAdminNoteToUser = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const { userId } = req.params;
    const noteText = (req.body?.noteText || '').toString().trim();
    if (!noteText) {
      return res.status(400).json({
        success: false,
        message: 'Note text is required',
      });
    }

    const user = await User.findById(userId).populate('adminNotes.admin', 'email name');
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    user.adminNotes.push({
      admin: currentAdmin._id,
      noteText,
    });
    await user.save();
    await user.populate('adminNotes.admin', 'email name');

    const latestNote = user.adminNotes[user.adminNotes.length - 1];

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_admin_note_added',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} added an internal note on ${user.email}`,
      details: { noteText },
      severity: 'info',
    });

    return res.json({
      success: true,
      message: 'Internal note added successfully',
      note: toAdminNoteResponse(latestNote),
    });
  } catch (error) {
    console.error('Error adding admin note to user:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to add internal note',
    });
  }
};

const updateUserSuspension = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const { userId } = req.params;
    const { suspendedUntil, suspensionReason, clearSuspension } = req.body || {};
    const user = await User.findById(userId).select('-password');

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    if (clearSuspension === true || !suspendedUntil) {
      user.suspendedUntil = null;
      user.suspensionReason = null;
    } else {
      const parsedDate = new Date(suspendedUntil);
      if (Number.isNaN(parsedDate.getTime())) {
        return res.status(400).json({
          success: false,
          message: 'Suspended until must be a valid date',
        });
      }
      user.suspendedUntil = parsedDate;
      user.suspensionReason = (suspensionReason || '').toString().trim() || null;
    }

    await user.save();

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_suspension_updated',
      targetType: 'user',
      targetId: user._id,
      summary:
        user.suspendedUntil
          ? `${currentAdmin.email} suspended ${user.email} until ${user.suspendedUntil.toISOString()}`
          : `${currentAdmin.email} cleared suspension for ${user.email}`,
      details: {
        suspendedUntil: user.suspendedUntil,
        suspensionReason: user.suspensionReason,
      },
      severity: 'warning',
    });

    return res.json({
      success: true,
      message: user.suspendedUntil
        ? 'User suspension updated successfully'
        : 'User suspension cleared successfully',
      user,
    });
  } catch (error) {
    console.error('Error updating user suspension:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to update suspension',
    });
  }
};

const forceLogoutUser = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canManageUsers')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to manage users',
      });
    }

    const { userId } = req.params;
    const user = await User.findById(userId).select('-password');
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
      });
    }

    user.forceLogoutAfter = new Date();
    user.devices = [];
    await user.save();

    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'user_force_logout',
      targetType: 'user',
      targetId: user._id,
      summary: `${currentAdmin.email} forced logout for ${user.email}`,
      details: {},
      severity: 'warning',
    });

    return res.json({
      success: true,
      message: 'User was logged out from active sessions',
      user,
    });
  } catch (error) {
    console.error('Error forcing logout for user:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to force logout user',
    });
  }
};

const getDashboardSummary = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const adminId = currentAdmin?._id;
    const todayStart = startOfToday();
    const todayEnd = endOfToday();
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);

    const [
      totalUsers,
      activeUsers,
      pendingUsers,
      totalAdmins,
      superAdmins,
      secureTransactions,
      quickTransactions,
      activeGroups,
      openSupportQueries,
      recentFeedbacks,
      activeSubscriptions,
      draftUpdates,
      scheduledUpdates,
      activeAds,
      reportedAdsAggregate,
      unreadAdminNotifications,
      todayUsers,
      todayTransactions,
    ] = await Promise.all([
      User.countDocuments(),
      User.countDocuments({ isActive: true }),
      User.countDocuments({ isVerified: false }),
      Admin.countDocuments(),
      Admin.countDocuments({ isSuperAdmin: true }),
      Transaction.countDocuments(),
      QuickTransaction.countDocuments(),
      GroupTransaction.countDocuments({ isActive: true }),
      SupportQuery.countDocuments({ status: { $in: ['open', 'in_progress'] } }),
      Feedback.countDocuments({ createdAt: { $gte: sevenDaysAgo } }),
      Subscription.countDocuments({
        subscribed: true,
        status: 'active',
        endDate: { $gte: new Date() },
      }),
      AppUpdate.countDocuments({ status: 'draft' }),
      AppUpdate.countDocuments({ status: 'scheduled' }),
      AppAd.countDocuments({
        active: true,
        startsAt: { $lte: new Date() },
        $or: [{ endsAt: null }, { endsAt: { $gte: new Date() } }],
      }),
      AppAdEvent.aggregate([
        { $match: { type: 'report' } },
        { $group: { _id: '$ad' } },
        { $count: 'count' },
      ]),
      Notification.countDocuments(buildAdminNotificationFilter(adminId)),
      User.countDocuments({ createdAt: { $gte: todayStart, $lt: todayEnd } }),
      Promise.all([
        Transaction.countDocuments({
          createdAt: { $gte: todayStart, $lt: todayEnd },
        }),
        QuickTransaction.countDocuments({
          createdAt: { $gte: todayStart, $lt: todayEnd },
        }),
      ]).then(([secureCount, quickCount]) => secureCount + quickCount),
    ]);

    const reportedAds = Number(reportedAdsAggregate[0]?.count || 0);
    const priorityItems = [];

    if (openSupportQueries > 0) {
      priorityItems.push({
        id: 'support',
        title: 'Support queue needs attention',
        description: `${openSupportQueries} open or in-progress support queries are waiting.`,
        count: openSupportQueries,
        sectionId: 'support_queries',
        tone: 'critical',
      });
    }

    if (pendingUsers > 0) {
      priorityItems.push({
        id: 'pending-users',
        title: 'Pending user verification review',
        description: `${pendingUsers} user accounts are still pending verification.`,
        count: pendingUsers,
        sectionId: 'manage_users',
        tone: 'warning',
      });
    }

    if (reportedAds > 0) {
      priorityItems.push({
        id: 'reported-ads',
        title: 'Reported ads should be reviewed',
        description: `${reportedAds} ads currently have user reports.`,
        count: reportedAds,
        sectionId: 'content_analytics',
        tone: 'warning',
      });
    }

    if (scheduledUpdates > 0 || draftUpdates > 0) {
      priorityItems.push({
        id: 'content-pipeline',
        title: 'Content pipeline has pending items',
        description:
          `${draftUpdates} drafts and ${scheduledUpdates} scheduled updates are pending publication.`,
        count: draftUpdates + scheduledUpdates,
        sectionId: 'content_analytics',
        tone: 'info',
      });
    }

    res.json({
      success: true,
      summary: {
        admin: currentAdmin
          ? {
              _id: currentAdmin._id,
              name: currentAdmin.name,
              email: currentAdmin.email,
              isSuperAdmin: currentAdmin.isSuperAdmin === true,
            }
          : null,
        cards: [
          {
            id: 'users',
            label: 'Users',
            value: totalUsers,
            helper: `${activeUsers} active`,
            sectionId: 'manage_users',
          },
          {
            id: 'transactions',
            label: 'Transactions',
            value: secureTransactions + quickTransactions,
            helper: `${todayTransactions} created today`,
            sectionId: 'manage_transactions',
          },
          {
            id: 'groups',
            label: 'Groups',
            value: activeGroups,
            helper: `${activeSubscriptions} subscribed users`,
            sectionId: 'manage_groups',
          },
          {
            id: 'support',
            label: 'Support',
            value: openSupportQueries,
            helper: `${recentFeedbacks} feedback items this week`,
            sectionId: 'support_queries',
          },
        ],
        systemHealth: {
          totalAdmins,
          superAdmins,
          unreadAdminNotifications,
          activeAds,
          scheduledUpdates,
          draftUpdates,
          reportedAds,
          todayUsers,
        },
        priorityItems,
      },
    });
  } catch (error) {
    console.error('Error fetching admin dashboard summary:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch admin dashboard summary',
    });
  }
};

const getAdminAuditLogs = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasAdminPermission(currentAdmin, 'canViewAuditLogs')) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to view audit logs',
      });
    }

    const { search = '', severity = 'All', actor = 'All' } = req.query;
    const filter = {};

    if (severity !== 'All') {
      filter.severity = severity;
    }

    if (actor === 'mine' && currentAdmin?._id) {
      filter.admin = currentAdmin._id;
    }

    if (search.trim()) {
      const safeSearch = escapeRegex(search.trim());
      filter.$or = [
        { adminEmail: { $regex: safeSearch, $options: 'i' } },
        { action: { $regex: safeSearch, $options: 'i' } },
        { summary: { $regex: safeSearch, $options: 'i' } },
        { targetType: { $regex: safeSearch, $options: 'i' } },
      ];
    }

    const logs = await AdminAuditLog.find(filter)
      .sort({ createdAt: -1 })
      .limit(200)
      .lean();

    res.json({
      success: true,
      logs,
      currentAdmin: currentAdmin
        ? {
            _id: currentAdmin._id,
            email: currentAdmin.email,
            isSuperAdmin: currentAdmin.isSuperAdmin === true,
            permissions: normalizeAdminPermissions(currentAdmin.permissions),
          }
        : null,
    });
  } catch (error) {
    console.error('Error fetching admin audit logs:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch admin audit logs',
    });
  }
};

const toggleSuperAdminStatus = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!currentAdmin?.isSuperAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Only superadmins can change superadmin access'
      });
    }

    const { adminId } = req.params;
    const { isSuperAdmin } = req.body;
    const targetAdmin = await Admin.findById(adminId);

    if (!targetAdmin) {
      return res.status(404).json({
        success: false,
        message: 'Admin not found'
      });
    }

    if (targetAdmin.isProtectedAdmin()) {
      return res.status(403).json({
        success: false,
        message: 'Protected admin access cannot be changed'
      });
    }

    if (targetAdmin._id.toString() === currentAdmin._id.toString()) {
      return res.status(400).json({
        success: false,
        message: 'You cannot change your own superadmin status'
      });
    }

    targetAdmin.isSuperAdmin = isSuperAdmin === true;
    await targetAdmin.save();

    res.json({
      success: true,
      message: targetAdmin.isSuperAdmin
        ? 'Superadmin access granted successfully'
        : 'Superadmin access removed successfully',
      admin: {
        _id: targetAdmin._id,
        email: targetAdmin.email,
        username: targetAdmin.username,
        name: targetAdmin.name,
        isSuperAdmin: targetAdmin.isSuperAdmin === true,
      }
    });
    await logAdminAudit({
      req,
      admin: currentAdmin,
      action: 'admin_superadmin_toggled',
      targetType: 'admin',
      targetId: targetAdmin._id,
      summary: `${currentAdmin.email} ${targetAdmin.isSuperAdmin ? 'granted' : 'removed'} superadmin access for ${targetAdmin.email}`,
      details: { isSuperAdmin: targetAdmin.isSuperAdmin === true },
      severity: 'critical',
    });
  } catch (error) {
    console.error('Error toggling superadmin status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update superadmin access'
    });
  }
};

// Get all group transactions (for admin)
const getAllGroupTransactions = async (req, res) => {
  try {
    const {
      page = 1,
      limit = 10,
      sortBy = 'createdAt',
      order = 'desc',
      search,
      sortOrder: sortOrderParam,
    } = req.query;
    const sortDir = (sortOrderParam || order) === 'asc' ? 1 : -1;

    // Build query with optional search
    const query = {};
    if (search && search.trim()) {
      const searchRegex = new RegExp(
        search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
        'i'
      );
      query.$or = [
        { title: searchRegex },
      ];
    }

    // Determine sort field
    const allowedSortFields = { createdAt: 'createdAt', title: 'title', memberCount: 'members' };
    const sortField = allowedSortFields[sortBy] ? sortBy : 'createdAt';

    // For memberCount sort, we need to sort after population; use createdAt as a fallback sort in DB
    const dbSortField = sortBy === 'memberCount' ? 'createdAt' : sortField;

    const groups = await GroupTransaction.find(query)
      .populate('members.user', 'email')
      .populate('creator', 'email')
      .sort({ [dbSortField]: sortDir })
      .skip((page - 1) * limit)
      .limit(parseInt(limit));
    const totalGroups = await GroupTransaction.countDocuments(query);

    for (const group of groups) {
      if (await rebuildGroupBalances(group)) {
        await group.save();
      }
    }

    let groupSummaries = groups.map(formatAdminGroupResponse);

    // If searching creator email or member emails (post-populate), apply additional filter
    if (search && search.trim()) {
      const q = search.trim().toLowerCase();
      groupSummaries = groupSummaries.filter((g) => {
        if ((g.title || '').toLowerCase().includes(q)) return true;
        if ((g.creator?.email || '').toLowerCase().includes(q)) return true;
        if (Array.isArray(g.members)) {
          for (const m of g.members) {
            if ((m.email || m.user?.email || '').toLowerCase().includes(q)) return true;
          }
        }
        return false;
      });
    }

    // Sort by memberCount in memory if needed
    if (sortBy === 'memberCount') {
      groupSummaries.sort((a, b) => {
        const aCount = Array.isArray(a.members) ? a.members.length : 0;
        const bCount = Array.isArray(b.members) ? b.members.length : 0;
        return sortDir === 1 ? aCount - bCount : bCount - aCount;
      });
    }

    res.json({
      success: true,
      groups: groupSummaries,
      totalPages: Math.ceil(totalGroups / limit),
      currentPage: parseInt(page),
      totalGroups,
    });
  } catch (error) {
    console.error('Error fetching group transactions:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch group transactions'
    });
  }
};

// Update a group transaction (for admin)
const updateGroupTransaction = async (req, res) => {
  try {
    const { groupId } = req.params;
    const updateData = req.body;

    const group = await GroupTransaction.findByIdAndUpdate(
      groupId,
      updateData,
      { new: true }
    );

    if (!group) {
      return res.status(404).json({
        success: false,
        message: 'Group transaction not found'
      });
    }

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({
      success: true,
      message: 'Group transaction updated successfully',
      group: groupObj
    });
  } catch (error) {
    console.error('Error updating group transaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update group transaction'
    });
  }
};

// Delete a group transaction (for admin)
const deleteGroupTransaction = async (req, res) => {
  try {
    const { groupId } = req.params;
    const group = await GroupTransaction.findByIdAndDelete(groupId);
    if (!group) {
      return res.status(404).json({
        success: false,
        message: 'Group transaction not found'
      });
    }
    res.json({
      success: true,
      message: 'Group transaction deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting group transaction:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete group transaction'
    });
  }
};

// Add member to group (for admin)
const addMemberToGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { email } = req.body;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const user = await User.findOne({ email });
    if (!user) return res.status(404).json({ error: 'User not found' });

    // Check if user is already an active member
    if (group.members.some(m => m.user.toString() === user._id.toString() && !m.leftAt)) {
      return res.status(400).json({ error: 'User already a member' });
    }

    // Check if user was previously removed and handle re-adding
    const existingMemberIndex = group.members.findIndex(m => m.user.toString() === user._id.toString());
    if (existingMemberIndex !== -1) {
      // User was previously in the group, reactivate them
      group.members[existingMemberIndex].leftAt = null;
      group.members[existingMemberIndex].joinedAt = new Date(); // Update join date
      
      // Check if balance entry exists, if not create one
      const existingBalance = group.balances.find(b => b.user.toString() === user._id.toString());
      if (!existingBalance) {
        group.balances.push({ user: user._id, balance: 0 });
      }
    } else {
      // User is completely new to the group
      group.members.push({ user: user._id, joinedAt: new Date() });
      group.balances.push({ user: user._id, balance: 0 });
    }
    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({ group: groupObj });
  } catch (error) {
    console.error('Error adding member to group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

// Remove member from group (for admin)
const removeMemberFromGroup = async (req, res) => {
  try {
    const { groupId, memberId } = req.params;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const user = await User.findById(memberId);
    if (!user) return res.status(404).json({ error: 'User not found' });

    // Check if trying to remove the creator
    if (user._id.toString() === group.creator.toString()) {
      return res.status(400).json({ error: 'Cannot remove group creator' });
    }

    // Check if user is a member
    const memberIndex = group.members.findIndex(m => m.user.toString() === user._id.toString() && !m.leftAt);
    if (memberIndex === -1) return res.status(400).json({ error: 'User is not a member of this group' });

    // Check if user has pending balances
    const userBalance = group.balances.find(b => b.user.toString() === user._id.toString());
    if (userBalance && userBalance.balance !== 0) {
      return res.status(400).json({ error: 'Cannot remove member with pending balances. Please ask them to settle their balance first.' });
    }

    // Mark member as left
    group.members[memberIndex].leftAt = new Date();
    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({ group: groupObj });
  } catch (error) {
    console.error('Error removing member from group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

// Add expense to group (for admin)
const addExpenseToGroup = async (req, res) => {
  try {
    const { groupId } = req.params;
    const { description, amount, splitType, split, date, selectedMembers, addedByEmail } = req.body;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const addedByUser = await User.findOne({ email: addedByEmail });
    if (!addedByUser) return res.status(404).json({ error: 'User who added expense not found' });

    if (!group.members.some(m => m.user.toString() === addedByUser._id.toString() && !m.leftAt)) return res.status(403).json({ error: 'User who added expense is not a group member' });
    if (!description || !amount || amount <= 0) return res.status(400).json({ error: 'Description and positive amount required' });

    // Validate selected members
    if (!selectedMembers || !Array.isArray(selectedMembers) || selectedMembers.length === 0) {
      return res.status(400).json({ error: 'At least one member must be selected for the expense' });
    }

    const activeMembers = group.members.filter(m => !m.leftAt);
    const activeMemberEmails = await Promise.all(activeMembers.map(async m => {
      const user = await User.findById(m.user);
      return user ? user.email : null;
    })).then(emails => emails.filter(email => email !== null));

    const invalidMembers = selectedMembers.filter(email => !activeMemberEmails.includes(email));
    if (invalidMembers.length > 0) {
      return res.status(400).json({ error: `Invalid members selected: ${invalidMembers.join(', ')}` });
    }

    let splitArr = [];
    if (splitType === 'equal') {
      const per = parseFloat((amount / selectedMembers.length).toFixed(2));
      let total = per * selectedMembers.length;
      let diff = parseFloat((amount - total).toFixed(2));

      splitArr = await Promise.all(selectedMembers.map(async (email, i) => {
        const member = await User.findOne({ email });
        return { user: member._id, amount: per + (i === 0 ? diff : 0) };
      }));
    } else if (splitType === 'custom') {
      if (!Array.isArray(split) || split.length === 0) {
        return res.status(400).json({ error: 'Custom split requires split data for each selected member' });
      }

      const totalSplitAmount = split.reduce((sum, item) => sum + (item.amount || 0), 0);
      if (Math.abs(totalSplitAmount - amount) > 0.01) {
        return res.status(400).json({ error: `Split amounts (${totalSplitAmount}) must sum to total amount (${amount})` });
      }

      splitArr = await Promise.all(split.map(async splitItem => {
        const member = await User.findOne({ email: splitItem.user });
        if (!member) throw new Error(`Member with email ${splitItem.user} not found`);
        if (splitItem.amount <= 0) throw new Error(`Amount for ${splitItem.user} must be greater than 0`);
        return { user: member._id, amount: splitItem.amount };
      }));
    } else {
      return res.status(400).json({ error: 'Invalid split type' });
    }

    const expenseData = {
      description,
      amount,
      addedBy: addedByEmail,
      date: date ? new Date(date) : new Date(),
      selectedMembers,
      split: splitArr
    };

    group.expenses.push(expenseData);

    splitArr.forEach(s => {
      const bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (bal) bal.balance += s.amount;
    });
    const payerBal = group.balances.find(b => b.user.toString() === addedByUser._id.toString());
    if (payerBal) payerBal.balance -= amount;

    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({ group: groupObj });
  } catch (error) {
    console.error('Error adding expense to group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

// Update expense in group (for admin)
const updateExpenseInGroup = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;
    const { description, amount, selectedMembers, splitType, customSplitAmounts, date, addedByEmail } = req.body;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const expenseIndex = group.expenses.findIndex(e => e._id.toString() === expenseId);
    if (expenseIndex === -1) return res.status(404).json({ error: 'Expense not found' });

    const expense = group.expenses[expenseIndex];

    const addedByUser = await User.findOne({ email: addedByEmail });
    if (!addedByUser) return res.status(404).json({ error: 'User who added expense not found' });

    if (!description || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Description and valid amount are required' });
    }

    const activeMembers = group.members.filter(m => !m.leftAt);
    const activeMemberEmails = await Promise.all(activeMembers.map(async m => {
      const user = await User.findById(m.user);
      return user ? user.email : null;
    })).then(emails => emails.filter(email => email !== null));

    const invalidMembers = selectedMembers.filter(email => !activeMemberEmails.includes(email));
    if (invalidMembers.length > 0) {
      return res.status(400).json({ 
        error: `Cannot include members who have left the group: ${invalidMembers.join(', ')}` 
      });
    }

    // Remove old expense from balances
    const oldAmount = expense.amount;
    const oldPayer = expense.addedBy
      ? await User.findOne({ email: expense.addedBy }).select('_id')
      : null;
    const oldSplit = expense.split;

    oldSplit.forEach(s => {
      const bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (bal) bal.balance -= s.amount;
    });
    const oldPayerBal = oldPayer
      ? group.balances.find(b => b.user.toString() === oldPayer._id.toString())
      : null;
    if (oldPayerBal) oldPayerBal.balance += oldAmount;

    let splitArr = [];
    if (splitType === 'equal') {
      const per = parseFloat((amount / selectedMembers.length).toFixed(2));
      let total = per * selectedMembers.length;
      let diff = parseFloat((amount - total).toFixed(2));

      splitArr = await Promise.all(selectedMembers.map(async (email, i) => {
        const member = await User.findOne({ email });
        return { user: member._id, amount: per + (i === 0 ? diff : 0) };
      }));
    } else if (splitType === 'custom') {
      if (!customSplitAmounts) {
        return res.status(400).json({ error: 'Custom split amounts are required for custom split type' });
      }

      splitArr = await Promise.all(selectedMembers.map(async memberEmail => {
        const member = await User.findOne({ email: memberEmail });
        if (!member) throw new Error(`Member with email ${memberEmail} not found`);
        const customAmount = customSplitAmounts[memberEmail] || 0;
        return { user: member._id, amount: customAmount };
      }));

      const totalSplitAmount = splitArr.reduce((sum, item) => sum + (item.amount || 0), 0);
      if (Math.abs(totalSplitAmount - amount) > 0.01) {
        return res.status(400).json({ error: `Split amounts (${totalSplitAmount}) must sum to total amount (${amount})` });
      }
    } else {
      return res.status(400).json({ error: 'Invalid split type' });
    }

    expense.description = description;
    expense.amount = amount;
    expense.addedBy = addedByEmail;
    expense.date = date ? new Date(date) : new Date();
    expense.selectedMembers = selectedMembers;
    expense.split = splitArr;

    splitArr.forEach(s => {
      const bal = group.balances.find(b => b.user.toString() === s.user.toString());
      if (bal) bal.balance += s.amount;
    });
    const newPayerBal = group.balances.find(b => b.user.toString() === addedByUser._id.toString());
    if (newPayerBal) newPayerBal.balance -= amount;

    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({ group: groupObj });
  } catch (error) {
    console.error('Error updating expense in group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

// Delete expense from group (for admin)
const deleteExpenseFromGroup = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const expenseIndex = group.expenses.findIndex(e => e._id.toString() === expenseId);
    if (expenseIndex === -1) return res.status(404).json({ error: 'Expense not found' });

    const expense = group.expenses[expenseIndex];
    const payer = expense?.addedBy
      ? await User.findOne({ email: expense.addedBy }).select('_id')
      : null;

    for (const splitItem of expense.split || []) {
      const balanceEntry = group.balances.find(
        b => b.user.toString() === splitItem.user.toString()
      );
      if (balanceEntry) {
        balanceEntry.balance -= Number(splitItem.amount || 0);
      }
    }

    if (payer) {
      const payerBalance = group.balances.find(
        b => b.user.toString() === payer._id.toString()
      );
      if (payerBalance) {
        payerBalance.balance += Number(expense.amount || 0);
      }
    }

    group.expenses.splice(expenseIndex, 1);
    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    res.json({ group: groupObj });
  } catch (error) {
    console.error('Error deleting expense from group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

// Settle expense splits in group (for admin)
const settleExpenseSplitsInGroup = async (req, res) => {
  try {
    const { groupId, expenseId } = req.params;
    const { memberEmails } = req.body;

    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });
    await rebuildGroupBalances(group);

    const expense = group.expenses.id(expenseId);
    if (!expense) return res.status(404).json({ error: 'Expense not found' });

    let settledCount = 0;
    let alreadySettledCount = 0;
    let alreadySettledMembers = [];

    for (let splitItem of expense.split) {
      const member = await User.findById(splitItem.user);
      if (member && memberEmails.includes(member.email)) {
        if (splitItem.settled) {
          alreadySettledCount++;
          alreadySettledMembers.push(member.email);
          continue;
        }
        splitItem.settled = true;
        splitItem.settledAt = new Date();
        splitItem.settledBy = req.user.email; // Admin's email
        settledCount++;
      }
    }

    if (settledCount === 0) {
      if (alreadySettledCount > 0) {
        return res.status(400).json({ 
          error: `All selected members are already settled: ${alreadySettledMembers.join(', ')}` 
        });
      }
      return res.status(400).json({ error: 'No valid splits found to settle' });
    }

    await group.save();

    const populatedGroup = await GroupTransaction.findById(group._id)
      .populate('members.user', 'email')
      .populate('creator', 'email');
    if (await rebuildGroupBalances(populatedGroup)) {
      await populatedGroup.save();
    }
    const groupObj = formatAdminGroupResponse(populatedGroup);

    let message = `Successfully settled ${settledCount} split(s) in expense`;
    if (alreadySettledCount > 0) {
      message += `. ${alreadySettledCount} member(s) were already settled: ${alreadySettledMembers.join(', ')}`;
    }

    res.json({
      group: groupObj,
      message: message,
      settledCount: settledCount,
      alreadySettledCount: alreadySettledCount,
      alreadySettledMembers: alreadySettledMembers
    });
  } catch (error) {
    console.error('Error settling expense splits in group:', error);
    res.status(500).json({ error: 'Server error' });
  }
};

const getSystemStats = async (req, res) => {
  try {
    const [userCount, adminCount, transactionCount, supportQueryCount, activityCount] = await Promise.all([
      User.countDocuments(),
      Admin.countDocuments(),
      Transaction.countDocuments(),
      SupportQuery.countDocuments(),
      Activity.countDocuments(),
    ]);
    res.json({
      users: userCount,
      admins: adminCount,
      transactions: transactionCount,
      supportQueries: supportQueryCount,
      activities: activityCount,
      serverTime: new Date().toISOString(),
      uptimeSeconds: Math.floor(process.uptime()),
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch system stats' });
  }
};

const exportAdminData = async (req, res) => {
  try {
    const type = req.query.type || 'users';
    const esc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;
    if (type === 'users') {
      const users = await User.find({}).select('name username email gender createdAt').lean();
      const header = 'Name,Username,Email,Gender,Joined\n';
      const rows = users.map(u =>
        [u.name, u.username, u.email, u.gender, u.createdAt?.toISOString().split('T')[0]].map(esc).join(',')
      ).join('\n');
      res.setHeader('Content-Type', 'text/csv');
      return res.send(header + rows);
    }
    if (type === 'transactions') {
      const txns = await Transaction.find({}).select('transactionId userEmail counterpartyEmail role amount currency place description date').lean();
      const header = 'Transaction ID,User Email,Counterparty Email,Role,Amount,Currency,Place,Description,Date\n';
      const rows = txns.map(t =>
        [t.transactionId ?? t._id, t.userEmail, t.counterpartyEmail, t.role, t.amount, t.currency, t.place, t.description, t.date ? new Date(t.date).toISOString().split('T')[0] : ''].map(esc).join(',')
      ).join('\n');
      res.setHeader('Content-Type', 'text/csv');
      return res.send(header + rows);
    }
    if (type === 'quick_transactions') {
      const txns = await QuickTransaction.find({}).select('amount currency date creatorEmail role description users cleared settlementStatus').lean();
      const header = 'ID,Creator Email,Participants,Role,Amount,Currency,Description,Date,Cleared,Settlement Status\n';
      const rows = txns.map(t =>
        [t._id, t.creatorEmail, (t.users || []).join(';'), t.role, t.amount, t.currency, t.description, t.date ? new Date(t.date).toISOString().split('T')[0] : '', t.cleared ? 'Yes' : 'No', t.settlementStatus].map(esc).join(',')
      ).join('\n');
      res.setHeader('Content-Type', 'text/csv');
      return res.send(header + rows);
    }
    if (type === 'group_transactions') {
      const groups = await GroupTransaction.find({}).populate('creator', 'email').lean();
      const rows = [];
      for (const g of groups) {
        if (!g.expenses || g.expenses.length === 0) {
          rows.push([g._id, g.title, g.creator?.email ?? '', '(no expenses)', '', '', '', '', g.isActive ? 'Active' : 'Inactive'].map(esc).join(','));
        } else {
          for (const exp of g.expenses) {
            rows.push([g._id, g.title, g.creator?.email ?? '', exp.description, exp.amount, exp.currency, exp.addedBy, exp.date ? new Date(exp.date).toISOString().split('T')[0] : '', g.isActive ? 'Active' : 'Inactive'].map(esc).join(','));
          }
        }
      }
      const header = 'Group ID,Group Title,Creator,Expense Description,Amount,Currency,Added By,Date,Status\n';
      res.setHeader('Content-Type', 'text/csv');
      return res.send(header + rows.join('\n'));
    }
    if (type === 'support') {
      const queries = await SupportQuery.find({}).populate('user', 'email').lean();
      const header = 'ID,User,Topic,Status,Priority,Created\n';
      const rows = queries.map(q =>
        [q._id, q.user?.email, q.topic, q.status, q.priority, q.createdAt?.toISOString().split('T')[0]].map(esc).join(',')
      ).join('\n');
      res.setHeader('Content-Type', 'text/csv');
      return res.send(header + rows);
    }
    res.status(400).json({ error: 'Invalid export type. Use: users, transactions, support' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to export data' });
  }
};

const performMaintenance = async (req, res) => {
  try {
    const { action } = req.body;
    if (action === 'clear_old_queries') {
      const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      const result = await SupportQuery.deleteMany({ createdAt: { $lt: sevenDaysAgo }, status: { $in: ['resolved', 'closed'] } });
      return res.json({ message: `Cleared ${result.deletedCount} old resolved/closed queries` });
    }
    if (action === 'clear_old_activities') {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);
      const result = await Activity.deleteMany({ createdAt: { $lt: thirtyDaysAgo } });
      return res.json({ message: `Cleared ${result.deletedCount} old activity records` });
    }
    if (action === 'clear_old_audit_logs') {
      const ninetyDaysAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
      const result = await AdminAuditLog.deleteMany({ createdAt: { $lt: ninetyDaysAgo } });
      return res.json({ message: `Cleared ${result.deletedCount} old audit log records` });
    }
    res.status(400).json({ error: 'Invalid action. Use: clear_old_queries, clear_old_activities, clear_old_audit_logs' });
  } catch (error) {
    res.status(500).json({ error: 'Maintenance action failed' });
  }
};

// Get all quick transactions (for admin)
const getAllQuickTransactions = async (req, res) => {
  try {
    const {
      page = 1,
      limit = 100,
      sortBy = 'createdAt',
      order = 'desc',
      search,
      cleared,
      settlementStatus,
    } = req.query;
    const sortDir = order === 'asc' ? 1 : -1;

    const query = {};
    if (search && search.trim()) {
      const searchRegex = new RegExp(
        search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'),
        'i'
      );
      query.$or = [
        { creatorEmail: searchRegex },
        { description: searchRegex },
        { users: searchRegex },
      ];
    }
    if (cleared === 'true') query.cleared = true;
    else if (cleared === 'false') query.cleared = false;
    if (settlementStatus && settlementStatus !== 'all') {
      query.settlementStatus = settlementStatus;
    }

    const allowedSortFields = ['createdAt', 'amount', 'date'];
    const sortField = allowedSortFields.includes(sortBy) ? sortBy : 'createdAt';

    const transactions = await QuickTransaction.find(query)
      .sort({ [sortField]: sortDir })
      .skip((page - 1) * limit)
      .limit(parseInt(limit));

    const total = await QuickTransaction.countDocuments(query);

    res.json({
      success: true,
      transactions,
      totalPages: Math.ceil(total / limit),
      currentPage: parseInt(page),
      total,
    });
  } catch (error) {
    console.error('Error fetching quick transactions:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch quick transactions' });
  }
};

// Update a quick transaction (for admin)
const updateAdminQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const { amount, currency, description, cleared, settlementStatus, role } = req.body;

    const updateData = {};
    if (amount !== undefined) updateData.amount = amount;
    if (currency !== undefined) updateData.currency = currency;
    if (description !== undefined) updateData.description = description;
    if (cleared !== undefined) updateData.cleared = cleared;
    if (settlementStatus !== undefined) updateData.settlementStatus = settlementStatus;
    if (role !== undefined) updateData.role = role;

    const transaction = await QuickTransaction.findByIdAndUpdate(id, updateData, { new: true });
    if (!transaction) {
      return res.status(404).json({ success: false, message: 'Quick transaction not found' });
    }

    res.json({ success: true, message: 'Quick transaction updated successfully', transaction });
  } catch (error) {
    console.error('Error updating quick transaction:', error);
    res.status(500).json({ success: false, message: 'Failed to update quick transaction' });
  }
};

// Delete a quick transaction (for admin)
const deleteAdminQuickTransaction = async (req, res) => {
  try {
    const { id } = req.params;
    const transaction = await QuickTransaction.findByIdAndDelete(id);
    if (!transaction) {
      return res.status(404).json({ success: false, message: 'Quick transaction not found' });
    }
    res.json({ success: true, message: 'Quick transaction deleted successfully' });
  } catch (error) {
    console.error('Error deleting quick transaction:', error);
    res.status(500).json({ success: false, message: 'Failed to delete quick transaction' });
  }
};

module.exports = {
  register,
  getDashboardSummary,
  getAllUsers,
  exportUsers,
  clearPendingUsers,
  reviewPendingUser,
  addAdminNoteToUser,
  updateUserSuspension,
  forceLogoutUser,
  getUserDetails,
  bulkUpdateUserStatus,
  updateUserStatus,
  updateUser,
  deleteUser,
  getSystemSettings,
  updateSystemSettings,
  getAnalyticsSettings,
  updateAnalyticsSettings,
  getSecuritySettings,
  updateSecuritySettings,
  getNotificationSettings,
  updateNotificationSettings,
  getAllAdmins,
  getAdminAuditLogs,
  addAdmin,
  removeAdmin,
  updateAdminPermissions,
  toggleSuperAdminStatus,
  getAllGroupTransactions,
  updateGroupTransaction,
  deleteGroupTransaction,
  addMemberToGroup,
  removeMemberFromGroup,
  addExpenseToGroup,
  updateExpenseInGroup,
  deleteExpenseFromGroup,
  settleExpenseSplitsInGroup,
  getAllQuickTransactions,
  updateAdminQuickTransaction,
  deleteAdminQuickTransaction,
  getSystemStats,
  exportAdminData,
  performMaintenance,
};
