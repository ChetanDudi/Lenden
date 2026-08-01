const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock } = require('./emailTemplate');

exports.sendRegistrationOTP = async (to, otp) => {
  await sendEmail({
    to,
    subject: 'LenDen – Verify Your Email Address',
    text: `Your registration OTP is: ${otp}\nThis code expires in 2 minutes. Do not share it with anyone.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Verify your email address</p>
        <p style="margin:0 0 16px;">Thank you for registering with LenDen. To complete your account setup, please enter the one-time password below in the app.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">For your security, do not share this code with anyone. LenDen will never ask for your OTP over a call or message.</p>
        <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not request this, you can safely ignore this email.</p>
      `),
  });
};
