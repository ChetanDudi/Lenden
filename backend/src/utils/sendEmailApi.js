const nodemailer = require('nodemailer');

async function sendEmail({ to, subject, html, text, attachments }) {
  try {
    await _sendViaSendGrid({ to, subject, html, text, attachments });
  } catch (sgErr) {
    console.warn('SendGrid failed, falling back to Gmail SMTP:', sgErr.message);
    await _sendViaNodemailer({ to, subject, html, text, attachments });
  }
}

async function _sendViaSendGrid({ to, subject, html, text, attachments }) {
  const apiKey = process.env.SENDGRID_API_KEY;
  if (!apiKey) throw new Error('SENDGRID_API_KEY is not configured');

  const from = {
    email: process.env.EMAIL_USER || 'lenden.support@gmail.com',
    name: 'Lenden',
  };

  const content = [];
  if (text) content.push({ type: 'text/plain', value: text });
  content.push({ type: 'text/html', value: html });

  const body = {
    personalizations: [{ to: [{ email: to }] }],
    from,
    subject,
    content,
  };

  if (attachments && attachments.length > 0) {
    body.attachments = attachments.map(a => ({
      content: Buffer.isBuffer(a.content)
        ? a.content.toString('base64')
        : a.content,
      filename: a.filename,
      type: a.contentType || 'application/octet-stream',
      disposition: 'attachment',
    }));
  }

  const res = await fetch('https://api.sendgrid.com/v3/mail/send', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.errors?.[0]?.message || `SendGrid error ${res.status}`);
  }
}

async function _sendViaNodemailer({ to, subject, html, text, attachments }) {
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.EMAIL_USER,
      pass: process.env.EMAIL_PASS,
    },
  });

  const mailOptions = {
    from: `"Lenden" <${process.env.EMAIL_USER}>`,
    to,
    subject,
    html,
    ...(text && { text }),
  };

  if (attachments && attachments.length > 0) {
    mailOptions.attachments = attachments.map(a => ({
      filename: a.filename,
      content: a.content,
      contentType: a.contentType || 'application/octet-stream',
    }));
  }

  await transporter.sendMail(mailOptions);
}

module.exports = { sendEmail };
