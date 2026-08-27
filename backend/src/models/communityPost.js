const mongoose = require('mongoose');

const commentSchema = new mongoose.Schema({
  author: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  text:   { type: String, required: true, maxlength: 500, trim: true },
  createdAt: { type: Date, default: Date.now },
}, { _id: true });

const pollOptionSchema = new mongoose.Schema({
  text:  { type: String, required: true, maxlength: 200, trim: true },
  votes: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
}, { _id: true });

const communityPostSchema = new mongoose.Schema({
  community: { type: mongoose.Schema.Types.ObjectId, ref: 'Community', required: true, index: true },
  author:    { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  text:      { type: String, required: true, maxlength: 1000, trim: true },
  type:      { type: String, enum: ['text', 'announcement', 'reminder', 'poll'], default: 'text' },
  isPinned:  { type: Boolean, default: false },
  // reminder fields
  dueDate:   { type: Date },
  amount:    { type: Number, min: 0 },
  // poll fields
  poll:      { options: [pollOptionSchema] },
  likes:     [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  comments:  [commentSchema],
}, { timestamps: true });

module.exports = mongoose.model('CommunityPost', communityPostSchema);
