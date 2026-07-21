const mongoose = require('mongoose');

const replySchema = new mongoose.Schema({
  admin: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    required: true,
  },
  replyText: {
    type: String,
    required: true,
  },
  timestamp: {
    type: Date,
    default: Date.now,
  },
});

const supportQuerySchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
  },
  topic: {
    type: String,
    required: true,
    trim: true,
  },
  description: {
    type: String,
    required: true,
    trim: true,
  },
  status: {
    type: String,
    enum: ['open', 'in_progress', 'resolved', 'closed'],
    default: 'open',
  },
  priority: {
    type: String,
    enum: ['low', 'normal', 'high', 'critical'],
    default: 'normal',
    index: true,
  },
  assignedAdmin: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    default: null,
    index: true,
  },
  firstAdminReplyAt: {
    type: Date,
    default: null,
  },
  lastAdminReplyAt: {
    type: Date,
    default: null,
  },
  resolvedAt: {
    type: Date,
    default: null,
  },
  internalNotes: [
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
      timestamp: {
        type: Date,
        default: Date.now,
      },
    },
  ],
  replies: [replySchema],
  createdAt: {
    type: Date,
    default: Date.now,
  },
  updatedAt: {
    type: Date,
    default: Date.now,
  },
});

// Update 'updatedAt' field on save
supportQuerySchema.pre('save', function (next) {
  this.updatedAt = Date.now();
  next();
});

// User support history (most common user-facing query)
supportQuerySchema.index({ user: 1, createdAt: -1 });
// Admin queue filtered by status
supportQuerySchema.index({ status: 1, createdAt: -1 });
// Admin prioritized queue
supportQuerySchema.index({ status: 1, priority: 1, createdAt: -1 });

module.exports = mongoose.model('SupportQuery', supportQuerySchema);
