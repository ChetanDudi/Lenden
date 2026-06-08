const nodemailer = require('nodemailer');
const User = require('../models/user');

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  requireTLS: true,
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
  connectionTimeout: 8000,
  greetingTimeout: 5000,
  socketTimeout: 10000,
});

const getStylishEmailHtml = (title, body) => {
  return `
    <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
      <h2 style="color: #00B4D8; text-align: center;">${title}</h2>
      <div style="font-size: 16px; color: #333; text-align: center;">${body}</div>
      <div style="text-align: center; margin-top: 24px;">
        <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
      </div>
    </div>
  `;
};

const sendEmailToGroupMembers = async (group, subject, getBody, actorEmail) => {
  for (const member of group.members) {
    const user = await User.findById(member.user);
    if (user && user.notificationSettings.emailNotifications && user.notificationSettings.groupNotifications) {
      const isActor = user.email === actorEmail;
      const body = getBody(isActor);
      const html = getStylishEmailHtml(subject, body);

      const mailOptions = {
        from: process.env.EMAIL_USER,
        to: user.email,
        subject: subject,
        html: html,
      };
      await transporter.sendMail(mailOptions);
    }
  }
};

exports.sendGroupCreatedEmail = (group, creator) => {
  const subject = `New Group Created: ${group.title}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have created a new group \"${group.title}\".</p>`;
    }
    return `<p>A new group \"${group.title}\" has been created by ${creator.email}.</p><p>You have been added as a member.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, creator.email);
};

exports.sendMemberAddedEmail = (group, addedMemberEmail, addedByEmail) => {
  const subject = `Member Added to ${group.title}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have added ${addedMemberEmail} to the group \"${group.title}\".</p>`;
    }
    return `<p>${addedMemberEmail} has been added to the group \"${group.title}\" by ${addedByEmail}.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, addedByEmail);
};

exports.sendMemberRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `Member Removed from ${group.title}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have removed ${removedMemberEmail} from the group \"${group.title}\".</p>`;
    }
    return `<p>${removedMemberEmail} has been removed from the group \"${group.title}\" by ${removedByEmail}.</p>`;
  };
  // Create a version of the group for the general notification that doesn't include the removed member
  const groupForNotification = {
      ...group,
      members: group.members.filter(m => m.user.email !== removedMemberEmail)
  };
  sendEmailToGroupMembers(groupForNotification, subject, getBody, removedByEmail);
};

exports.sendYouHaveBeenRemovedEmail = (group, removedMemberEmail, removedByEmail) => {
  const subject = `You have been removed from ${group.title}`;
  const body = `<p>You have been removed from the group \"${group.title}\" by ${removedByEmail}.</p>`;
  const html = getStylishEmailHtml(subject, body);
  
  const mailOptions = {
    from: process.env.EMAIL_USER,
    to: removedMemberEmail,
    subject: subject,
    html: html,
  };
  transporter.sendMail(mailOptions);
};

exports.sendExpenseAddedEmail = (group, expense, addedByEmail) => {
  const subject = `New Expense in ${group.title}: ${expense.description}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have added a new expense \"${expense.description}\" of ${expense.amount} to the group \"${group.title}\".</p>`;
    }
    return `<p>A new expense \"${expense.description}\" of ${expense.amount} has been added to the group \"${group.title}\" by ${addedByEmail}.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, addedByEmail);
};

exports.sendExpenseEditedEmail = (group, expense, editedByEmail) => {
  const subject = `Expense Edited in ${group.title}: ${expense.description}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have edited the expense \"${expense.description}\" in group \"${group.title}\".</p>`;
    }
    return `<p>The expense \"${expense.description}\" in group \"${group.title}\" has been edited by ${editedByEmail}.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, editedByEmail);
};

exports.sendExpenseDeletedEmail = (group, expense, deletedByEmail) => {
  const subject = `Expense Deleted in ${group.title}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have deleted the expense \"${expense.description}\" in group \"${group.title}\".</p>`;
    }
    return `<p>The expense \"${expense.description}\" in group \"${group.title}\" has been deleted by ${deletedByEmail}.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, deletedByEmail);
};

exports.sendExpenseSettledEmail = (group, expense, settledByEmail) => {
  const subject = `Expense Settled in ${group.title}`;
  const getBody = (isActor) => {
    if (isActor) {
      return `<p>You have settled an expense in group \"${group.title}\".</p>`;
    }
    return `<p>An expense in group \"${group.title}\" has been settled by ${settledByEmail}.</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, settledByEmail);
};

exports.sendMemberLeftEmail = (group, memberEmail) => {
  const subject = `Member Left ${group.title}`;
  const getBody = (isActor) => {
    return `<p>${memberEmail} has left the group \"${group.title}\".</p>`;
  };
  sendEmailToGroupMembers(group, subject, getBody, null, memberEmail);
};
