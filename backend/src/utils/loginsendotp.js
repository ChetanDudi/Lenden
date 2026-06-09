const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  requireTLS: true,
  pool: true,
  maxConnections: 2,
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
  connectionTimeout: 30000,
  greetingTimeout: 15000,
  socketTimeout: 30000,
});

// Pre-warm the SMTP connection pool at server startup so the first OTP email
// doesn't pay the connection establishment cost during a user request.
transporter.verify().catch(e =>
  console.warn('[Login OTP] SMTP warm-up:', e.message)
);

exports.sendLoginOTP = async (to, otp) => {
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to,
    subject: 'Lenden Login - OTP Verification',
    html: `
      <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
        <h2 style="color: #00B4D8; text-align: center;">Lenden Login OTP</h2>
        <p style="font-size: 16px; color: #333; text-align: center;">Your OTP for login is:</p>
        <div style="font-size: 32px; font-weight: bold; color: #00B4D8; text-align: center; margin: 24px 0; letter-spacing: 4px;">${otp}</div>
        <p style="font-size: 14px; color: #888; text-align: center;">This OTP is valid for 2 minutes. If you did not request this, please ignore this email.</p>
        <div style="text-align: center; margin-top: 24px;">
          <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
        </div>
      </div>
    `,
  });
};
