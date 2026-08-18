const nodemailer = require('nodemailer');
const { EmailServiceError } = require('../apiError');

async function sendEmail({ to, subject, html, text, attachments }) {
  const start = Date.now();

  // Primary: Brevo (HTTP API, no domain needed — just verify sender email on brevo.com)
  if (process.env.BREVO_API_KEY) {
    try {
      await _sendViaBrevo({ to, subject, html, text, attachments });
      console.log(`[email] sent via brevo to=${to} subject="${subject}" ms=${Date.now() - start}`);
      return;
    } catch (brevoErr) {
      console.warn(`[email] brevo failed (${brevoErr.message}), trying gmail`);
    }
  }

  // Fallback: Gmail SMTP (works locally only; Render blocks outbound SMTP ports)
  try {
    await _sendViaNodemailer({ to, subject, html, text, attachments });
    console.log(`[email] sent via gmail to=${to} subject="${subject}" ms=${Date.now() - start}`);
    return;
  } catch (gmailErr) {
    console.error(`[email] all providers failed to=${to} subject="${subject}" gmailErr="${gmailErr.message}"`);
    throw new EmailServiceError(gmailErr);
  }
}

async function _sendViaBrevo({ to, subject, html, text, attachments }) {
  const body = {
    sender: { name: 'Lenden', email: process.env.EMAIL_USER || 'lenden.support@gmail.com' },
    to: [{ email: to }],
    subject,
    htmlContent: html,
    ...(text && { textContent: text }),
  };

  if (attachments && attachments.length > 0) {
    body.attachment = attachments.map(a => ({
      name: a.filename,
      content: Buffer.isBuffer(a.content) ? a.content.toString('base64') : a.content,
    }));
  }

  const res = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      'api-key': process.env.BREVO_API_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message || `Brevo error ${res.status}`);
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
