const Transaction = require('../models/transaction');

const MIN_RESOLVED_TRANSACTIONS = 1;

async function computeTrustScore(email) {
  if (!email) return null;
  const normalizedEmail = email.toLowerCase();

  // Include ALL transactions — quick (no expectedReturnDate) and secure.
  const transactions = await Transaction.find({
    $or: [{ userEmail: normalizedEmail }, { counterpartyEmail: normalizedEmail }],
  }).select('userEmail counterpartyEmail userCleared counterpartyCleared expectedReturnDate');

  const now = Date.now();
  let good = 0;
  let bad = 0;

  for (const t of transactions) {
    const isUserSide = t.userEmail?.toLowerCase() === normalizedEmail;
    const theirSideCleared = isUserSide ? t.userCleared : t.counterpartyCleared;

    if (theirSideCleared) {
      // Cleared on either type counts as good.
      good += 1;
    } else if (t.expectedReturnDate) {
      // Only secure transactions can be judged as bad (overdue and uncleared).
      const overdue = new Date(t.expectedReturnDate).getTime() < now;
      if (overdue) bad += 1;
    }
    // Quick transactions that aren't cleared yet: skip (no due date to judge).
  }

  const resolved = good + bad;
  if (resolved < MIN_RESOLVED_TRANSACTIONS) {
    return {
      score: null,
      resolvedCount: resolved,
      label: 'Not enough history yet',
    };
  }

  const score = Math.round((good / resolved) * 100);
  let label;
  if (score >= 90) label = 'Excellent';
  else if (score >= 75) label = 'Good';
  else if (score >= 50) label = 'Fair';
  else label = 'Poor';

  return { score, resolvedCount: resolved, label };
}

module.exports = { computeTrustScore };
