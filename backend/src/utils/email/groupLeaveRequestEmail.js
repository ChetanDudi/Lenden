const { sendEmail } = require('./sendEmailApi');
const User = require('../../models/user');
const { shouldSendNotification } = require('./shouldSendNotification');
const { shell, infoTable, alertBox } = require('./emailTemplate');

const sendGroupLeaveRequestEmail = async (creatorEmail, groupDetails, requestingUserEmail, userBalance) => {
  try {
    const creator = await User.findOne({ email: creatorEmail });
    if (!creator || !creator.notificationSettings.emailNotifications || !shouldSendNotification(creator)) {
      return false;
    }

    const balanceSection = userBalance !== 0
      ? alertBox(`This member has a pending balance of <strong>&#8377;${Math.abs(userBalance).toFixed(2)}</strong> that must be settled before they can leave the group.`, 'error')
      : alertBox('This member has no pending balance and can safely leave the group.', 'success');

    await sendEmail({
      to: creatorEmail,
      subject: `LenDen – Leave Request: ${requestingUserEmail} wants to leave "${groupDetails.title}"`,
      html: shell(`
          <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Leave Request</p>
          <p style="margin:0 0 24px;"><strong>${requestingUserEmail}</strong> has requested to leave your group <strong>${groupDetails.title}</strong>. Please review the details below and approve or deny the request in the app.</p>
          ${infoTable([
            ['Group', groupDetails.title],
            ['Requesting Member', requestingUserEmail],
            ['Total Members', groupDetails.members ? groupDetails.members.length : 0],
            ['Total Expenses', groupDetails.expenses ? groupDetails.expenses.length : 0],
          ])}
          ${balanceSection}
        `),
    });
    return true;
  } catch (error) {
    console.error('Error sending group leave request email:', error.message);
    return false;
  }
};

module.exports = { sendGroupLeaveRequestEmail };
