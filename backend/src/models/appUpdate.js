const mongoose = require('mongoose');

const appUpdateSchema = new mongoose.Schema(
  {
    title: {
      type: String,
      required: true,
      trim: true,
    },
    body: {
      type: String,
      required: true,
      trim: true,
    },
    summary: {
      type: String,
      default: '',
      trim: true,
    },
    versionTag: {
      type: String,
      default: '',
      trim: true,
    },
    category: {
      type: String,
      enum: ['general', 'feature', 'bug_fix', 'security', 'maintenance'],
      default: 'general',
      index: true,
    },
    importance: {
      type: String,
      enum: ['normal', 'important', 'critical'],
      default: 'normal',
      index: true,
    },
    targetAudience: {
      type: String,
      enum: ['all', 'subscribed', 'nonsubscribed'],
      default: 'all',
      index: true,
    },
    platforms: {
      type: [String],
      default: ['all'],
    },
    tags: {
      type: [String],
      default: [],
    },
    status: {
      type: String,
      enum: ['draft', 'published', 'scheduled'],
      default: 'published',
      index: true,
    },
    scheduledFor: {
      type: Date,
      default: null,
      index: true,
    },
    pinned: {
      type: Boolean,
      default: false,
    },
    publishedAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'Admin',
      required: true,
    },
    editHistory: {
      type: [
        {
          editedAt: { type: Date, required: true },
          title: { type: String, default: '' },
          body: { type: String, default: '' },
          summary: { type: String, default: '' },
          versionTag: { type: String, default: '' },
          category: { type: String, default: 'general' },
          importance: { type: String, default: 'normal' },
          tags: { type: [String], default: [] },
          platforms: { type: [String], default: ['all'] },
          targetAudience: { type: String, default: 'all' },
          status: { type: String, default: 'published' },
        },
      ],
      default: [],
    },
  },
  { timestamps: true }
);

appUpdateSchema.index({ pinned: -1, publishedAt: -1, status: 1 });
appUpdateSchema.index({ category: 1, importance: 1, targetAudience: 1 });

module.exports = mongoose.model('AppUpdate', appUpdateSchema);
