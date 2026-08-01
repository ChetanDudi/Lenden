const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock } = require('./emailTemplate');

exports.sendGroupSettleOtp = async (email, otp) => {
  await sendEmail({
    to: email,
    subject: 'LenDen – Group Balance Settlement Verification',
    text: `Your OTP to settle your group balance is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Balance Settlement</p>
        <p style="margin:0 0 16px;">A group balance settlement has been initiated on your LenDen account. Enter the verification code below to confirm and complete the settlement.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
        <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not initiate this settlement, please ignore this email. No changes will be made.</p>
      `),
  });
};
