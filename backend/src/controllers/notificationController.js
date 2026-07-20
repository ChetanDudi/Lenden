const Notification = require('../models/notification');
const User = require('../models/user');
const Admin = require('../models/admin');

const ADMIN_PERMISSION_DEFAULTS = {
  canManageUsers: true,
  canManageTransactions: true,
  canManageSupport: true,
  canManageContent: true,
  canManageDigitise: true,
  canManageSettings: true,
  canViewAuditLogs: true,
};

const normalizePermissions = (permissions = {}) => {
  const normalized = {};
  for (const [key, value] of Object.entries(ADMIN_PERMISSION_DEFAULTS)) {
    normalized[key] = permissions[key] !== false ? value : false;
  }
  return normalized;
};

const getCurrentAdmin = async (req) => {
  if (req.user?.role !== 'admin') return null;

  const adminId = req.user?._id || req.user?.userId || req.user?.id;
  let admin = null;

  if (adminId) {
    admin = await Admin.findById(adminId)
      .select('_id email isSuperAdmin permissions')
      .lean();
  }
  if (!admin && req.user?.email) {
    admin = await Admin.findOne({ email: req.user.email })
      .select('_id email isSuperAdmin permissions')
      .lean();
  }

  return admin;
};

const hasNotificationPermission = (admin) =>
  !!admin &&
  (admin.isSuperAdmin === true ||
    normalizePermissions(admin.permissions || {}).canManageSettings === true ||
    normalizePermissions(admin.permissions || {}).canManageContent === true);

const resolveRecipients = async ({ recipientType, recipients = [], requirePush = false }) => {
  let recipientIds = [];
  let recipientModel;
  let invalidRecipients = [];

  const pushFilter = requirePush
    ? { 'notificationSettings.pushNotifications': true }
    : {};

  if (recipientType === 'all-users') {
    const users = await User.find(pushFilter, '_id');
    recipientIds = users.map((user) => user._id);
    recipientModel = 'User';
  } else if (recipientType === 'all-admins') {
    const admins = await Admin.find(pushFilter, '_id');
    recipientIds = admins.map((admin) => admin._id);
    recipientModel = 'Admin';
  } else if (recipientType === 'specific-users') {
    const users = await User.find(
      {
        $or: [{ username: { $in: recipients } }, { email: { $in: recipients } }],
        ...pushFilter,
      },
      'username email _id'
    );
    recipientIds = users.map((user) => user._id);
    recipientModel = 'User';

    const foundUsernames = users.map((user) => user.username);
    const foundEmails = users.map((user) => user.email);
    invalidRecipients = recipients.filter(
      (rec) => !foundUsernames.includes(rec) && !foundEmails.includes(rec)
    );
  } else if (recipientType === 'specific-admins') {
    const admins = await Admin.find(
      {
        $or: [{ username: { $in: recipients } }, { email: { $in: recipients } }],
        ...pushFilter,
      },
      'username email _id'
    );
    recipientIds = admins.map((admin) => admin._id);
    recipientModel = 'Admin';

    const foundAdminUsernames = admins.map((admin) => admin.username);
    const foundAdminEmails = admins.map((admin) => admin.email);
    invalidRecipients = recipients.filter(
      (rec) => !foundAdminUsernames.includes(rec) && !foundAdminEmails.includes(rec)
    );
  }

  return {
    recipientIds,
    recipientModel,
    invalidRecipients,
    estimatedAudience: recipientIds.length,
  };
};

const dispatchDueScheduledNotifications = async () => {
  const dueNotifications = await Notification.find({
    deliveryStatus: 'scheduled',
    scheduledFor: { $lte: new Date() },
  });
  if (!dueNotifications.length) return;

  for (const notification of dueNotifications) {
    notification.deliveryStatus = 'sent';
    notification.sentAt = new Date();
    await notification.save();
  }
};

const canManageNotification = (notification, req, currentAdmin) => {
  if (!notification || !req.user) return false;
  const requesterId = (req.user._id || req.user.userId || req.user.id)?.toString();
  if (notification.sender?.toString() === requesterId) return true;
  return req.user.role === 'admin' && currentAdmin?.isSuperAdmin === true;
};

function inferNotificationCategory(message = '', recipientType = '') {
  const text = `${message} ${recipientType}`.toLowerCase();

  if (text.includes('friend')) return 'friend';
  if (text.includes('offer')) return 'offer';
  if (
    text.includes('group') ||
    text.includes('split') ||
    text.includes('expense')
  ) {
    return 'group';
  }
  if (
    text.includes('transaction') ||
    text.includes('payment') ||
    text.includes('borrow') ||
    text.includes('lend') ||
    text.includes('due') ||
    text.includes('reminder')
  ) {
    return 'transaction';
  }
  if (
    text.includes('admin') ||
    text.includes('system') ||
    text.includes('alert') ||
    text.includes('security') ||
    text.includes('maintenance')
  ) {
    return 'system';
  }
  return 'general';
}

exports.createNotification = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (req.user.role === 'admin' && !hasNotificationPermission(currentAdmin)) {
      return res.status(403).json({ message: 'You do not have permission to manage notifications' });
    }

    const {
      title,
      message,
      recipientType,
      recipients,
      category,
      deliveryStatus,
      scheduledFor,
    } = req.body;
    const sender = req.user._id;
    const senderModel = req.user.role === 'admin' ? 'Admin' : 'User';
    const safeRecipients = Array.isArray(recipients) ? recipients : [];
    const {
      recipientIds,
      recipientModel,
      invalidRecipients,
      estimatedAudience,
    } = await resolveRecipients({
      recipientType,
      recipients: safeRecipients,
      requirePush: true,
    });

    if (invalidRecipients.length > 0) {
        return res.status(400).json({ message: `The following recipients were not found: ${invalidRecipients.join(', ')}` });
    }

    if ((recipientType === 'specific-users' || recipientType === 'specific-admins') && recipientIds.length === 0 && safeRecipients.length > 0) {
        return res.status(400).json({ message: 'No valid recipients found for the specified type among the provided list.' });
    }

    const normalizedDeliveryStatus =
      ['draft', 'scheduled', 'sent'].includes((deliveryStatus || '').toString())
        ? deliveryStatus
        : 'sent';
    const parsedSchedule =
      normalizedDeliveryStatus === 'scheduled' && scheduledFor
        ? new Date(scheduledFor)
        : null;
    if (normalizedDeliveryStatus === 'scheduled' && (!parsedSchedule || Number.isNaN(parsedSchedule.getTime()))) {
      return res.status(400).json({ message: 'scheduledFor must be a valid future date' });
    }

    const notification = new Notification({
      sender,
      senderModel,
      recipientType,
      recipients: recipientIds,
      recipientModel,
      title: (title || '').toString().trim(),
      message,
      category: category || inferNotificationCategory(message, recipientType),
      deliveryStatus: normalizedDeliveryStatus,
      scheduledFor: normalizedDeliveryStatus === 'scheduled' ? parsedSchedule : null,
      sentAt: normalizedDeliveryStatus === 'sent' ? new Date() : null,
      estimatedAudience,
    });

    await notification.save();

    res.status(201).json({
      message:
        normalizedDeliveryStatus === 'scheduled'
          ? 'Notification scheduled successfully'
          : normalizedDeliveryStatus === 'draft'
              ? 'Notification draft saved successfully'
              : 'Notification sent successfully',
      notification,
    });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getNotifications = async (req, res) => {
    try {
        await dispatchDueScheduledNotifications();
        const { viewAll } = req.query;
        const userId = req.user._id;
        const userRole = req.user.role;

        // pushNotifications=false should stop NEW notifications from being created,
        // not hide the existing inbox — users must always be able to read stored alerts.

        let query;

        if (userRole === 'user') {
            query = Notification.find({
                recipientModel: 'User',
                recipients: { $in: [userId] },
                deliveryStatus: 'sent',
            })
            .populate({
                path: 'recipients',
                select: 'username email',
            })
            .populate('readBy', 'username email')
            .sort({ createdAt: -1 });
        } else if (userRole === 'admin') {
            query = Notification.find({
                $or: [
                    { recipientType: 'all-admins', recipientModel: 'Admin' },
                    { recipientType: 'specific-admins', recipientModel: 'Admin', recipients: userId },
                    { sender: userId, deliveryStatus: 'sent' }
                ],
                deliveryStatus: 'sent',
            })
            .populate({
                path: 'recipients',
                select: 'username email',
            })
            .populate('readBy', 'username email')
            .sort({ createdAt: -1 });
        }

        if (viewAll !== 'true') {
            query = query.limit(3);
        }

        const notifications = await query;
        res.json(notifications);
    } catch (error) {
        res.status(500).json({ message: 'Server error' });
    }
};


exports.getSentNotifications = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (req.user.role === 'admin' && !hasNotificationPermission(currentAdmin)) {
      return res.status(403).json({ message: 'You do not have permission to manage notifications' });
    }
    await dispatchDueScheduledNotifications();
    const { viewAll } = req.query;

    let query = Notification.find({ sender: req.user._id })
      .populate({
        path: 'recipients',
        select: 'username email',
      })
      .sort({ createdAt: -1 });

    if (viewAll !== 'true') {
      query = query.limit(3);
    }

    const notifications = await query;
    res.json(notifications);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getNotificationById = async (req, res) => {
  try {
    const notificationId = req.params.id;
    const notification = await Notification.findById(notificationId)
      .populate({
        path: 'recipients',
        select: 'username email',
      });

    if (!notification) {
      return res.status(404).json({ message: 'Notification not found' });
    }

    res.status(200).json(notification);
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.deleteNotification = async (req, res) => {
  try {
    const notificationId = req.params.id;
    const currentAdmin = await getCurrentAdmin(req);

    const notification = await Notification.findById(notificationId);

    if (!notification) {
      return res.status(404).json({ message: 'Notification not found' });
    }

    // Check if the authenticated user is the sender of the notification
    if (!canManageNotification(notification, req, currentAdmin)) {
      return res.status(403).json({ message: 'Unauthorized: You can only delete your own notifications' });
    }

    await notification.deleteOne(); // Use deleteOne() for Mongoose 6+

    res.status(200).json({ message: 'Notification deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.updateNotification = async (req, res) => {
  try {
    const notificationId = req.params.id;
    const currentAdmin = await getCurrentAdmin(req);
    if (req.user.role === 'admin' && !hasNotificationPermission(currentAdmin)) {
      return res.status(403).json({ message: 'You do not have permission to manage notifications' });
    }
    const { title, message, recipientType, recipients, category, deliveryStatus, scheduledFor } = req.body;

    const notification = await Notification.findById(notificationId);

    if (!notification) {
      return res.status(404).json({ message: 'Notification not found' });
    }

    // Check if the authenticated user is the sender of the notification
    if (!canManageNotification(notification, req, currentAdmin)) {
      return res.status(403).json({ message: 'Unauthorized: You can only edit your own notifications' });
    }

    // Update fields
    notification.title = title ?? notification.title;
    notification.message = message || notification.message;
    notification.recipientType = recipientType || notification.recipientType;
    notification.category =
      category ||
      inferNotificationCategory(
        message || notification.message,
        recipientType || notification.recipientType
      );

    // Handle recipients update if provided
    if (recipients) {
      const {
        recipientIds,
        recipientModel,
        invalidRecipients,
        estimatedAudience,
      } = await resolveRecipients({
        recipientType: recipientType || notification.recipientType,
        recipients,
      });

      if (invalidRecipients.length > 0) {
          return res.status(400).json({ message: `The following recipients were not found: ${invalidRecipients.join(', ')}` });
      }

      if ((recipientType === 'specific-users' || recipientType === 'specific-admins') && recipientIds.length === 0 && recipients.length > 0) {
          return res.status(400).json({ message: 'No valid recipients found for the specified type among the provided list.' });
      }

      notification.recipients = recipientIds;
      notification.recipientModel = recipientModel;
      notification.estimatedAudience = estimatedAudience;
    }

    if (deliveryStatus && ['sent', 'draft', 'scheduled'].includes(deliveryStatus)) {
      notification.deliveryStatus = deliveryStatus;
      if (deliveryStatus === 'scheduled') {
        const parsed = new Date(scheduledFor);
        if (Number.isNaN(parsed.getTime())) {
          return res.status(400).json({ message: 'scheduledFor must be a valid future date' });
        }
        notification.scheduledFor = parsed;
        notification.sentAt = null;
      } else if (deliveryStatus === 'sent') {
        notification.sentAt = new Date();
        notification.scheduledFor = null;
      } else {
        notification.scheduledFor = null;
      }
    }

    await notification.save();

    res.status(200).json({ message: 'Notification updated successfully', notification });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getUnreadNotificationCount = async (req, res) => {
  try {
    const userId = req.user._id;
    const count = await Notification.countDocuments({
      recipients: userId,
      deliveryStatus: 'sent',
      readBy: { $ne: userId }
    });
    res.json({ count });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.markNotificationsAsRead = async (req, res) => {
  try {
    const userId = req.user._id;
    await Notification.updateMany(
      { recipients: userId, deliveryStatus: 'sent', readBy: { $ne: userId } },
      { $addToSet: { readBy: userId } }
    );
    res.status(200).json({ message: 'Notifications marked as read' });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.clearReadNotifications = async (req, res) => {
  try {
    const userId = req.user._id;
    // Pull the user out of recipients on every notification they've already read.
    // When recipients becomes empty the notification is effectively dead for everyone,
    // so delete those rows entirely to avoid orphan documents building up.
    await Notification.updateMany(
      { recipients: userId, readBy: userId },
      { $pull: { recipients: userId } }
    );
    await Notification.deleteMany({ recipients: { $size: 0 } });
    res.status(200).json({ message: 'Read notifications cleared' });
  } catch (error) {
    res.status(500).json({ message: 'Server error' });
  }
};

exports.getAudiencePreview = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    if (!hasNotificationPermission(currentAdmin)) {
      return res.status(403).json({ message: 'You do not have permission to manage notifications' });
    }
    const recipientType = (req.query.recipientType || 'all-users').toString();
    const recipients = (req.query.recipients || '')
      .toString()
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);

    const { estimatedAudience, invalidRecipients, recipientModel } =
      await resolveRecipients({
        recipientType,
        recipients,
        requirePush: true,
      });

    return res.json({
      estimatedAudience,
      invalidRecipients,
      recipientModel,
      recipientType,
    });
  } catch (error) {
    return res.status(500).json({ message: 'Server error' });
  }
};
