const { sendEmail } = require('./sendEmailApi');

async function sendLoginNotificationEmail({ to, name, ipAddress, userAgent, loginTime }) {
  const formattedTime = loginTime.toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
  await sendEmail({
    to,
    subject: 'LenDen: New Login Notification',
    html: `
      <div style="font-family: 'Segoe UI', Arial, sans-serif; background: #f8f6fa; padding: 32px;">
        <div style="max-width: 480px; margin: auto; background: #fff; border-radius: 16px; box-shadow: 0 2px 12px #0001; padding: 32px;">
          <div style="text-align: center;">
            <img src="https://img.icons8.com/color/96/lock--v1.png" alt="Login" style="width: 64px; margin-bottom: 16px;" />
            <h2 style="color: #00b4d8; margin-bottom: 8px;">New Login Detected</h2>
          </div>
          <p style="font-size: 16px; color: #222;">Hi <b>${name || 'User'}</b>,</p>
          <p style="font-size: 15px; color: #444;">We noticed a new login to your account on <b>LenDen</b>.</p>
          <table style="width: 100%; margin: 24px 0; border-collapse: collapse;">
            <tr><td style="padding: 8px 0; color: #888;">Login Time:</td><td style="padding: 8px 0; color: #222;"><b>${formattedTime}</b></td></tr>
            <tr><td style="padding: 8px 0; color: #888;">IP Address:</td><td style="padding: 8px 0; color: #222;">${ipAddress || 'Unknown'}</td></tr>
            <tr><td style="padding: 8px 0; color: #888;">Device:</td><td style="padding: 8px 0; color: #222;">${userAgent || 'Unknown'}</td></tr>
          </table>
          <div style="background: #e0f7fa; border-radius: 8px; padding: 16px; margin-bottom: 16px;">
            <span style="color: #0077b6; font-weight: 500;">If this was you, you can safely ignore this email.<br>If you did <b>not</b> perform this login, please reset your password immediately.</span>
          </div>
          <p style="font-size: 13px; color: #888; text-align: center;">Stay secure,<br><b>LenDen Team</b></p>
        </div>
      </div>
    `,
  });
}

module.exports = { sendLoginNotificationEmail };
