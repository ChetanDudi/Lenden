const { sendEmail } = require('./sendEmailApi');

exports.sendSetPasswordOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Set Your Account Password',
    text: `Your OTP to set a password for your LenDen account is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email.`,
    html: `
<table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f2f2f2;padding:24px 0;">
  <tr><td align="center">
    <table width="580" cellpadding="0" cellspacing="0" border="0" style="background:#ffffff;border:1px solid #cccccc;font-family:Arial,Helvetica,sans-serif;">
      <tr><td style="background:#003d75;padding:20px 32px;">
        <span style="font-size:20px;font-weight:bold;color:#ffffff;letter-spacing:1px;">LenDen</span>
      </td></tr>
      <tr><td style="padding:32px;color:#333333;font-size:14px;line-height:1.7;">
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Set Account Password</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">You have requested to set a password for your LenDen account. Enter the verification code below to proceed. Once set, you will be able to log in with your email and password in addition to Google Sign-In.</p>
        <div style="background:#f7f7f7;border:1px solid #dddddd;border-left:4px solid #003d75;margin:24px 0;padding:18px 24px;text-align:center;">
          <p style="margin:0 0 8px;font-size:11px;color:#666666;text-transform:uppercase;letter-spacing:1px;">One-Time Password (OTP)</p>
          <span style="font-family:'Courier New',Courier,monospace;font-size:30px;font-weight:bold;letter-spacing:8px;color:#111111;">${otp}</span>
          <p style="margin:8px 0 0;font-size:12px;color:#999999;">This code expires in 2 minutes.</p>
        </div>
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen will never ask for your OTP.</p>
        <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not request this, please ignore this email. No changes will be made to your account.</p>
      </td></tr>
      <tr><td style="background:#f9f9f9;border-top:1px solid #e5e5e5;padding:16px 32px;font-size:11px;color:#999999;">
        <p style="margin:0;">This is an automated message. Please do not reply to this email.</p>
        <p style="margin:6px 0 0;">&copy; 2024 LenDen. All rights reserved.</p>
      </td></tr>
    </table>
  </td></tr>
</table>`,
  });
};
