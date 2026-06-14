const mongoose = require('mongoose');

const CONTACT_CATEGORIES = [
  'Account & Profile',
  'Payments & Transactions',
  'Groups & Expenses',
  'Lending & Borrowing',
  'Security & Privacy',
  'Technical Issue',
  'Feature Request',
  'Billing & Subscriptions',
  'General Inquiry',
  'Other',
];

const contactMessageSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true, maxlength: 100 },
  email: { type: String, required: true, trim: true, lowercase: true },
  subject: { type: String, trim: true, default: 'General Inquiry', maxlength: 200 },
  message: { type: String, required: true, trim: true, maxlength: 2000 },
  category: {
    type: String,
    enum: CONTACT_CATEGORIES,
    default: 'General Inquiry',
    index: true,
  },
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
contactMessageSchema.index({ category: 1, createdAt: -1 });
contactMessageSchema.index({ email: 1 });

const ContactMessage = mongoose.model('ContactMessage', contactMessageSchema);

module.exports = ContactMessage;
module.exports.CONTACT_CATEGORIES = CONTACT_CATEGORIES;
