const { sendEmail } = require('./sendEmailApi');

const sendReceiptEmail = async (to, transaction, pdfBuffer) => {
  await sendEmail({
    to,
    subject: `Transaction Receipt: ${transaction.transactionId}`,
    html: `
      <div style="font-family: Arial, sans-serif; font-size: 16px; color: #333;">
        <h2>Transaction Receipt</h2>
        <p>Please find attached the receipt for your transaction.</p>
        <p><b>Transaction ID:</b> ${transaction.transactionId}</p>
        <p><b>Amount:</b> ${transaction.amount} ${transaction.currency}</p>
        <p>Thank you for using LenDen!</p>
      </div>
    `,
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
