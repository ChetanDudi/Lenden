const { sendEmail } = require('./sendEmailApi');
const { shell } = require('./emailTemplate');

const sendGroupReceiptEmail = async (to, group, pdfBuffer) => {
  await sendEmail({
    to,
    subject: `LenDen – Group Receipt: ${group.title}`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Receipt</p>
        <p style="margin:0 0 16px;">Please find attached the receipt for the group <strong>${group.title}</strong>. The PDF includes a full summary of all expenses and member splits.</p>
        <p style="margin:0;color:#888888;font-size:13px;">Keep this document for your records.</p>
      `),
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
