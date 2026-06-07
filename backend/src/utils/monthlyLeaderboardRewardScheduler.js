const cron = require('node-cron');
const User = require('../models/user');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const MonthlyLeaderboardReward = require('../models/monthlyLeaderboardReward');
const { recordCoinLedgerEntry } = require('./coinLedgerService');

const RANK_REWARDS = {
  1: 20,
  2: 10,
  3: 5,
};

const toMonthKey = (date) => {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
};

const getPreviousMonthWindow = (anchorDate = new Date()) => {
  const start = new Date(anchorDate.getFullYear(), anchorDate.getMonth() - 1, 1);
  start.setHours(0, 0, 0, 0);
  const end = new Date(anchorDate.getFullYear(), anchorDate.getMonth(), 0);
  end.setHours(23, 59, 59, 999);
  return { start, end, monthKey: toMonthKey(start) };
};

const rankWithTies = (rows) => {
  let previousPoints = null;
  let rank = 0;
  return rows.map((row, idx) => {
    if (row.points !== previousPoints) {
      rank = idx + 1; // competition ranking
      previousPoints = row.points;
    }
    return { ...row, rank };
  });
};

const settlePreviousMonthRewards = async () => {
  const { start, end, monthKey } = getPreviousMonthWindow(new Date());

  const alreadyProcessed = await MonthlyLeaderboardReward.findOne({ monthKey });
  if (alreadyProcessed) {
    return;
  }

  const [quickRows, trxnsRows, groupRows] = await Promise.all([
    QuickTransaction.aggregate([
      { $match: { createdAt: { $gte: start, $lte: end } } },
      { $group: { _id: '$creatorEmail', count: { $sum: 1 } } },
    ]),
    Transaction.aggregate([
      { $match: { createdAt: { $gte: start, $lte: end } } },
      { $group: { _id: '$userEmail', count: { $sum: 1 } } },
    ]),
    GroupTransaction.aggregate([
      { $match: { createdAt: { $gte: start, $lte: end } } },
      { $group: { _id: '$creator', count: { $sum: 1 } } },
    ]),
  ]);

  const quickByEmail = new Map(
    quickRows.map((r) => [r._id?.toString(), Number(r.count) || 0])
  );
  const trxnsByEmail = new Map(
    trxnsRows.map((r) => [r._id?.toString(), Number(r.count) || 0])
  );
  const groupById = new Map(
    groupRows.map((r) => [r._id?.toString(), Number(r.count) || 0])
  );

  const emails = Array.from(
    new Set([...quickByEmail.keys(), ...trxnsByEmail.keys()].filter(Boolean))
  );
  const ids = Array.from(groupById.keys()).filter(Boolean);

  const usersByEmail = emails.length
    ? await User.find({ email: { $in: emails } }).select('_id email lenDenCoins')
    : [];
  const usersById = ids.length
    ? await User.find({ _id: { $in: ids } }).select('_id email lenDenCoins')
    : [];

  const userMap = new Map();
  usersByEmail.forEach((u) => userMap.set(u._id.toString(), u));
  usersById.forEach((u) => userMap.set(u._id.toString(), u));

  usersByEmail.forEach((u) => {
    const id = u._id.toString();
    const existing = userMap.get(id);
    if (!existing) userMap.set(id, u);
  });

  const scoreRows = [];
  userMap.forEach((user) => {
    const email = user.email?.toString();
    const id = user._id.toString();
    const quick = email ? quickByEmail.get(email) || 0 : 0;
    const trxns = email ? trxnsByEmail.get(email) || 0 : 0;
    const group = groupById.get(id) || 0;
    const points = (quick + trxns + group) * 10;
    if (points > 0) {
      scoreRows.push({ userId: id, points });
    }
  });

  scoreRows.sort((a, b) => b.points - a.points || a.userId.localeCompare(b.userId));
  const ranked = rankWithTies(scoreRows);
  const winners = ranked.filter((r) => r.rank <= 3);

  let totalCoinsAwarded = 0;
  const rewardedUsers = [];
  for (const winner of winners) {
    const reward = RANK_REWARDS[winner.rank] || 0;
    if (!reward) continue;
    const user = userMap.get(winner.userId);
    if (!user) continue;
    user.lenDenCoins = (user.lenDenCoins || 0) + reward;
    await user.save();
    await recordCoinLedgerEntry({
      userId: user._id,
      direction: 'earned',
      coins: reward,
      source: 'leaderboard_reward',
      title: 'Monthly Leaderboard Reward',
      description: `Earned ${reward} LenDen coins for finishing rank #${winner.rank} on the monthly leaderboard.`,
      metadata: {
        monthKey,
        rank: winner.rank,
        points: winner.points,
      },
      occurredAt: end,
    });
    totalCoinsAwarded += reward;
    rewardedUsers.push({
      user: user._id,
      rank: winner.rank,
      points: winner.points,
      coinsAwarded: reward,
    });
  }

  await MonthlyLeaderboardReward.create({
    monthKey,
    periodStart: start,
    periodEnd: end,
    rewardedUsers,
    totalCoinsAwarded,
  });
};

const initializeMonthlyLeaderboardRewardScheduler = () => {
  // Run at 00:10 every day; idempotent due to monthKey uniqueness.
  cron.schedule('10 0 * * *', async () => {
    try {
      await settlePreviousMonthRewards();
    } catch (error) {
      console.error('[MonthlyLeaderboardReward] Scheduler error:', error);
    }
  });

  // Run once on server startup so missed cron windows still settle.
  settlePreviousMonthRewards().catch((error) => {
    console.error('[MonthlyLeaderboardReward] Startup settlement error:', error);
  });

};

module.exports = {
  initializeMonthlyLeaderboardRewardScheduler,
  settlePreviousMonthRewards,
};
