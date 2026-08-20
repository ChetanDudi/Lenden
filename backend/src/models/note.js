const mongoose = require('mongoose');

const noteSchema = new mongoose.Schema({
  user: { type: mongoose.Schema.Types.ObjectId, required: true, refPath: 'role' },
  role: { type: String, enum: ['User', 'Admin'], required: true },
  title: { type: String, required: true },
  content: { type: String, required: true },
  isShared: { type: Boolean, default: false },
  sharedFrom: {
    noteId:      { type: mongoose.Schema.Types.ObjectId, ref: 'Note', default: null },
    senderEmail: { type: String, default: null },
    senderName:  { type: String, default: null },
    sharedAt:    { type: Date, default: null },
  },
}, { timestamps: true });

noteSchema.index({ user: 1 });
noteSchema.index({ role: 1 });
noteSchema.index({ title: 1 });
noteSchema.index({ isShared: 1 });

module.exports = mongoose.model('Note', noteSchema); 