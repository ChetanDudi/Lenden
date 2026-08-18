const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock, alertBox } = require('./emailTemplate');

exports.sendPasswordResetOTP = async (to, otp) => {
  await sendEmail({
    to,
    subject: 'LenDen – Password Reset Request',
    text: `Your password reset OTP is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Password Reset Request</p>
        <p style="margin:0 0 16px;">We received a request to reset the password for your LenDen account. Enter the code below in the app to proceed.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">For your security, do not share this code with anyone.</p>
        ${alertBox('If you did not request a password reset, no action is required. Your account password has not been changed.', 'warning')}
      `),
  });
};
