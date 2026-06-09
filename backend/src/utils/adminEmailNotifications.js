const { sendEmail } = require('./sendEmailApi');

exports.sendAdminWelcomeEmail = async (to, adminInfo) => {
  await sendEmail({
    to,
    subject: 'Welcome to LenDen Admin Team',
    text: `Welcome to LenDen Admin Team! Here are your credentials:\nName: ${adminInfo.name}\nUsername: ${adminInfo.username}\nEmail: ${adminInfo.email}\nPassword: ${adminInfo.password}\n\nPlease change your password after your first login.`,
    html: `
      <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #00B4D8 0%, #0077B5 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
          <h1 style="color: white; margin: 0; font-size: 24px; font-weight: 600;">Welcome to LenDen Admin Team</h1>
          <p style="color: rgba(255,255,255,0.9); margin: 10px 0 0; font-size: 16px;">Your admin account has been created successfully</p>
        </div>
        <div style="background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <h2 style="color: #333; margin-bottom: 20px;">Your Admin Account Details</h2>
          <div style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
            <p style="margin: 10px 0;"><strong>Name:</strong> ${adminInfo.name}</p>
            <p style="margin: 10px 0;"><strong>Username:</strong> ${adminInfo.username}</p>
            <p style="margin: 10px 0;"><strong>Email:</strong> ${adminInfo.email}</p>
            <p style="margin: 10px 0;"><strong>Password:</strong> ${adminInfo.password}</p>
          </div>
          <div style="background: #ffe9e9; padding: 20px; border-radius: 8px; margin-bottom: 20px; border-left: 4px solid #ff4444;">
            <h3 style="color: #dc3545; margin-top: 0;">Important Security Notice</h3>
            <ul style="color: #555; margin: 0; padding-left: 20px;">
              <li style="margin-bottom: 5px;"><strong>Change your password immediately</strong> after your first login</li>
              <li style="margin-bottom: 5px;">Never share your admin credentials with anyone</li>
            </ul>
          </div>
        </div>
        <div style="text-align: center; margin-top: 20px; color: #666; font-size: 12px;">
          <p>&copy; 2024 Lenden App. All rights reserved.</p>
        </div>
      </div>
    `,
  });
};

exports.sendAdminRemovalEmail = async (to, adminName) => {
  await sendEmail({
    to,
    subject: 'LenDen Admin Access Revoked',
    text: `Dear ${adminName}, your admin access to the LenDen platform has been revoked.`,
    html: `
      <div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto;">
        <div style="background: linear-gradient(135deg, #ff4b4b 0%, #ff7676 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
          <h1 style="color: white; margin: 0;">Admin Access Revoked</h1>
        </div>
        <div style="background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1);">
          <h2 style="color: #333; margin-bottom: 20px;">Dear ${adminName},</h2>
          <p style="color: #555; line-height: 1.6;">Your admin access to the LenDen platform has been revoked. If you believe this is an error, please contact the super administrator.</p>
          <div style="background: #fff3cd; padding: 20px; border-radius: 8px; margin: 20px 0;">
            <p style="color: #856404; margin: 0;">Your admin session has been terminated and you will no longer have access to admin features.</p>
          </div>
        </div>
        <div style="text-align: center; margin-top: 20px; color: #666; font-size: 12px;">
          <p>&copy; 2024 Lenden App. All rights reserved.</p>
        </div>
      </div>
    `,
  });
};
