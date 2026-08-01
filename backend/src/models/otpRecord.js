const mongoose = require('mongoose');
const otpRecordSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true },
  otp: { type: String },
  createdAt: { type: Date, default: Date.now, expires: 300 },
});
module.exports = mongoose.model('OtpRecord', otpRecordSchema);
