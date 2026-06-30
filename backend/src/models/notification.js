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
    enum: ['general', 'friend', 'offer', 'transaction', 'group', 'system', 'subscription'],
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

module.exports = mongoose.model('Notification', notificationSchema);
