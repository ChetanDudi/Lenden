const { sendEmail } = require('./sendEmailApi');

async function sendLoginNotificationEmail({ to, name, ipAddress, userAgent, loginTime }) {
  const formattedTime = loginTime.toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
  await sendEmail({
    to,
    subject: 'LenDen – New Sign-In to Your Account',
    text: `Hi ${name || 'User'},\n\nA new sign-in was detected on your LenDen account.\n\nTime: ${formattedTime}\nIP Address: ${ipAddress || 'Unknown'}\nDevice: ${userAgent || 'Unknown'}\n\nIf this was you, no action is needed. If you did not sign in, please reset your password immediately.`,
    html: `
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2f2f2;padding:24px 0;">
  <tr><td align="center">
    <table width="580" cellpadding="0" cellspacing="0" border="0" style="background:#ffffff;border:1px solid #cccccc;font-family:Arial,Helvetica,sans-serif;">
      <tr><td style="background:#003d75;padding:20px 32px;">
        <span style="font-size:20px;font-weight:bold;color:#ffffff;letter-spacing:1px;">LenDen</span>
      </td></tr>
      <tr><td style="padding:32px;color:#333333;font-size:14px;line-height:1.7;">
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">New Sign-In Detected</p>
        <p style="margin:0 0 16px;">Dear ${name || 'User'},</p>
        <p style="margin:0 0 24px;">A sign-in to your LenDen account was recorded. If this was you, no further action is required.</p>
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:24px;">
          <tr style="background:#f7f7f7;">
            <td style="padding:10px 16px;font-weight:bold;color:#555555;width:40%;border-bottom:1px solid #e0e0e0;">Date &amp; Time</td>
            <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${formattedTime}</td>
          </tr>
          <tr>
            <td style="padding:10px 16px;font-weight:bold;color:#555555;border-bottom:1px solid #e0e0e0;">IP Address</td>
            <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${ipAddress || 'Unknown'}</td>
          </tr>
          <tr style="background:#f7f7f7;">
            <td style="padding:10px 16px;font-weight:bold;color:#555555;">Device / Browser</td>
            <td style="padding:10px 16px;color:#222222;">${userAgent || 'Unknown'}</td>
          </tr>
        </table>
        <p style="margin:16px 0 0;background:#fce8e8;border-left:4px solid #cc0000;padding:12px 16px;color:#555555;font-size:13px;">If you did not sign in, please reset your password immediately and contact LenDen support.</p>
      </td></tr>
      <tr><td style="background:#f9f9f9;border-top:1px solid #e5e5e5;padding:16px 32px;font-size:11px;color:#999999;">
        <p style="margin:0;">This is an automated security notification. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;">&copy; 2024 LenDen. All rights reserved.</p>
      </td></tr>
    </table>
  </td></tr>
</table>`,
  });
}

module.exports = { sendLoginNotificationEmail };
