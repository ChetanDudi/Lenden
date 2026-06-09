const { sendEmail } = require('./sendEmailApi');

const sendGroupReceiptEmail = async (to, group, pdfBuffer) => {
  await sendEmail({
    to,
    subject: `Group Transaction Receipt: ${group.title}`,
    html: `
      <div style="font-family: Arial, sans-serif; font-size: 16px; color: #333;">
        <h2>Group Transaction Receipt</h2>
        <p>Please find attached the receipt for the group "${group.title}".</p>
        <p>This receipt includes a summary of all expenses and member splits for the group.</p>
        <p>Thank you for using LenDen!</p>
      </div>
    `,
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
