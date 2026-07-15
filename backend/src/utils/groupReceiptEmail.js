const { sendEmail } = require('./sendEmailApi');

const sendGroupReceiptEmail = async (to, group, pdfBuffer) => {
  await sendEmail({
    to,
    subject: `LenDen – Group Receipt: ${group.title}`,
    html: `
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2f2f2;padding:24px 0;">
  <tr><td align="center">
    <table width="580" cellpadding="0" cellspacing="0" border="0" style="background:#ffffff;border:1px solid #cccccc;font-family:Arial,Helvetica,sans-serif;">
      <tr><td style="background:#003d75;padding:20px 32px;">
        <span style="font-size:20px;font-weight:bold;color:#ffffff;letter-spacing:1px;">LenDen</span>
      </td></tr>
      <tr><td style="padding:32px;color:#333333;font-size:14px;line-height:1.7;">
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Receipt</p>
        <p style="margin:0 0 16px;">Please find attached the receipt for the group <strong>${group.title}</strong>. The PDF includes a full summary of all expenses and member splits.</p>
        <p style="margin:0;color:#888888;font-size:13px;">Keep this document for your records.</p>
      </td></tr>
      <tr><td style="background:#f9f9f9;border-top:1px solid #e5e5e5;padding:16px 32px;font-size:11px;color:#999999;">
        <p style="margin:0;">This is an automated message. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;">&copy; 2024 LenDen. All rights reserved.</p>
      </td></tr>
    </table>
  </td></tr>
</table>`,
    attachments: [
      {
        filename: `group-receipt-${group._id}.pdf`,
        content: pdfBuffer,
        contentType: 'application/pdf',
      },
    ],
  });
};

module.exports = { sendGroupReceiptEmail };
