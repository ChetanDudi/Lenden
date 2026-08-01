const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock } = require('./emailTemplate');

exports.sendAlternativeEmailOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Verify Your Alternative Email Address',
    text: `Your OTP to verify the alternative email address is: ${otp}\nThis code expires in 2 minutes.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Alternative Email Verification</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">You have requested to add <strong>${to}</strong> as an alternative email address on your LenDen account. Please enter the code below to confirm this change.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
        <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not request this change, please ignore this email. Your account will not be affected.</p>
      `),
  });
};
