const { sendEmail } = require('./sendEmailApi');

async function sendAccountDeletedEmail({ to, name, deactivated }) {
  const actionWord = deactivated ? 'Deactivated' : 'Deleted';
  const actionPast = deactivated ? 'deactivated' : 'deleted';
  await sendEmail({
    to,
    subject: `LenDen – Account ${actionWord} Confirmation`,
    text: `Dear ${name || 'User'},\n\nYour LenDen account has been ${actionPast}.\n\nIf you did not request this, please contact our support team immediately.\n\nThank you for using LenDen.`,
    html: `
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2f2f2;padding:24px 0;">
  <tr><td align="center">
    <table width="580" cellpadding="0" cellspacing="0" border="0" style="background:#ffffff;border:1px solid #cccccc;font-family:Arial,Helvetica,sans-serif;">
      <tr><td style="background:#003d75;padding:20px 32px;">
        <span style="font-size:20px;font-weight:bold;color:#ffffff;letter-spacing:1px;">LenDen</span>
      </td></tr>
      <tr><td style="padding:32px;color:#333333;font-size:14px;line-height:1.7;">
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Account ${actionWord} Confirmation</p>
        <p style="margin:0 0 16px;">Dear ${name || 'User'},</p>
        <p style="margin:0 0 16px;">Your LenDen account associated with <strong>${to}</strong> has been successfully <strong>${actionPast}</strong>.</p>
        ${deactivated
          ? `<p style="margin:0 0 16px;">Your account data has been retained securely. You may recover your account at any time by selecting the recovery option on the login screen.</p>`
          : `<p style="margin:0 0 16px;">Your account and associated data have been permanently removed from our systems as per your request.</p>`
        }
        <p style="margin:16px 0 0;background:#fce8e8;border-left:4px solid #cc0000;padding:12px 16px;color:#555555;font-size:13px;">If you did not request this action, please contact LenDen support immediately.</p>
        <p style="margin:24px 0 0;color:#555555;">Thank you for being a part of LenDen.</p>
      </td></tr>
      <tr><td style="background:#f9f9f9;border-top:1px solid #e5e5e5;padding:16px 32px;font-size:11px;color:#999999;">
        <p style="margin:0;">This is an automated message. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;">&copy; 2024 LenDen. All rights reserved.</p>
      </td></tr>
    </table>
  </td></tr>
</table>`,
  });
}

module.exports = { sendAccountDeletedEmail };
