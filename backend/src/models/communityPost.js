const mongoose = require('mongoose');

const communityPostSchema = new mongoose.Schema({
  community: { type: mongoose.Schema.Types.ObjectId, ref: 'Community', required: true, index: true },
  author: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  text: { type: String, required: true, maxlength: 1000, trim: true },
}, { timestamps: true });

module.exports = mongoose.model('CommunityPost', communityPostSchema);
