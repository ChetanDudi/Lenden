const { sendEmail } = require('./sendEmailApi');
const { shell, alertBox } = require('./emailTemplate');

async function sendAccountDeletedEmail({ to, name, deactivated }) {
  const actionWord = deactivated ? 'Deactivated' : 'Deleted';
  const actionPast = deactivated ? 'deactivated' : 'deleted';
  await sendEmail({
    to,
    subject: `LenDen – Account ${actionWord} Confirmation`,
    text: `Dear ${name || 'User'},\n\nYour LenDen account has been ${actionPast}.\n\nIf you did not request this, please contact our support team immediately.\n\nThank you for using LenDen.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Account ${actionWord} Confirmation</p>
        <p style="margin:0 0 16px;">Dear ${name || 'User'},</p>
        <p style="margin:0 0 16px;">Your LenDen account associated with <strong>${to}</strong> has been successfully <strong>${actionPast}</strong>.</p>
        ${deactivated
          ? `<p style="margin:0 0 16px;">Your account data has been retained securely. You may recover your account at any time by selecting the recovery option on the login screen.</p>`
          : `<p style="margin:0 0 16px;">Your account and associated data have been permanently removed from our systems as per your request.</p>`
        }
        ${alertBox('If you did not request this action, please contact LenDen support immediately.', 'error')}
        <p style="margin:24px 0 0;color:#555555;">Thank you for being a part of LenDen.</p>
      `),
  });
}

module.exports = { sendAccountDeletedEmail };
