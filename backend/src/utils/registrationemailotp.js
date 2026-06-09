const { sendEmail } = require('./sendEmailApi');

exports.sendRegistrationOTP = async (to, otp) => {
  await sendEmail({
    to,
    subject: 'Welcome to Lenden! Your Registration OTP',
    text: `Your OTP for registration is: ${otp}`,
    html: `
      <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
        <h2 style="color: #00B4D8; text-align: center;">Welcome to <span style='color:#0077B5;'>Lenden</span>!</h2>
        <p style="font-size: 16px; color: #333; text-align: center;">Thank you for registering. Your OTP is:</p>
        <div style="font-size: 32px; font-weight: bold; color: #00B4D8; text-align: center; margin: 24px 0; letter-spacing: 4px;">${otp}</div>
        <p style="font-size: 14px; color: #888; text-align: center;">This OTP is valid for 2 minutes. If you did not request this, please ignore this email.</p>
        <div style="text-align: center; margin-top: 24px;">
          <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
        </div>
      </div>
    `,
  });
};
