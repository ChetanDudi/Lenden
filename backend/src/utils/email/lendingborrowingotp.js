const { sendEmail } = require('./sendEmailApi');
const User = require('../../models/user');
const { shouldSendNotification } = require('./shouldSendNotification');
const { shell, otpBlock } = require('./emailTemplate');
const OtpRecord = require('../../models/otpRecord');

function generateOtp() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

exports.sendDualOtp = async (email1, email2) => {
  const otp1 = generateOtp();
  const otp2 = generateOtp();
  await OtpRecord.findOneAndUpdate({ key: email1 }, { otp: otp1, createdAt: new Date() }, { upsert: true });
  await OtpRecord.findOneAndUpdate({ key: email2 }, { otp: otp2, createdAt: new Date() }, { upsert: true });
  await sendEmail({
    to: email1,
    subject: 'LenDen – Transaction Verification',
    text: `Your OTP for transaction confirmation is: ${otp1}\nThis OTP will expire in 2 minutes.`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Verification</p>
      <p style="margin:0 0 16px;">A secure transaction requires your verification. Enter the code below in the app to confirm your participation.</p>
      ${otpBlock(otp1)}
      <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
      <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not initiate this transaction, please ignore this email.</p>
    `),
  });
  await sendEmail({
    to: email2,
    subject: 'LenDen – Transaction Verification',
    text: `Your OTP for transaction confirmation is: ${otp2}\nThis OTP will expire in 2 minutes.`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Verification</p>
      <p style="margin:0 0 16px;">A secure transaction requires your verification. Enter the code below in the app to confirm your participation.</p>
      ${otpBlock(otp2)}
      <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
      <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not initiate this transaction, please ignore this email.</p>
    `),
  });
  return { otp1, otp2 };
};

exports.verifyDualOtp = async (email1, otp1Input, email2, otp2Input) => {
  const rec1 = await OtpRecord.findOne({ key: email1 });
  const rec2 = await OtpRecord.findOne({ key: email2 });
  if (!rec1 || !rec2) return { valid: false, reason: 'OTP not found' };
  if (rec1.otp === otp1Input && rec2.otp === otp2Input) {
    await OtpRecord.deleteOne({ key: email1 });
    await OtpRecord.deleteOne({ key: email2 });
    return { valid: true };
  }
  return { valid: false, reason: 'OTP invalid' };
};

exports.resendOtp = async (email) => {
  const otp = generateOtp();
  await OtpRecord.findOneAndUpdate({ key: email }, { otp, createdAt: new Date() }, { upsert: true });
  await sendEmail({
    to: email,
    subject: 'LenDen – Transaction Verification (Resend)',
    text: `Your OTP for transaction confirmation is: ${otp}\nThis OTP will expire in 2 minutes.`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Verification</p>
      <p style="margin:0 0 16px;">A new verification code has been sent as requested.</p>
      ${otpBlock(otp)}
      <p style="margin:0 0 8px;">Do not share this code with anyone.</p>
      <p style="margin:16px 0 0;color:#888888;font-size:13px;">If you did not initiate this transaction, please ignore this email.</p>
    `),
  });
  return otp;
};

exports.verifyLendingBorrowingOtp = async (email, otp) => {
  const record = await OtpRecord.findOne({ key: email });
  if (!record) return false;
  if (record.otp === otp) {
    await OtpRecord.deleteOne({ key: email });
    return true;
  }
  return false;
};

// Server-side record that a given role ('lender'/'borrower') on a given
// secure transaction has completed OTP verification — so processPartialPayment
// can check this instead of trusting client-sent lenderOtpVerified/
// borrowerOtpVerified booleans, which could otherwise be set to true without
// ever calling verifyPartialPaymentOTP. Short TTL gives both parties time to
// verify before the deduction call, but expires unused verifications.
const partialPaymentVerifiedStore = {};
const PARTIAL_PAYMENT_VERIFIED_TTL_MS = 10 * 60 * 1000;

exports.markPartialPaymentVerified = (transactionId, role) => {
  partialPaymentVerifiedStore[`${transactionId}:${role}`] = { verifiedAt: Date.now() };
};

exports.isPartialPaymentVerified = (transactionId, role) => {
  const key = `${transactionId}:${role}`;
  const record = partialPaymentVerifiedStore[key];
  if (!record) return false;
  if (Date.now() - record.verifiedAt > PARTIAL_PAYMENT_VERIFIED_TTL_MS) {
    delete partialPaymentVerifiedStore[key];
    return false;
  }
  return true;
};

exports.consumePartialPaymentVerified = (transactionId) => {
  delete partialPaymentVerifiedStore[`${transactionId}:lender`];
  delete partialPaymentVerifiedStore[`${transactionId}:borrower`];
};

exports.sendTransactionReceipt = async (email, transaction, counterpartyNameOrEmail) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.transactionNotifications || !shouldSendNotification(user)) {
    return;
  }

  const {
    amount, currency, date, time, place, role, interestType, interestRate, expectedReturnDate, compoundingFrequency, transactionId
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

  const _row = (label, value, shaded) =>
    `<tr${shaded ? ' style="background:#f7f7f7;"' : ''}>
      <td style="padding:10px 16px;font-weight:bold;color:#555555;width:45%;border-bottom:1px solid #e0e0e0;">${label}</td>
      <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${value}</td>
    </tr>`;

  const rows = [
    ['Amount', `${amount} ${currency}`],
    ['Date', date ? new Date(date).toLocaleDateString('en-IN') : ''],
    ['Time', time || ''],
    ['Place', place || ''],
    ['Counterparty', counterpartyNameOrEmail],
    ...(interestInfo ? [['Interest', interestInfo]] : []),
    ...(expectedReturnDate ? [['Expected Return Date', new Date(expectedReturnDate).toLocaleDateString('en-IN')]] : []),
    ...(interestInfo && expectedReturnDate ? [['Expected Amount', `${expectedAmount.toFixed(2)} ${currency}`]] : []),
    ['Transaction ID', transactionId],
  ];

  await sendEmail({
    to: email,
    subject: `LenDen – Transaction Receipt (${transactionId})`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Receipt</p>
      <p style="margin:0 0 24px;">Your transaction has been recorded. Below is a summary for your reference.</p>
      <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:16px;">
        ${rows.map(([l, v], i) => _row(l, v, i % 2 === 0)).join('')}
      </table>
    `),
  });
};

exports.sendTransactionClearedNotification = async (email, transaction, clearedByEmail) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.transactionNotifications || !shouldSendNotification(user)) {
    return;
  }

  const { amount, currency, date, time, place, transactionId, userCleared, counterpartyCleared } = transaction;
  const fullyCleared = userCleared && counterpartyCleared;

  const _row = (label, value, shaded) =>
    `<tr${shaded ? ' style="background:#f7f7f7;"' : ''}>
      <td style="padding:10px 16px;font-weight:bold;color:#555555;width:45%;border-bottom:1px solid #e0e0e0;">${label}</td>
      <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${value}</td>
    </tr>`;

  await sendEmail({
    to: email,
    subject: `LenDen – Transaction Clearance Update (${transactionId})`,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Transaction Clearance Update</p>
      <p style="margin:0 0 24px;">The clearance status of your transaction has been updated.</p>
      <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:24px;">
        ${_row('Amount', `${amount} ${currency}`, true)}
        ${_row('Date', date ? new Date(date).toLocaleDateString('en-IN') : '', false)}
        ${_row('Place', place || '', true)}
        ${_row('Transaction ID', transactionId, false)}
        ${_row('Cleared by', clearedByEmail, true)}
        ${_row('Status', fullyCleared ? 'Fully Cleared — both parties have confirmed.' : 'Partially cleared — pending confirmation from your side.', false)}
      </table>
      ${!fullyCleared ? '<p style="margin:0;color:#555555;">Please open the app and confirm clearance on your side to fully close this transaction.</p>' : ''}
    `),
  });
};

exports.sendReminderEmail = async (email, transaction, daysLeft) => {
  const user = await User.findOne({ email });
  if (!user || !user.notificationSettings.emailNotifications || !user.notificationSettings.paymentReminders || !shouldSendNotification(user)) {
    return;
  }

  const subject = daysLeft === 0
    ? 'LenDen – Payment Due Today'
    : `LenDen – Payment Due in ${daysLeft} Day${daysLeft === 1 ? '' : 's'}`;

  const dueLabel = daysLeft === 0 ? 'today' : `in ${daysLeft} day${daysLeft === 1 ? '' : 's'}`;

  const _row = (label, value, shaded) =>
    `<tr${shaded ? ' style="background:#f7f7f7;"' : ''}>
      <td style="padding:10px 16px;font-weight:bold;color:#555555;width:45%;border-bottom:1px solid #e0e0e0;">${label}</td>
      <td style="padding:10px 16px;color:#222222;border-bottom:1px solid #e0e0e0;">${value}</td>
    </tr>`;

  await sendEmail({
    to: email,
    subject,
    html: shell(`
      <p style="margin:0 0 16px;font-size:16px;font-weight:bold;color:#111;">Payment Reminder</p>
      <p style="margin:0 0 16px;">This is a reminder that your transaction of <strong>&#8377;${transaction.amount}</strong> (${transaction.type}) is due <strong>${dueLabel}</strong>.</p>
      <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border:1px solid #e0e0e0;margin-bottom:24px;">
        ${_row('Transaction ID', transaction._id, true)}
        ${_row('Counterparty', transaction.counterpartyEmail, false)}
        ${_row('Place', transaction.place || '', true)}
        ${_row('Due Date', transaction.expectedReturnDate ? new Date(transaction.expectedReturnDate).toLocaleDateString('en-IN') : 'N/A', false)}
      </table>
      <p style="margin:0;color:#555555;">Please ensure timely settlement to maintain a good record on LenDen.</p>
    `),
  });
};
