const mongoose = require('mongoose');

const notificationSchema = new mongoose.Schema({
  sender: {
    type: mongoose.Schema.Types.ObjectId,
    refPath: 'senderModel',
    required: true,
  },
  senderModel: {
    type: String,
    required: true,
    enum: ['User', 'Admin'],
  },
  recipientType: {
    type: String,
    enum: ['all-users', 'all-admins', 'specific-users', 'specific-admins'],
    required: true,
  },
  recipients: [
    {
      type: mongoose.Schema.Types.ObjectId,
      refPath: 'recipientModel',
    },
  ],
  recipientModel: {
    type: String,
    required: true,
    enum: ['User', 'Admin'],
  },
  message: {
    type: String,
    required: true,
  },
  title: {
    type: String,
    default: '',
  },
  category: {
    type: String,
    default: 'general',
    enum: ['general', 'friend', 'offer', 'transaction', 'group', 'community', 'system', 'subscription', 'update'],
  },
  deliveryStatus: {
    type: String,
    enum: ['sent', 'draft', 'scheduled'],
    default: 'sent',
    index: true,
  },
  scheduledFor: {
    type: Date,
    default: null,
    index: true,
  },
  sentAt: {
    type: Date,
    default: null,
  },
  estimatedAudience: {
    type: Number,
    default: 0,
  },
  metadata: {
    type: mongoose.Schema.Types.Mixed,
    default: {},
  },
  readBy: [{
    type: mongoose.Schema.Types.ObjectId,
    refPath: 'recipientModel'
  }],
  createdAt: {
    type: Date,
    default: Date.now,
    expires: '7d', // Notifications will be automatically deleted after 7 days
  },
});

// Primary user inbox query: recipients + deliveryStatus
notificationSchema.index({ recipients: 1, deliveryStatus: 1, createdAt: -1 });
// readBy is a second array — cannot compound-index two arrays together (MongoDB restriction).
// The inbox query filters by readBy in-memory after the recipients+deliveryStatus index reduces the set.
// Admin sent-notifications list
notificationSchema.index({ sender: 1, deliveryStatus: 1, createdAt: -1 });
// Scheduled dispatch: find due scheduled notifications
notificationSchema.index({ deliveryStatus: 1, scheduledFor: 1 });

module.exports = mongoose.model('Notification', notificationSchema);
