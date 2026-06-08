const nodemailer = require('nodemailer');
const User = require('../models/user');
const { shouldSendNotification } = require('./shouldSendNotification');

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

// Send group leave request email to group creator
const sendGroupLeaveRequestEmail = async (creatorEmail, groupDetails, requestingUserEmail, userBalance) => {
  try {
    const creator = await User.findOne({ email: creatorEmail });
    if (!creator || !creator.notificationSettings.emailNotifications || !shouldSendNotification(creator)) {
      return false;
    }

    const htmlContent = `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Group Leave Request - Lenden</title>
        <style>
          * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
          }
          
          body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
          }
          
          .container {
            max-width: 600px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            overflow: hidden;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
          }
          
          .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px 30px;
            text-align: center;
          }
          
          .header h1 {
            font-size: 28px;
            font-weight: bold;
            margin-bottom: 10px;
          }
          
          .header p {
            font-size: 16px;
            opacity: 0.9;
          }
          
          .content {
            padding: 40px 30px;
          }
          
          .alert-box {
            background: linear-gradient(135deg, #fff3cd 0%, #ffeaa7 100%);
            border: 2px solid #fdcb6e;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 30px;
            text-align: center;
          }
          
          .alert-box h2 {
            color: #856404;
            font-size: 22px;
            margin-bottom: 15px;
            font-weight: bold;
          }
          
          .alert-box p {
            color: #856404;
            font-size: 16px;
            margin-bottom: 0;
          }
          
          .group-info {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 30px;
          }
          
          .group-info h3 {
            color: #495057;
            font-size: 20px;
            margin-bottom: 20px;
            font-weight: bold;
          }
          
          .info-row {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #e9ecef;
          }
          
          .info-row:last-child {
            border-bottom: none;
          }
          
          .info-label {
            font-weight: 600;
            color: #495057;
          }
          
          .info-value {
            color: #6c757d;
            font-weight: 500;
          }
          
          .balance-warning {
            background: linear-gradient(135deg, #ffe6e6 0%, #ffcccc 100%);
            border: 2px solid #ff6b6b;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 30px;
            text-align: center;
          }
          
          .balance-warning h3 {
            color: #d63031;
            font-size: 20px;
            margin-bottom: 15px;
            font-weight: bold;
          }
          
          .balance-warning p {
            color: #d63031;
            font-size: 16px;
            margin-bottom: 0;
          }
          
          .balance-amount {
            font-size: 24px;
            font-weight: bold;
            color: #d63031;
            margin: 10px 0;
          }
          
          .action-buttons {
            text-align: center;
            margin-top: 30px;
          }
          
          .btn {
            display: inline-block;
            padding: 15px 30px;
            margin: 0 10px;
            border-radius: 10px;
            text-decoration: none;
            font-weight: bold;
            font-size: 16px;
            transition: all 0.3s ease;
          }
          
          .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
          }
          
          .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
          }
          
          .btn-secondary {
            background: #6c757d;
            color: white;
          }
          
          .btn-secondary:hover {
            background: #5a6268;
            transform: translateY(-2px);
          }
          
          .footer {
            background: #f8f9fa;
            padding: 30px;
            text-align: center;
            color: #6c757d;
            font-size: 14px;
          }
          
          .footer p {
            margin-bottom: 10px;
          }
          
          .logo {
            font-size: 24px;
            font-weight: bold;
            color: #667eea;
            margin-bottom: 10px;
          }
          
          @media (max-width: 600px) {
            .container {
              margin: 10px;
              border-radius: 15px;
            }
            
            .header, .content, .footer {
              padding: 20px;
            }
            
            .info-row {
              flex-direction: column;
              align-items: flex-start;
              gap: 5px;
            }
            
            .btn {
              display: block;
              margin: 10px 0;
            }
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>🚨 Group Leave Request</h1>
            <p>A member wants to leave your group</p>
          </div>
          
          <div class="content">
            <div class="alert-box">
              <h2>⚠️ Action Required</h2>
              <p><strong>${requestingUserEmail}</strong> has requested to leave your group "${groupDetails.title}".</p>
            </div>
            
            <div class="group-info">
              <h3>📋 Group Details</h3>
              <div class="info-row">
                <span class="info-label">Group Name:</span>
                <span class="info-value">${groupDetails.title}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Requesting Member:</span>
                <span class="info-value">${requestingUserEmail}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Total Members:</span>
                <span class="info-value">${groupDetails.members ? groupDetails.members.length : 0}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Total Expenses:</span>
                <span class="info-value">${groupDetails.expenses ? groupDetails.expenses.length : 0}</span>
              </div>
            </div>
            
            ${userBalance !== 0 ? `
            <div class="balance-warning">
              <h3>💰 Pending Balance</h3>
              <p>This member has pending expenses that need to be settled before they can leave.</p>
              <div class="balance-amount">$${userBalance.toFixed(2)}</div>
              <p>Please review and settle their expenses before approving the leave request.</p>
            </div>
            ` : `
            <div class="alert-box" style="background: linear-gradient(135deg, #d4edda 0%, #c3e6cb 100%); border-color: #28a745;">
              <h2 style="color: #155724;">✅ No Pending Balance</h2>
              <p style="color: #155724;">This member has no pending expenses and can safely leave the group.</p>
            </div>
            `}
            
                         <div class="action-buttons">
               <a href="mailto:${requestingUserEmail}" class="btn btn-secondary">
                 📧 Contact Member
               </a>
             </div>
          </div>
          
          <div class="footer">
            <div class="logo">Lenden</div>
            <p>Manage your group expenses efficiently</p>
            <p>This is an automated message. Please do not reply to this email.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    const mailOptions = {
      from: process.env.EMAIL_USER,
      to: creatorEmail,
      subject: `🚨 Group Leave Request: ${requestingUserEmail} wants to leave "${groupDetails.title}"`,
      html: htmlContent
    };

    await transporter.sendMail(mailOptions);
    return true;
  } catch (error) {
    console.error('Error sending group leave request email:', error);
    return false;
  }
};

module.exports = {
  sendGroupLeaveRequestEmail
};