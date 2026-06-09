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
      ? `<div style="background: linear-gradient(135deg, #ffe6e6 0%, #ffcccc 100%); border: 2px solid #ff6b6b; border-radius: 15px; padding: 25px; margin-bottom: 30px; text-align: center;">
           <h3 style="color: #d63031;">Pending Balance</h3>
           <p style="color: #d63031;">This member has pending expenses that need to be settled.</p>
           <div style="font-size: 24px; font-weight: bold; color: #d63031; margin: 10px 0;">$${userBalance.toFixed(2)}</div>
         </div>`
      : `<div style="background: #d4edda; border: 2px solid #28a745; border-radius: 15px; padding: 25px; margin-bottom: 30px; text-align: center;">
           <h3 style="color: #155724;">No Pending Balance</h3>
           <p style="color: #155724;">This member has no pending expenses and can safely leave the group.</p>
         </div>`;

    await sendEmail({
      to: creatorEmail,
      subject: `Group Leave Request: ${requestingUserEmail} wants to leave "${groupDetails.title}"`,
      html: `
        <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.1);">
          <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 40px 30px; text-align: center;">
            <h1 style="margin: 0;">Group Leave Request</h1>
            <p style="opacity: 0.9;">A member wants to leave your group</p>
          </div>
          <div style="padding: 40px 30px;">
            <div style="background: #fff3cd; border: 2px solid #fdcb6e; border-radius: 15px; padding: 25px; margin-bottom: 30px; text-align: center;">
              <h2 style="color: #856404;">Action Required</h2>
              <p style="color: #856404;"><strong>${requestingUserEmail}</strong> has requested to leave your group "${groupDetails.title}".</p>
            </div>
            <div style="background: #f8f9fa; border-radius: 15px; padding: 25px; margin-bottom: 30px;">
              <h3 style="color: #495057;">Group Details</h3>
              <p><strong>Group:</strong> ${groupDetails.title}</p>
              <p><strong>Requesting Member:</strong> ${requestingUserEmail}</p>
              <p><strong>Total Members:</strong> ${groupDetails.members ? groupDetails.members.length : 0}</p>
              <p><strong>Total Expenses:</strong> ${groupDetails.expenses ? groupDetails.expenses.length : 0}</p>
            </div>
            ${balanceSection}
          </div>
          <div style="background: #f8f9fa; padding: 20px; text-align: center; color: #6c757d; font-size: 14px;">
            <p>&copy; Lenden App. This is an automated message.</p>
          </div>
        </div>
      `,
    });
    return true;
  } catch (error) {
    console.error('Error sending group leave request email:', error.message);
    return false;
  }
};

module.exports = { sendGroupLeaveRequestEmail };
