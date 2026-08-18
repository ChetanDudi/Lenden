const { sendEmail } = require('./sendEmailApi');
const { shell, infoTable } = require('./emailTemplate');

const sendReceiptEmail = async (to, transaction, pdfBuffer) => {
  await sendEmail({
    to,
    subject: `LenDen – Transaction Receipt (${transaction.transactionId})`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Receipt</p>
        <p style="margin:0 0 16px;">Please find attached the receipt for your transaction. Keep this for your records.</p>
        ${infoTable([['Transaction ID', transaction.transactionId], ['Amount', `${transaction.amount} ${transaction.currency}`]])}
        <p style="margin:0;color:#888888;font-size:13px;">The full receipt is attached as a PDF document.</p>
      `),
    attachments: [
      {
        filename: `receipt-${transaction.transactionId}.pdf`,
        content: pdfBuffer,
        contentType: 'application/pdf',
      },
    ],
  });
};

module.exports = { sendReceiptEmail };
