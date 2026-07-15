const { sendEmail } = require('./sendEmailApi');
const User = require('../models/user');
const { shouldSendNotification } = require('./shouldSendNotification');

const sendGroupLeaveRequestEmail = async (creatorEmail, groupDetails, requestingUserEmail, userBalance) => {
  try {
    const creator = await User.findOne({ email: creatorEmail });
    if (!creator || !creator.notificationSettings.emailNotifications || !shouldSendNotification(creator)) {
      return false;
    }

    const balanceSection = userBalance !== 0
      ? `<p style="margin:16px 0 0;background:#fce8e8;border-left:4px solid #cc0000;padding:12px 16px;color:#555555;font-size:13px;">This member has a pending balance of <strong>&#8377;${Math.abs(userBalance).toFixed(2)}</strong> that must be settled before they can leave the group.</p>`
      : `<p style="margin:16px 0 0;background:#e8f5e9;border-left:4px solid #388e3c;padding:12px 16px;color:#555555;font-size:13px;">This member has no pending balance and can safely leave the group.</p>`;

    const _row = (label, value, shaded) =>
      `<tr${shaded ? ' style="background:#f7f7f7;"' : ''}>
        <td style="padding:10px 16px;font-weight:bold;color:#555555;width:45%;border-bottom:1px solid #e0e0e0;">${label}</td>
        <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${value}</td>
      </tr>`;

    await sendEmail({
      to: creatorEmail,
      subject: `LenDen – Leave Request: ${requestingUserEmail} wants to leave "${groupDetails.title}"`,
      html: `
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2f2f2;padding:24px 0;">
  <tr><td align="center">
    <table width="580" cellpadding="0" cellspacing="0" border="0" style="background:#ffffff;border:1px solid #cccccc;font-family:Arial,Helvetica,sans-serif;">
      <tr><td style="background:#003d75;padding:20px 32px;">
        <span style="font-size:20px;font-weight:bold;color:#ffffff;letter-spacing:1px;">LenDen</span>
      </td></tr>
      <tr><td style="padding:32px;color:#333333;font-size:14px;line-height:1.7;">
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Leave Request</p>
        <p style="margin:0 0 24px;"><strong>${requestingUserEmail}</strong> has requested to leave your group <strong>${groupDetails.title}</strong>. Please review the details below and approve or deny the request in the app.</p>
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:16px;">
          ${_row('Group', groupDetails.title, true)}
          ${_row('Requesting Member', requestingUserEmail, false)}
          ${_row('Total Members', groupDetails.members ? groupDetails.members.length : 0, true)}
          ${_row('Total Expenses', groupDetails.expenses ? groupDetails.expenses.length : 0, false)}
        </table>
        ${balanceSection}
      </td></tr>
      <tr><td style="background:#f9f9f9;border-top:1px solid #e5e5e5;padding:16px 32px;font-size:11px;color:#999999;">
        <p style="margin:0;">This is an automated message. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;">&copy; 2024 LenDen. All rights reserved.</p>
      </td></tr>
    </table>
  </td></tr>
</table>`,
    });
    return true;
  } catch (error) {
    console.error('Error sending group leave request email:', error.message);
    return false;
  }
};

module.exports = { sendGroupLeaveRequestEmail };
