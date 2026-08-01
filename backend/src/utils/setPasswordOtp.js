const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock } = require('./emailTemplate');

exports.sendSetPasswordOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Set Your Account Password',
    text: `Your OTP to set a password for your LenDen account is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Set Account Password</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">You have requested to set a password for your LenDen account. Enter the verification code below to proceed. Once set, you will be able to log in with your email and password in addition to Google Sign-In.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen will never ask for your OTP.</p>
        <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not request this, please ignore this email. No changes will be made to your account.</p>
      `),
  });
};
