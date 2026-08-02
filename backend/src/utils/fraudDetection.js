const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const User = require('../models/user');
const Dispute = require('../models/dispute');
const FraudAlert = require('../models/fraudAlert');

const HIGH_VALUE_THRESHOLD = 200000;
const NEW_ACCOUNT_WINDOW_MS = 48 * 60 * 60 * 1000;
const VELOCITY_WINDOW_MS = 60 * 60 * 1000;
const VELOCITY_THRESHOLD = 8;
const SHARED_DEVICE_MIN_ACCOUNTS = 3;
const SHARED_DEVICE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const REPEATED_DISPUTE_THRESHOLD = 3;
const REPEATED_DISPUTE_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;
const SCAN_LOOKBACK_MS = 24 * 60 * 60 * 1000;

async function upsertAlert({ type, severity, targetEmail, relatedEmails, relatedTransactionType, relatedTransactionId, description, details }) {
  const existing = await FraudAlert.findOne({ type, targetEmail, status: { $in: ['open', 'reviewing'] } });
  if (existing) {
    existing.occurrenceCount += 1;
    existing.lastDetectedAt = new Date();
    existing.details = details;
    await existing.save();
    return { alert: existing, isNew: false };
  }
  const alert = await FraudAlert.create({
    type, severity, targetEmail, relatedEmails, relatedTransactionType, relatedTransactionId, description, details,
  });
  return { alert, isNew: true };
}

// Same email used as both sides of a secure transaction should never happen
// and most plausibly indicates a manipulated request rather than a real loan.
async function detectSelfTransactions(since) {
  const results = [];
  const txs = await Transaction.find({
    createdAt: { $gte: since },
    $expr: { $eq: [{ $toLower: '$userEmail' }, { $toLower: '$counterpartyEmail' }] },
  }).select('userEmail amount transactionId');

  for (const t of txs) {
    results.push(await upsertAlert({
      type: 'self_transaction',
      severity: 'high',
      targetEmail: t.userEmail,
      relatedTransactionType: 'secure',
      relatedTransactionId: t._id,
      description: `Transaction ${t.transactionId} has the same email on both sides (${t.userEmail}).`,
      details: { amount: t.amount },
    }));
  }
  return results;
}

// A brand-new account immediately moving a large amount is a classic
// account-takeover / mule-account signal.
async function detectLargeAmountNewAccounts(since) {
  const results = [];
  const txs = await Transaction.find({
    createdAt: { $gte: since },
    amount: { $gte: HIGH_VALUE_THRESHOLD },
  }).select('userEmail amount transactionId createdAt');

  for (const t of txs) {
    const user = await User.findOne({ email: t.userEmail }).select('createdAt');
    if (user?.createdAt && (t.createdAt - user.createdAt) < NEW_ACCOUNT_WINDOW_MS) {
      results.push(await upsertAlert({
        type: 'large_amount_new_account',
        severity: 'critical',
        targetEmail: t.userEmail,
        relatedTransactionType: 'secure',
        relatedTransactionId: t._id,
        description: `Account created ${user.createdAt.toDateString()} raised a transaction of ${t.amount} within 48 hours of signup.`,
        details: { amount: t.amount, accountCreatedAt: user.createdAt },
      }));
    }
  }
  return results;
}

// Unusually rapid transaction creation by one user, across both secure and
// quick transactions, can indicate scripted/automated abuse.
async function detectHighVelocity() {
  const results = [];
  const windowStart = new Date(Date.now() - VELOCITY_WINDOW_MS);

  const counts = new Map();
  const secureCounts = await Transaction.aggregate([
    { $match: { createdAt: { $gte: windowStart } } },
    { $group: { _id: '$userEmail', count: { $sum: 1 } } },
  ]);
  const quickCounts = await QuickTransaction.aggregate([
    { $match: { createdAt: { $gte: windowStart } } },
    { $group: { _id: '$creatorEmail', count: { $sum: 1 } } },
  ]);
  for (const row of [...secureCounts, ...quickCounts]) {
    if (!row._id) continue;
    counts.set(row._id, (counts.get(row._id) || 0) + row.count);
  }

  for (const [email, count] of counts.entries()) {
    if (count < VELOCITY_THRESHOLD) continue;
    results.push(await upsertAlert({
      type: 'high_velocity',
      severity: 'medium',
      targetEmail: email,
      description: `${email} created ${count} transactions within the last hour (threshold: ${VELOCITY_THRESHOLD}).`,
      details: { count, windowMinutes: 60 },
    }));
  }
  return results;
}

// Multiple distinct accounts logging in from the same device/IP within a
// month suggests a fake-account ring rather than coincidence.
async function detectSharedDevices() {
  const results = [];
  const windowStart = new Date(Date.now() - SHARED_DEVICE_WINDOW_MS);

  const users = await User.find({ 'devices.lastActive': { $gte: windowStart } })
    .select('email devices');

  const byDeviceId = new Map();
  for (const user of users) {
    for (const device of user.devices || []) {
      if (!device.deviceId || !device.lastActive || device.lastActive < windowStart) continue;
      if (!byDeviceId.has(device.deviceId)) byDeviceId.set(device.deviceId, new Set());
      byDeviceId.get(device.deviceId).add(user.email);
    }
  }

  for (const [deviceId, emails] of byDeviceId.entries()) {
    if (emails.size < SHARED_DEVICE_MIN_ACCOUNTS) continue;
    const emailList = Array.from(emails);
    results.push(await upsertAlert({
      type: 'shared_device',
      severity: 'medium',
      targetEmail: emailList[0],
      relatedEmails: emailList,
      description: `${emailList.length} different accounts shared device ${deviceId} in the last 30 days.`,
      details: { deviceId, accountCount: emailList.length },
    }));
  }
  return results;
}

// A user repeatedly named as the respondent in disputes is worth a manual
// look, regardless of how each individual dispute was resolved.
async function detectRepeatedDisputes() {
  const results = [];
  const windowStart = new Date(Date.now() - REPEATED_DISPUTE_WINDOW_MS);

  const counts = await Dispute.aggregate([
    { $match: { createdAt: { $gte: windowStart }, respondentEmail: { $ne: '' } } },
    { $group: { _id: '$respondentEmail', count: { $sum: 1 } } },
    { $match: { count: { $gte: REPEATED_DISPUTE_THRESHOLD } } },
  ]);

  for (const row of counts) {
    results.push(await upsertAlert({
      type: 'repeated_disputes',
      severity: 'high',
      targetEmail: row._id,
      description: `${row._id} has been named respondent in ${row.count} disputes over the last 90 days.`,
      details: { count: row.count },
    }));
  }
  return results;
}

async function runFraudScan() {
  const since = new Date(Date.now() - SCAN_LOOKBACK_MS);
  const [selfTx, largeNew, velocity, sharedDevices, repeatedDisputes] = await Promise.all([
    detectSelfTransactions(since),
    detectLargeAmountNewAccounts(since),
    detectHighVelocity(),
    detectSharedDevices(),
    detectRepeatedDisputes(),
  ]);
  const all = [...selfTx, ...largeNew, ...velocity, ...sharedDevices, ...repeatedDisputes];
  return {
    total: all.length,
    newAlerts: all.filter((r) => r.isNew).map((r) => r.alert),
    updatedAlerts: all.filter((r) => !r.isNew).map((r) => r.alert),
  };
}

module.exports = { runFraudScan };
