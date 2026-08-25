const mongoose = require('mongoose');
const crypto = require('crypto');

const memberSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  role: { type: String, enum: ['admin', 'member'], default: 'member' },
  joinedAt: { type: Date, default: Date.now },
  invitedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
}, { _id: false });

const pendingInviteSchema = new mongoose.Schema({
  email: { type: String, required: true, lowercase: true, trim: true },
  invitedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  invitedAt: { type: Date, default: Date.now },
}, { _id: false });

const communitySchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true, maxlength: 80 },
  description: { type: String, trim: true, default: '', maxlength: 300 },
  color: { type: String, default: '#00B4D8' },
  communityImage: { type: Buffer, default: null },
  communityImageMimeType: { type: String, default: '' },
  creator: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  members: [memberSchema],
  groups: [{ type: mongoose.Schema.Types.ObjectId, ref: 'GroupTransaction' }],
  pendingInvites: [pendingInviteSchema],
  inviteCode: { type: String, unique: true, sparse: true },
  privacy: { type: String, enum: ['private', 'invite_only'], default: 'invite_only' },
  settings: {
    membersCanCreateGroups: { type: Boolean, default: false },
    requireAdminApproval: { type: Boolean, default: false },
    allowDirectAdd: { type: Boolean, default: true },
  },
}, { timestamps: true });

communitySchema.pre('save', function (next) {
  if (!this.inviteCode) {
    this.inviteCode = crypto.randomBytes(3).toString('hex').toUpperCase();
  }
  next();
});

communitySchema.index({ 'members.user': 1 });
communitySchema.index({ creator: 1 });
communitySchema.index({ inviteCode: 1 });

module.exports = mongoose.model('Community', communitySchema);
