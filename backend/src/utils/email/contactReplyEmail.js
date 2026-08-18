const { sendEmail } = require('./sendEmailApi');
const { shell } = require('./emailTemplate');

async function sendContactReplyEmail({ name, email, subject, originalMessage, replyText }) {
  const content = `
    <p style="color:#555;margin:0 0 16px;">Hi ${name},</p>
    <p style="color:#333;margin:0 0 20px;">Thank you for reaching out. Here is our response:</p>
    <div style="background:#f0f9fc;border-left:4px solid #00B4D8;padding:16px;border-radius:4px;margin:0 0 24px;">
      <p style="color:#333;margin:0;line-height:1.6;">${replyText.trim().replace(/\n/g, '<br>')}</p>
    </div>
    <p style="color:#999;font-size:12px;margin:0 0 4px;"><strong>Your original message:</strong></p>
    <p style="color:#aaa;font-size:12px;font-style:italic;margin:0 0 24px;">"${originalMessage}"</p>
    <p style="color:#555;margin:0;">Best regards,<br><strong>Lenden Support Team</strong></p>
  `;

  await sendEmail({
    to: email,
    subject: `Re: ${subject || 'Your Inquiry'} - Lenden Support`,
    html: shell(content),
  });
}

module.exports = { sendContactReplyEmail };
