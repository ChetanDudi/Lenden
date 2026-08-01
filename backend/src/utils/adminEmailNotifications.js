const { sendEmail } = require('./sendEmailApi');
const { shell, infoRow, infoTable, alertBox } = require('./emailTemplate');

exports.sendAdminWelcomeEmail = async (to, adminInfo) => {
  await sendEmail({
    to,
    subject: 'LenDen – Admin Account Created',
    text: `Welcome to the LenDen Admin Team, ${adminInfo.name}.\n\nYour admin account has been created.\n\nName: ${adminInfo.name}\nUsername: ${adminInfo.username}\nEmail: ${adminInfo.email}\n\nFor security reasons, your password is not included in this email. Please use the Forgot Password option on the admin login page to set your password before signing in.\n\nNever share your credentials with anyone.`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Admin Account Created</p>
      <p style="margin:0 0 16px;">Dear ${adminInfo.name},</p>
      <p style="margin:0 0 24px;">Your administrator account on the LenDen platform has been created. Your account details are listed below.</p>
      ${infoTable([['Name', adminInfo.name], ['Username', adminInfo.username], ['Email', adminInfo.email]])}
      <p style="margin:0 0 16px;background:#fff8e1;border-left:4px solid #f0a500;padding:12px 16px;color:#555555;font-size:13px;">
        For security reasons, your password has not been included in this email. Please use the <strong>Forgot Password</strong> option on the admin login page to set your password before signing in.
      </p>
      <p style="margin:16px 0 0;color:#555555;">Never share your credentials with anyone. If you did not expect this account, please contact the super administrator immediately.</p>
    `, true),
  });
};

exports.sendAdminDigestEmail = async (to, period, stats) => {
  const periodLabel = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' }[period] || 'Periodic';
  const rows = [
    ['New users', stats.newUsers],
    ['New secure transactions', `${stats.newSecureTx} (&#8377;${stats.secureVolume.toLocaleString('en-IN')})`],
    ['New quick transactions', `${stats.newQuickTx} (&#8377;${stats.quickVolume.toLocaleString('en-IN')})`],
    ['New expense groups', stats.newGroups],
    ['Open support queries', stats.openSupportQueries],
    ['New disputes', stats.newDisputes],
    ['Open disputes', stats.openDisputes],
    ['New fraud alerts', stats.newFraudAlerts],
    ['Open fraud alerts', stats.openFraudAlerts],
  ];

  await sendEmail({
    to,
    subject: `LenDen – ${periodLabel} Admin Digest`,
    text: rows.map(([label, value]) => `${label}: ${value}`).join('\n'),
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">${periodLabel} Admin Digest</p>
      <p style="margin:0 0 24px;">Here is the platform activity summary for the current ${period} period.</p>
      ${infoTable(rows)}
      <p style="margin:16px 0 0;color:#888888;font-size:13px;">Log in to the admin dashboard for full details and to manage any open items.</p>
    `, true),
  });
};

exports.sendFraudAlertSummaryEmail = async (to, alerts) => {
  const alertRows = alerts.map((a) => `
    <tr>
      <td style="padding:10px 16px;font-weight:bold;color:#cc0000;border-bottom:1px solid #e0e0e0;">${a.severity.toUpperCase()}</td>
      <td style="padding:10px 16px;color:#333333;border-bottom:1px solid #e0e0e0;">${a.type.replace(/_/g, ' ')}</td>
      <td style="padding:10px 16px;color:#555555;border-bottom:1px solid #e0e0e0;">${a.description}</td>
    </tr>`).join('');

  await sendEmail({
    to,
    subject: `LenDen – Fraud Scan: ${alerts.length} new alert${alerts.length === 1 ? '' : 's'}`,
    text: `The automated fraud scan found ${alerts.length} new alert(s):\n\n${alerts.map((a) => `[${a.severity.toUpperCase()}] ${a.type}: ${a.description}`).join('\n')}`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Fraud Scan Alert</p>
      <p style="margin:0 0 24px;">The automated fraud scan has detected <strong>${alerts.length} new alert${alerts.length === 1 ? '' : 's'}</strong> requiring review.</p>
      <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:24px;">
        <tr style="background:#f7f7f7;">
          <td style="padding:10px 16px;font-weight:bold;color:#555555;border-bottom:1px solid #e0e0e0;">Severity</td>
          <td style="padding:10px 16px;font-weight:bold;color:#555555;border-bottom:1px solid #e0e0e0;">Type</td>
          <td style="padding:10px 16px;font-weight:bold;color:#555555;border-bottom:1px solid #e0e0e0;">Description</td>
        </tr>
        ${alertRows}
      </table>
      <p style="margin:0;color:#555555;">Review and resolve these in the admin dashboard under <strong>Manage Disputes &amp; Fraud Alerts</strong>.</p>
    `, true),
  });
};

exports.sendAdminRemovalEmail = async (to, adminName) => {
  await sendEmail({
    to,
    subject: 'LenDen – Admin Access Revoked',
    text: `Dear ${adminName},\n\nYour administrator access to the LenDen platform has been revoked. You will no longer be able to access the admin portal.\n\nIf you believe this is an error, please contact the super administrator.`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Admin Access Revoked</p>
      <p style="margin:0 0 16px;">Dear ${adminName},</p>
      <p style="margin:0 0 16px;">Your administrator access to the LenDen platform has been revoked. Your admin session has been terminated and you will no longer have access to the admin portal.</p>
      ${alertBox('If you did not expect this or believe this is an error, please contact the super administrator immediately.', 'error')}
    `, true),
  });
};
