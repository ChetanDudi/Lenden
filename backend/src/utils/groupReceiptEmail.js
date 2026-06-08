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

const sendGroupReceiptEmail = async (to, group, pdfBuffer) => {
  const mailOptions = {
    from: process.env.EMAIL_USER,
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
  };

  await transporter.sendMail(mailOptions);
};

module.exports = { sendGroupReceiptEmail };
