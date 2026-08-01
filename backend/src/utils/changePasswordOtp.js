const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock, alertBox } = require('./emailTemplate');

exports.sendChangePasswordOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Change Password Verification',
    text: `Your OTP to change your LenDen account password is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email and your password will remain unchanged.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Change Account Password</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">You have requested to change the password for your LenDen account. Enter the verification code below to confirm your identity and proceed with the change.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen will never ask for your OTP.</p>
        ${alertBox('If you did not request a password change, please ignore this email. Your current password will remain unchanged and no action is required.', 'error')}
      `),
  });
};
