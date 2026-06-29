const { sendEmail } = require('./sendEmailApi');

exports.sendGroupSettleOtp = async (email, otp) => {
  await sendEmail({
    to: email,
    subject: 'Lenden Group Settle - OTP Verification',
    text: `Your OTP to settle this group balance is: ${otp}\nIf you did not request this, please ignore this email.`,
    html: `
      <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
        <h2 style="color: #00B4D8; text-align: center;">Lenden Group Settle</h2>
        <p style="font-size: 16px; color: #333; text-align: center;">Your OTP to settle this group balance is:</p>
        <div style="font-size: 32px; font-weight: bold; color: #00B4D8; text-align: center; margin: 24px 0; letter-spacing: 4px;">${otp}</div>
        <p style="font-size: 14px; color: #888; text-align: center;">If you did not request this, please ignore this email.</p>
        <div style="text-align: center; margin-top: 24px;">
          <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
        </div>
      </div>
    `,
  });
};
