// Shared SendGrid HTTP email sender — replaces all nodemailer usage.
// Uses Node 18+ built-in fetch. No npm package needed.
// Set SENDGRID_API_KEY in Render environment variables.

async function sendEmail({ to, subject, html, text, attachments }) {
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

  // PDF / file attachments (Buffer or base64 string)
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

module.exports = { sendEmail };
