const { sendEmail } = require('./sendEmailApi');
const User = require('../models/user');

const getStylishEmailHtml = (title, body) => `
  <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
    <h2 style="color: #00B4D8; text-align: center;">${title}</h2>
    <div style="font-size: 16px; color: #333; text-align: center;">${body}</div>
    <div style="text-align: center; margin-top: 24px;">
      <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
    </div>
  </div>
`;

const sendEmailToGroupMembers = async (group, subject, getBody, actorEmail) => {
  for (const member of group.members) {
    const user = await User.findById(member.user);
    if (user && user.notificationSettings.emailNotifications && user.notificationSettings.groupNotifications) {
      const isActor = user.email === actorEmail;
      const html = getStylishEmailHtml(subject, getBody(isActor));
      await sendEmail({ to: user.email, subject, html });
    }
  }
};

exports.sendGroupCreatedEmail = (group, creator) => {
  const subject = `New Group Created: ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have created a new group "${group.title}".</p>`
      : `<p>A new group "${group.title}" has been created by ${creator.email}.</p><p>You have been added as a member.</p>`,
    creator.email
  ).catch(e => console.error('sendGroupCreatedEmail error:', e.message));
};

exports.sendMemberAddedEmail = (group, addedMemberEmail, addedByEmail) => {
  const subject = `Member Added to ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have added ${addedMemberEmail} to the group "${group.title}".</p>`
      : `<p>${addedMemberEmail} has been added to the group "${group.title}" by ${addedByEmail}.</p>`,
    addedByEmail
  ).catch(e => console.error('sendMemberAddedEmail error:', e.message));
};

exports.sendMemberRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `Member Removed from ${group.title}`;
  const groupForNotification = { ...group, members: group.members.filter(m => m.user.email !== removedMemberEmail) };
  sendEmailToGroupMembers(groupForNotification, subject, (isActor) =>
    isActor
      ? `<p>You have removed ${removedMemberEmail} from the group "${group.title}".</p>`
      : `<p>${removedMemberEmail} has been removed from the group "${group.title}" by ${removedByEmail}.</p>`,
    removedByEmail
  ).catch(e => console.error('sendMemberRemovedEmail error:', e.message));
};

exports.sendYouHaveBeenRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `You have been removed from ${group.title}`;
  const html = getStylishEmailHtml(subject, `<p>You have been removed from the group "${group.title}" by ${removedByEmail}.</p>`);
  sendEmail({ to: removedMemberEmail, subject, html }).catch(e => console.error('sendYouHaveBeenRemovedEmail error:', e.message));
};

exports.sendExpenseAddedEmail = (group, expense, addedByEmail) => {
  const subject = `New Expense in ${group.title}: ${expense.description}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have added a new expense "${expense.description}" of ${expense.amount} to the group "${group.title}".</p>`
      : `<p>A new expense "${expense.description}" of ${expense.amount} has been added to the group "${group.title}" by ${addedByEmail}.</p>`,
    addedByEmail
  ).catch(e => console.error('sendExpenseAddedEmail error:', e.message));
};

exports.sendExpenseEditedEmail = (group, expense, editedByEmail) => {
  const subject = `Expense Edited in ${group.title}: ${expense.description}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have edited the expense "${expense.description}" in group "${group.title}".</p>`
      : `<p>The expense "${expense.description}" in group "${group.title}" has been edited by ${editedByEmail}.</p>`,
    editedByEmail
  ).catch(e => console.error('sendExpenseEditedEmail error:', e.message));
};

exports.sendExpenseDeletedEmail = (group, expense, deletedByEmail) => {
  const subject = `Expense Deleted in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have deleted the expense "${expense.description}" in group "${group.title}".</p>`
      : `<p>The expense "${expense.description}" in group "${group.title}" has been deleted by ${deletedByEmail}.</p>`,
    deletedByEmail
  ).catch(e => console.error('sendExpenseDeletedEmail error:', e.message));
};

exports.sendExpenseSettledEmail = (group, expense, settledByEmail) => {
  const subject = `Expense Settled in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p>You have settled an expense in group "${group.title}".</p>`
      : `<p>An expense in group "${group.title}" has been settled by ${settledByEmail}.</p>`,
    settledByEmail
  ).catch(e => console.error('sendExpenseSettledEmail error:', e.message));
};

exports.sendMemberLeftEmail = (group, memberEmail) => {
  const subject = `Member Left ${group.title}`;
  sendEmailToGroupMembers(group, subject, () => `<p>${memberEmail} has left the group "${group.title}".</p>`, null)
    .catch(e => console.error('sendMemberLeftEmail error:', e.message));
};
