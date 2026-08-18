const { sendEmail } = require('./sendEmailApi');
const User = require('../../models/user');
const { shell } = require('./emailTemplate');
const { shouldSendNotification } = require('./shouldSendNotification');

const sendEmailToGroupMembers = async (group, subject, getBody, actorEmail) => {
  for (const member of group.members) {
    const user = await User.findById(member.user);
    if (user && user.notificationSettings.emailNotifications && user.notificationSettings.groupNotifications && shouldSendNotification(user)) {
      const isActor = user.email === actorEmail;
      await sendEmail({ to: user.email, subject, html: shell(getBody(isActor)) });
    }
  }
};

exports.sendGroupCreatedEmail = (group, creator) => {
  const subject = `LenDen – Group Created: ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Group Created</p><p style="margin:0 0 16px;">You have successfully created the group <strong>${group.title}</strong>. You can now start adding expenses and managing balances.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">You Have Been Added to a Group</p><p style="margin:0 0 16px;">You have been added to the group <strong>${group.title}</strong> by ${creator.email}. Open the LenDen app to view the group details.</p>`,
    creator.email
  ).catch(e => console.error('sendGroupCreatedEmail error:', e.message));
};

exports.sendMemberAddedEmail = (group, addedMemberEmail, addedByEmail) => {
  const subject = `LenDen – Member Added: ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Member Added</p><p style="margin:0;">You have added <strong>${addedMemberEmail}</strong> to the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">New Member in ${group.title}</p><p style="margin:0;"><strong>${addedMemberEmail}</strong> has been added to your group <strong>${group.title}</strong> by ${addedByEmail}.</p>`,
    addedByEmail
  ).catch(e => console.error('sendMemberAddedEmail error:', e.message));
};

exports.sendMemberRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `LenDen – Member Removed: ${group.title}`;
  const groupForNotification = { ...group, members: group.members.filter(m => m.user.email !== removedMemberEmail) };
  sendEmailToGroupMembers(groupForNotification, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Member Removed</p><p style="margin:0;">You have removed <strong>${removedMemberEmail}</strong> from the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Member Removed from ${group.title}</p><p style="margin:0;"><strong>${removedMemberEmail}</strong> has been removed from the group <strong>${group.title}</strong> by ${removedByEmail}.</p>`,
    removedByEmail
  ).catch(e => console.error('sendMemberRemovedEmail error:', e.message));
};

exports.sendYouHaveBeenRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `LenDen – Removed from ${group.title}`;
  const html = shell(`
    <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">You Have Been Removed from a Group</p>
    <p style="margin:0 0 16px;">You have been removed from the group <strong>${group.title}</strong> by ${removedByEmail}.</p>
    <p style="margin:0;color:#555555;">If you believe this is an error, please contact the group administrator.</p>
  `);
  sendEmail({ to: removedMemberEmail, subject, html }).catch(e => console.error('sendYouHaveBeenRemovedEmail error:', e.message));
};

exports.sendExpenseAddedEmail = (group, expense, addedByEmail) => {
  const subject = `LenDen – New Expense in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Added</p><p style="margin:0;">You have added a new expense <strong>${expense.description}</strong> of <strong>${expense.amount}</strong> to the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">New Expense in ${group.title}</p><p style="margin:0;">A new expense <strong>${expense.description}</strong> of <strong>${expense.amount}</strong> has been added to your group <strong>${group.title}</strong> by ${addedByEmail}.</p>`,
    addedByEmail
  ).catch(e => console.error('sendExpenseAddedEmail error:', e.message));
};

exports.sendExpenseEditedEmail = (group, expense, editedByEmail) => {
  const subject = `LenDen – Expense Updated in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Updated</p><p style="margin:0;">You have updated the expense <strong>${expense.description}</strong> in the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Updated in ${group.title}</p><p style="margin:0;">The expense <strong>${expense.description}</strong> in the group <strong>${group.title}</strong> has been updated by ${editedByEmail}.</p>`,
    editedByEmail
  ).catch(e => console.error('sendExpenseEditedEmail error:', e.message));
};

exports.sendExpenseDeletedEmail = (group, expense, deletedByEmail) => {
  const subject = `LenDen – Expense Deleted in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Deleted</p><p style="margin:0;">You have deleted the expense <strong>${expense.description}</strong> from the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Deleted in ${group.title}</p><p style="margin:0;">The expense <strong>${expense.description}</strong> has been deleted from the group <strong>${group.title}</strong> by ${deletedByEmail}.</p>`,
    deletedByEmail
  ).catch(e => console.error('sendExpenseDeletedEmail error:', e.message));
};

exports.sendExpenseSettledEmail = (group, expense, settledByEmail) => {
  const subject = `LenDen – Expense Settled in ${group.title}`;
  sendEmailToGroupMembers(group, subject, (isActor) =>
    isActor
      ? `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Settled</p><p style="margin:0;">You have settled an expense in the group <strong>${group.title}</strong>.</p>`
      : `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Expense Settled in ${group.title}</p><p style="margin:0;">An expense in the group <strong>${group.title}</strong> has been settled by ${settledByEmail}.</p>`,
    settledByEmail
  ).catch(e => console.error('sendExpenseSettledEmail error:', e.message));
};

exports.sendMemberLeftEmail = (group, memberEmail) => {
  const subject = `LenDen – Member Left ${group.title}`;
  sendEmailToGroupMembers(group, subject, () =>
    `<p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Member Left the Group</p><p style="margin:0;"><strong>${memberEmail}</strong> has left the group <strong>${group.title}</strong>.</p>`,
    null
  ).catch(e => console.error('sendMemberLeftEmail error:', e.message));
};
