const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock, alertBox } = require('./emailTemplate');

exports.sendLoginOTP = async (to, otp) => {
  await sendEmail({
    to,
    subject: 'LenDen – Login Verification Code',
    text: `Your login OTP is: ${otp}\nThis code expires in 2 minutes. Do not share it with anyone.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Login Verification</p>
        <p style="margin:0 0 16px;">A login attempt was made for your LenDen account. Use the code below to complete sign-in.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen staff will never ask for your OTP.</p>
        ${alertBox('If you did not attempt to log in, please reset your password immediately to secure your account.', 'warning')}
      `),
  });
};
