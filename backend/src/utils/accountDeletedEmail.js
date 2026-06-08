const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  requireTLS: true,
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
  connectionTimeout: 8000,
  greetingTimeout: 5000,
  socketTimeout: 10000,
});

/**
 * Send a stylish account deactivated email to the user.
 * @param {Object} param0
 * @param {string} param0.to - Recipient email
 * @param {string} param0.name - User's name
 * @param {boolean} [param0.deactivated] - If true, say "deactivated", else "deleted"
 */
async function sendAccountDeletedEmail({ to, name, deactivated }) {
  const actionWord = deactivated ? 'Deactivated' : 'Deleted';
  const actionPast = deactivated ? 'deactivated' : 'deleted';
  const html = `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; background: #f8f6fa; padding: 32px;">
      <div style="max-width: 480px; margin: auto; background: #fff; border-radius: 16px; box-shadow: 0 2px 12px #0001; padding: 32px;">
        <div style="text-align: center;">
          <img src="https://img.icons8.com/color/96/delete-forever.png" alt="Account ${actionWord}" style="width: 64px; margin-bottom: 16px;" />
          <h2 style="color: #d90429; margin-bottom: 8px;">Account ${actionWord}</h2>
        </div>
        <p style="font-size: 16px; color: #222;">
          Hi <b>${name || 'User'}</b>,
        </p>
        <p style="font-size: 15px; color: #444;">
          Your <b>LenDen</b> account has been <span style="color: #d90429; font-weight: bold;">successfully ${actionPast}</span>.<br>
          We're sorry to see you go!
        </p>
        <div style="background: #ffe5e5; border-radius: 8px; padding: 16px; margin-bottom: 16px;">
          <span style="color: #d90429; font-weight: 500;">
            Your data is preserved securely. If this was not you, or you wish to recover your account, please contact our support team or use the recovery option on the login page.
          </span>
        </div>
        <p style="font-size: 13px; color: #888; text-align: center;">
          Thank you for being a part of LenDen.<br>
          <b>LenDen Team</b>
        </p>
        <div style="text-align:center; margin-top:24px;">
          <a href="https://lenden.com" style="color:#00b4d8; text-decoration:none; font-weight:bold;">Visit LenDen</a>
        </div>
      </div>
    </div>
  `;

  await transporter.sendMail({
    from: process.env.EMAIL_FROM || '"LenDen" <no-reply@lenden.com>',
    to,
    subject: `LenDen: Account ${actionWord} Confirmation`,
    html
  });
}

module.exports = { sendAccountDeletedEmail };
