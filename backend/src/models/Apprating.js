const mongoose = require('mongoose');

const AppratingSchema = new mongoose.Schema({
  // Reference kept for live users; set to null when account is deleted
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  // Denormalized at submission time so ratings persist after account deletion
  userName: { type: String, default: '' },
  userEmail: { type: String, default: '' },
  username: { type: String, default: '' },
  userDeleted: { type: Boolean, default: false },
  rating: { type: Number, min: 1, max: 5, required: true },
  createdAt: { type: Date, default: Date.now },
});

// Keep one rating per user (null user can have multiple after deletion)
AppratingSchema.index({ user: 1 }, { unique: true, sparse: true });

module.exports = mongoose.model('AppRating', AppratingSchema);
