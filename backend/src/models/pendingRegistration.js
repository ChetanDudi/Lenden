const mongoose = require('mongoose');

// Temporary store for in-progress email-OTP registrations.
// MongoDB TTL index auto-removes documents after 10 minutes so stale
// entries are never left behind if the user abandons the flow.
const schema = new mongoose.Schema({
  email: { type: String, required: true, unique: true, index: true, lowercase: true, trim: true },
  otp: { type: String, required: true },
  data: { type: mongoose.Schema.Types.Mixed },
  createdAt: { type: Date, default: Date.now, expires: 600 }, // TTL: 10 min
});

module.exports = mongoose.model('PendingRegistration', schema);
