const Transaction = require('../models/transaction');

const MIN_RESOLVED_TRANSACTIONS = 3;

/**
 * Repayment reliability score for a user, based on their secure-transaction
 * history. Only transactions with an expectedReturnDate are judgeable: a
 * transaction counts as "good" once the user's side is cleared, and as "bad"
 * once it's overdue (past expectedReturnDate) and still not cleared on their
 * side. Transactions that are neither yet (still pending, not yet due) are
 * excluded since no outcome can be judged.
 *
 * There's no clearedAt timestamp on Transaction, so this can't distinguish
 * "cleared on time" from "cleared late" — it only distinguishes
 * cleared-eventually from overdue-and-unresolved.
 */
async function computeTrustScore(email) {
  if (!email) return null;
  const normalizedEmail = email.toLowerCase();

  const transactions = await Transaction.find({
    $or: [{ userEmail: normalizedEmail }, { counterpartyEmail: normalizedEmail }],
    expectedReturnDate: { $ne: null },
  }).select('userEmail counterpartyEmail userCleared counterpartyCleared expectedReturnDate');

  const now = Date.now();
  let good = 0;
  let bad = 0;

  for (const t of transactions) {
    const isUserSide = t.userEmail?.toLowerCase() === normalizedEmail;
    const theirSideCleared = isUserSide ? t.userCleared : t.counterpartyCleared;
    const overdue = new Date(t.expectedReturnDate).getTime() < now;

    if (theirSideCleared) {
      good += 1;
    } else if (overdue) {
      bad += 1;
    }
    // else: still pending and not yet due — not judgeable, skip.
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
