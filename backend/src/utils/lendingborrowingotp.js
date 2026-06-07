const nodemailer = require('nodemailer');
const User = require('../models/user');
const { shouldSendNotification } = require('./shouldSendNotification');

const otpStore = {};

const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

function getStylishOtpHtml(otp) {
  return `
    <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 480px; margin: auto;">
      <h2 style="color: #00B4D8; text-align: center;">Lenden Transaction OTP</h2>
      <p style="font-size: 16px; color: #333; text-align: center;">Your OTP for transaction confirmation is:</p>
      <div style="font-size: 32px; font-weight: bold; color: #00B4D8; text-align: center; margin: 24px 0; letter-spacing: 4px;">${otp}</div>
      <p style="font-size: 14px; color: #888; text-align: center;">This OTP is valid for 2 minutes. If you did not request this, please ignore this email.</p>
      <div style="text-align: center; margin-top: 24px;">
        <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
      </div>
    </div>
  `;
}

exports.sendDualOtp = async (email1, email2) => {
  const otp1 = generateOtp();
  const otp2 = generateOtp();
  const expires = Date.now() + 2 * 60 * 1000; // 2 minutes
  otpStore[email1] = {otp: otp1, expires };
  otpStore[email2] = {otp: otp2, expires };
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email1,
    subject: 'Lending/Borrowing OTP Verification',
    text: `Your OTP for transaction confirmation is: ${otp1}\nThis OTP will expire in 2 minutes.`, 
    html: getStylishOtpHtml(otp1),
  });
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email2,
    subject: 'Lending/Borrowing OTP Verification',
    text: `Your OTP for transaction confirmation is: ${otp2}\nThis OTP will expire in 2 minutes.`, 
    html: getStylishOtpHtml(otp2),
  });
  return {otp1, otp2 };
};

exports.verifyDualOtp = (email1, otp1, email2, otp2) => {
  const rec1 = otpStore[email1];
  const rec2 = otpStore[email2];
  const now = Date.now();
  if (!rec1 || !rec2) return { valid: false, reason: 'OTP not found' };
  if (now > rec1.expires || now > rec2.expires) return { valid: false, reason: 'OTP expired' };
  if (rec1.otp === otp1 && rec2.otp === otp2) {
    delete otpStore[email1];
    delete otpStore[email2];
    return { valid: true };
  }
  return { valid: false, reason: 'OTP invalid' };
};

exports.resendOtp = async (email) => {
  const otp = generateOtp();
  const expires = Date.now() + 2 * 60 * 1000;
  otpStore[email] = {otp, expires };
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email,
    subject: 'Lending/Borrowing OTP Verification (Resend)',
    text: `Your OTP for transaction confirmation is: ${otp}\nThis OTP will expire in 2 minutes.`, 
    html: getStylishOtpHtml(otp),
  });
  return otp;
};

exports.verifyLendingBorrowingOtp = (email, otp) => {
  const record = otpStore[email];
  if (!record) return false;
  if (record.otp === otp && Date.now() < record.expires) {
    delete otpStore[email];
    return true;
  }
  return false;
};

exports.sendTransactionReceipt = async (email, transaction, counterpartyNameOrEmail) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.transactionNotifications || !shouldSendNotification(user)) {
    return; // Do not send email if notifications are disabled or in quiet hours
  }

  const {
    amount, currency, date, time, place, counterpartyEmail, userEmail, role, interestType, interestRate, expectedReturnDate, compoundingFrequency, transactionId
  } = transaction;
  let interestInfo = '';
  let expectedAmount = amount;
  let freqLabel = '';
  if (interestType && interestRate && expectedReturnDate) {
    const principal = amount;
    const rate = interestRate;
    const start = new Date(date);
    const end = new Date(expectedReturnDate);
    const years = (end - start) / (1000 * 60 * 60 * 24 * 365);
    if (interestType === 'simple') {
      expectedAmount = principal + (principal * rate * years / 100);
      interestInfo = `Simple Interest @ ${rate}%`;
    } else if (interestType === 'compound') {
      let n = compoundingFrequency || 1;
      if (n === 1) freqLabel = 'Annually';
      else if (n === 2) freqLabel = 'Semi-annually';
      else if (n === 4) freqLabel = 'Quarterly';
      else if (n === 12) freqLabel = 'Monthly';
      else freqLabel = `${n}x/year`;
      expectedAmount = principal * Math.pow(1 + rate / 100 / n, n * years);
      interestInfo = `Compound Interest @ ${rate}% (${freqLabel})`;
    }
  }
  const html = `
    <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 520px; margin: auto;">
      <h2 style="color: #00B4D8; text-align: center;">Lenden Transaction Receipt</h2>
      <div style="background: #fff; border-radius: 10px; padding: 20px; box-shadow: 0 2px 8px #00B4D820;">
        <p style="font-size: 18px; color: #333; margin-bottom: 8px;"><b>Amount:</b> ${amount} ${currency}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Date:</b> ${date ? new Date(date).toLocaleDateString() : ''} <b>Time:</b> ${time || ''}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Place:</b> ${place || ''}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Counterparty:</b> ${counterpartyNameOrEmail}</p>
        ${interestInfo ? `<p style='font-size: 16px; color: #333; margin-bottom: 8px;'><b>Interest:</b> ${interestInfo}</p>` : ''}
        ${expectedReturnDate ? `<p style='font-size: 16px; color: #333; margin-bottom: 8px;'><b>Expected Return Date:</b> ${new Date(expectedReturnDate).toLocaleDateString()}</p>` : ''}
        ${(interestInfo && expectedReturnDate) ? `<p style='font-size: 16px; color: #333; margin-bottom: 8px;'><b>Expected Amount to be Paid:</b> ${expectedAmount.toFixed(2)} ${currency}</p>` : ''}
        <p style="font-size: 14px; color: #888; margin-bottom: 8px;"><b>Transaction ID:</b> ${transactionId}</p>
      </div>
      <div style="text-align: center; margin-top: 24px;">
        <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
      </div>
    </div>
  `;
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email,
    subject: 'Lenden Transaction Receipt',
    html
  });
};

exports.sendTransactionClearedNotification = async (email, transaction, clearedByEmail) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.transactionNotifications || !shouldSendNotification(user)) {
    return; // Do not send email if notifications are disabled or in quiet hours
  }

  const {
    amount, currency, date, time, place, counterpartyEmail, userEmail, role, transactionId, userCleared, counterpartyCleared
  } = transaction;
  const fullyCleared = userCleared && counterpartyCleared;
  const html = `
    <div style="font-family: Arial, sans-serif; background: #f8f6fa; padding: 24px; border-radius: 12px; max-width: 520px; margin: auto;">
      <h2 style="color: #00B4D8; text-align: center;">Lenden Transaction Clearance Update</h2>
      <div style="background: #fff; border-radius: 10px; padding: 20px; box-shadow: 0 2px 8px #00B4D820;">
        <p style="font-size: 18px; color: #333; margin-bottom: 8px;"><b>Amount:</b> ${amount} ${currency}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Date:</b> ${date ? new Date(date).toLocaleDateString() : ''} <b>Time:</b> ${time || ''}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Place:</b> ${place || ''}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Transaction ID:</b> ${transactionId}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Cleared by:</b> ${clearedByEmail}</p>
        <p style="font-size: 16px; color: #333; margin-bottom: 8px;"><b>Status:</b> ${fullyCleared ? '<span style=\'color:green\'>Fully Cleared (Both parties have cleared)</span>' : 'Pending clearance from the your side'}</p>
      </div>
      <div style="text-align: center; margin-top: 24px;">
        <span style="font-size: 12px; color: #aaa;">&copy; Lenden App</span>
      </div>
    </div>
  `;
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email,
    subject: 'Lenden Transaction Clearance Update',
    html
  });
};

exports.sendReminderEmail = async (email, transaction, daysLeft) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.paymentReminders || !shouldSendNotification(user)) {
    return; // Do not send email if notifications are disabled or in quiet hours
  }

  const nodemailer = require('nodemailer');
  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.EMAIL_USER,
      pass: process.env.EMAIL_PASS
    }
  });
  const subject = daysLeft === 0
    ? `Lenden: Today is the due date for your transaction!`
    : `Lenden: Your transaction is due in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`;
  const html = `
    <div style="font-family: 'Segoe UI', Arial, sans-serif; background: #f8f6fa; padding: 32px; border-radius: 16px; max-width: 500px; margin: auto;">
      <h2 style="color: #00b4d8;">Lenden Reminder</h2>
      <p style="font-size: 18px; color: #333;">Hi <b>${transaction.counterpartyName || 'User'}</b>,</p>
      <p style="font-size: 16px;">This is a friendly reminder that your transaction of <b>₹${transaction.amount}</b> (${transaction.type}) is due <b>${daysLeft === 0 ? 'today' : `in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`}</b>.</p>
      <ul style="font-size: 15px; color: #444;">
        <li><b>Transaction ID:</b> ${transaction._id}</li>
        <li><b>Counterparty:</b> ${transaction.counterpartyEmail}</li>
        <li><b>Place:</b> ${transaction.place}</li>
        <li><b>Expected Return Date:</b> ${transaction.expectedReturnDate ? new Date(transaction.expectedReturnDate).toLocaleDateString() : 'N/A'}</li>
      </ul>
      <p style="margin-top: 24px; font-size: 15px; color: #555;">Please ensure timely settlement to maintain a good record.</p>
      <div style="margin-top: 32px; text-align: center;">
        <a href="https://lenden.app" style="background: #00b4d8; color: #fff; padding: 12px 32px; border-radius: 24px; text-decoration: none; font-weight: bold;">Go to Lenden</a>
      </div>
      <p style="margin-top: 32px; font-size: 13px; color: #aaa;">This is an automated reminder from Lenden. Please do not reply to this email.</p>
    </div>
  `;
  await transporter.sendMail({
    from: process.env.EMAIL_USER,
    to: email,
    subject,
    html
  });
};
