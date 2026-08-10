const nodemailer = require('nodemailer');
const { EmailServiceError } = require('./apiError');

async function sendEmail({ to, subject, html, text, attachments }) {
  const start = Date.now();
  const errors = [];

  // 1. Try Resend (HTTP API — works on Render, no SMTP port needed)
  if (process.env.RESEND_API_KEY) {
    try {
      await _sendViaResend({ to, subject, html, text, attachments });
      console.log(`[email] sent via resend to=${to} subject="${subject}" ms=${Date.now() - start}`);
      return;
    } catch (resendErr) {
      console.warn(`[email] resend failed (${resendErr.message}), trying sendgrid`);
      errors.push(resendErr);
    }
  }

  // 2. Try SendGrid (HTTP API — works on Render, but free tier has daily limits)
  if (process.env.SENDGRID_API_KEY) {
    try {
      await _sendViaSendGrid({ to, subject, html, text, attachments });
      console.log(`[email] sent via sendgrid to=${to} subject="${subject}" ms=${Date.now() - start}`);
      return;
    } catch (sgErr) {
      console.warn(`[email] sendgrid failed (${sgErr.message}), trying gmail`);
      errors.push(sgErr);
    }
  }

  // 3. Try Gmail SMTP (works locally; blocked by Render's firewall on port 465/587)
  try {
    await _sendViaNodemailer({ to, subject, html, text, attachments });
    console.log(`[email] sent via gmail to=${to} subject="${subject}" ms=${Date.now() - start}`);
    return;
  } catch (gmailErr) {
    errors.push(gmailErr);
    console.error(`[email] all providers failed to=${to} subject="${subject}"`, errors.map(e => e.message));
    throw new EmailServiceError(gmailErr);
  }
}

async function _sendViaResend({ to, subject, html, text, attachments }) {
  const body = {
    from: `Lenden <${process.env.RESEND_FROM_EMAIL || 'onboarding@resend.dev'}>`,
    to: [to],
    subject,
    html,
    ...(text && { text }),
  };

  if (attachments && attachments.length > 0) {
    body.attachments = attachments.map(a => ({
      filename: a.filename,
      content: Buffer.isBuffer(a.content) ? a.content.toString('base64') : a.content,
    }));
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message || `Resend error ${res.status}`);
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
