const { sendEmail } = require('./sendEmailApi');
const { shell, otpBlock, alertBox } = require('./emailTemplate');

exports.sendWalletPinSetupOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Wallet PIN Setup Verification',
    text: `Your OTP to set up your LenDen Wallet PIN is: ${otp}\nThis code expires in 2 minutes. If you did not request this, please ignore this email.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Wallet PIN Setup</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">You have initiated a Wallet PIN setup on your LenDen account. Enter the verification code below to proceed. Your PIN will be used to authorise wallet transactions.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen will never ask for your OTP or PIN.</p>
        ${alertBox('If you did not request this, please ignore this email. No changes will be made to your account.', 'error')}
      `),
  });
};

exports.sendWalletTransactionAuthOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Wallet Transaction Authorisation',
    text: `Your OTP to authorise this wallet transaction is: ${otp}\nThis code expires in 2 minutes. If you did not initiate this, please contact support immediately.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Wallet Transaction Authorisation</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">A wallet transaction is awaiting your authorisation on LenDen. Enter the verification code below in the app to approve and complete it.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone. LenDen will never ask for your OTP.</p>
        ${alertBox('If you did not initiate this transaction, do not share this code and contact LenDen support immediately.', 'error')}
      `),
  });
};

exports.sendWalletPayOTP = async (to, otp, username) => {
  return sendEmail({
    to,
    subject: 'LenDen – Wallet Payment Authorisation',
    text: `Your OTP to authorise this wallet payment is: ${otp}\nThis code expires in 2 minutes. If you did not initiate this payment, please contact support immediately.`,
    html: shell(`
        <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Wallet Payment Authorisation</p>
        <p style="margin:0 0 16px;">Dear ${username},</p>
        <p style="margin:0 0 16px;">A wallet payment has been initiated from your LenDen account. Enter the code below in the app to authorise and complete the transaction.</p>
        ${otpBlock(otp)}
        <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
        ${alertBox('If you did not initiate this payment, do not share this code and contact LenDen support immediately.', 'error')}
      `),
  });
};
