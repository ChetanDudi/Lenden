const { sendEmail } = require('./sendEmailApi');
const { shell, infoTable, alertBox } = require('./emailTemplate');

async function sendLoginNotificationEmail({ to, name, ipAddress, userAgent, loginTime }) {
  const formattedTime = loginTime.toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
  await sendEmail({
    to,
    subject: 'LenDen – New Sign-In to Your Account',
    text: `Hi ${name || 'User'},\n\nA new sign-in was detected on your LenDen account.\n\nTime: ${formattedTime}\nIP Address: ${ipAddress || 'Unknown'}\nDevice: ${userAgent || 'Unknown'}\n\nIf this was you, no action is needed. If you did not sign in, please reset your password immediately.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">New Sign-In Detected</p>
        <p style="margin:0 0 16px;">Dear ${name || 'User'},</p>
        <p style="margin:0 0 24px;">A sign-in to your LenDen account was recorded. If this was you, no further action is required.</p>
        ${infoTable([['Date &amp; Time', formattedTime], ['IP Address', ipAddress || 'Unknown'], ['Device / Browser', userAgent || 'Unknown']])}
        ${alertBox('If you did not sign in, please reset your password immediately and contact LenDen support.', 'error')}
      `),
  });
}

module.exports = { sendLoginNotificationEmail };
