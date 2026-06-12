const mongoose = require('mongoose');

const contactMessageSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true, maxlength: 100 },
  email: { type: String, required: true, trim: true, lowercase: true },
  subject: { type: String, trim: true, default: 'General Inquiry', maxlength: 200 },
  message: { type: String, required: true, trim: true, maxlength: 2000 },
  status: {
    type: String,
    enum: ['new', 'read', 'replied', 'closed'],
    default: 'new',
    index: true,
  },
  userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },
  userEmail: { type: String, default: null },
  ipAddress: { type: String, default: null },
  repliedAt: { type: Date, default: null },
  replyNote: { type: String, default: '' },
}, { timestamps: true });

contactMessageSchema.index({ status: 1, createdAt: -1 });
contactMessageSchema.index({ email: 1 });

module.exports = mongoose.model('ContactMessage', contactMessageSchema);
