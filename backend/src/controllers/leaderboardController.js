const User = require('../models/user');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const MonthlyLeaderboardReward = require('../models/monthlyLeaderboardReward');

const normalizeType = (type) => {
  if (type === 'quick') return 'quick';
  if (type === 'group') return 'group';
  return 'trxns';
};

const normalizeRange = (range) => {
  if (range === 'weekly') return 'weekly';
  if (range === 'monthly') return 'monthly';
  return 'daily';
};

const getRangeWindow = (range, anchorDate = new Date()) => {
  const start = new Date(anchorDate);
  const end = new Date(anchorDate);

  if (range === 'weekly') {
    const day = start.getDay(); // 0..6 (Sun..Sat)
    const diffToMonday = (day + 6) % 7;
    start.setDate(start.getDate() - diffToMonday);
    start.setHours(0, 0, 0, 0);
    end.setTime(start.getTime());
    end.setDate(end.getDate() + 6);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  if (range === 'monthly') {
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
    end.setMonth(start.getMonth() + 1, 0);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  start.setHours(0, 0, 0, 0);
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

const getPreviousRangeWindow = (range, currentStart) => {
  if (range === 'weekly') {
    const start = new Date(currentStart);
    start.setDate(start.getDate() - 7);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setDate(end.getDate() + 6);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  if (range === 'monthly') {
    const start = new Date(currentStart);
    start.setMonth(start.getMonth() - 1, 1);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start);
    end.setMonth(start.getMonth() + 1, 0);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  const start = new Date(currentStart);
  start.setDate(start.getDate() - 1);
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

const calculateRanks = (items) => {
  const ranked = [];
  let previousCount = null;
  let currentRank = 0;
  for (let i = 0; i < items.length; i += 1) {
    if (items[i].count !== previousCount) {
      currentRank += 1; // dense ranking: 1,2,2,3
      previousCount = items[i].count;
    }
    ranked.push({ ...items[i], rank: currentRank });
  }
  return ranked;
};

const selectTopWithTies = (ranked, maxRank = 10) => {
  return ranked.filter((r) => r.rank <= maxRank);
};

const aggregateQuickCounts = async (start, end, allowedEmails = null) => {
  const match = { createdAt: { $gte: start, $lte: end } };
  if (allowedEmails) {
    match.creatorEmail = { $in: allowedEmails };
  }
  const rows = await QuickTransaction.aggregate([
    { $match: match },
    { $group: { _id: '$creatorEmail', count: { $sum: 1 } } },
    { $sort: { count: -1, _id: 1 } },
  ]);
  return rows.map((r) => ({ key: r._id, count: r.count }));
};

const aggregateTrxnsCounts = async (start, end, allowedEmails = null) => {
  const match = { createdAt: { $gte: start, $lte: end } };
  if (allowedEmails) {
    match.userEmail = { $in: allowedEmails };
  }
  const rows = await Transaction.aggregate([
    { $match: match },
    { $group: { _id: '$userEmail', count: { $sum: 1 } } },
    { $sort: { count: -1, _id: 1 } },
  ]);
  return rows.map((r) => ({ key: r._id, count: r.count }));
};

const aggregateGroupCounts = async (start, end, allowedIds = null) => {
  const match = { createdAt: { $gte: start, $lte: end } };
  if (allowedIds) {
    match.creator = { $in: allowedIds };
  }
  const rows = await GroupTransaction.aggregate([
    { $match: match },
    { $group: { _id: '$creator', count: { $sum: 1 } } },
    { $sort: { count: -1, _id: 1 } },
  ]);
  return rows.map((r) => ({ key: r._id?.toString(), count: r.count }));
};

const mapFromCounts = (rows) => {
  const map = new Map();
  rows.forEach((r) => map.set(r.key?.toString(), r.count));
  return map;
};

const previousRankMap = (rows) => {
  const ranked = calculateRanks(rows);
  const map = new Map();
  ranked.forEach((r) => map.set(r.key?.toString(), r.rank));
  return map;
};

const movementFromRanks = (currentRank, prevRank) => {
  if (!prevRank) {
    return { direction: 'new', delta: 0 };
  }
  if (prevRank > currentRank) {
    return { direction: 'up', delta: prevRank - currentRank };
  }
  if (prevRank < currentRank) {
    return { direction: 'down', delta: currentRank - prevRank };
  }
  return { direction: 'same', delta: 0 };
};

exports.getDailyLeaderboard = async (req, res) => {
  try {
    const type = normalizeType(req.query.type);
    const range = normalizeRange(req.query.range);
    const friendsOnly = String(req.query.friendsOnly || 'false') === 'true';

    const { start, end } = getRangeWindow(range, new Date());
    const { start: prevStart, end: prevEnd } = getPreviousRangeWindow(
      range,
      start
    );

    let allowedEmails = null;
    let allowedIds = null;
    let userScope = null;

    if (friendsOnly) {
      const me = await User.findById(req.user._id).select('_id friends');
      if (!me) return res.status(404).json({ error: 'User not found' });

      const friendIds = (me.friends || []).map((id) => id.toString());
      const scopedIds = Array.from(new Set([me._id.toString(), ...friendIds]));
      const scopedUsers = await User.find({ _id: { $in: scopedIds } }).select(
        '_id email'
      );

      allowedIds = scopedUsers.map((u) => u._id);
      allowedEmails = scopedUsers
        .map((u) => u.email)
        .filter((email) => Boolean(email));
      userScope = new Set(scopedUsers.map((u) => u._id.toString()));
    }

    let currentRows = [];
    let previousRows = [];
    if (type === 'quick') {
      currentRows = await aggregateQuickCounts(start, end, allowedEmails);
      previousRows = await aggregateQuickCounts(prevStart, prevEnd, allowedEmails);
    } else if (type === 'group') {
      currentRows = await aggregateGroupCounts(start, end, allowedIds);
      previousRows = await aggregateGroupCounts(prevStart, prevEnd, allowedIds);
    } else {
      currentRows = await aggregateTrxnsCounts(start, end, allowedEmails);
      previousRows = await aggregateTrxnsCounts(prevStart, prevEnd, allowedEmails);
    }

    const ranked = calculateRanks(currentRows);
    const topWithTies = selectTopWithTies(ranked, 10);
    const prevMap = previousRankMap(previousRows);

    const topKeys = topWithTies.map((r) => r.key?.toString()).filter(Boolean);
    let users = [];
    if (type === 'group') {
      users = await User.find({ _id: { $in: topKeys }, 'privacySettings.leaderboardVisible': { $ne: false } }).select(
        '_id name email gender profileImage'
      );
    } else {
      users = await User.find({ email: { $in: topKeys }, 'privacySettings.leaderboardVisible': { $ne: false } }).select(
        '_id name email gender profileImage'
      );
    }

    if (userScope) {
      users = users.filter((u) => userScope.has(u._id.toString()));
    }

    const byId = new Map(users.map((u) => [u._id.toString(), u]));
    const byEmail = new Map(users.map((u) => [u.email, u]));

    const rowUsers = topWithTies
      .map((r) => {
        const user =
          type === 'group'
            ? byId.get(r.key?.toString())
            : byEmail.get(r.key?.toString());
        if (!user) return null;
        const prevRank = prevMap.get(r.key?.toString());
        const movement = movementFromRanks(r.rank, prevRank);
        return {
          rank: r.rank,
          previousRank: prevRank || null,
          movement,
          userId: user._id,
          email: user.email || null,
          isCurrentUser: user._id.toString() === req.user._id.toString(),
          name: user.name || 'Unknown User',
          gender: user.gender || 'Other',
          count: r.count,
          points: r.count * 10,
        };
      })
      .filter(Boolean);

    // Points breakdown for users returned in leaderboard.
    const leaderboardUserIds = rowUsers.map((u) => u.userId.toString());
    const leaderboardEmails = users
      .filter((u) => leaderboardUserIds.includes(u._id.toString()))
      .map((u) => u.email)
      .filter(Boolean);

    const [quickBreakdownRows, trxnsBreakdownRows, groupBreakdownRows] =
      await Promise.all([
        aggregateQuickCounts(start, end, leaderboardEmails),
        aggregateTrxnsCounts(start, end, leaderboardEmails),
        aggregateGroupCounts(start, end, leaderboardUserIds),
      ]);

    const quickMap = mapFromCounts(quickBreakdownRows);
    const trxnsMap = mapFromCounts(trxnsBreakdownRows);
    const groupMap = mapFromCounts(groupBreakdownRows);

    const enrichedRows = rowUsers.map((row) => {
      const user = byId.get(row.userId.toString());
      const emailKey = user?.email?.toString();
      const idKey = row.userId.toString();
      const quickCount = emailKey ? quickMap.get(emailKey) || 0 : 0;
      const trxnsCount = emailKey ? trxnsMap.get(emailKey) || 0 : 0;
      const groupCount = groupMap.get(idKey) || 0;
      return {
        ...row,
        breakdown: {
          quick: quickCount,
          group: groupCount,
          trxns: trxnsCount,
          totalPoints: (quickCount + groupCount + trxnsCount) * 10,
        },
      };
    });

    const latestRewardBatch = await MonthlyLeaderboardReward.findOne({})
      .sort({ periodEnd: -1 })
      .select('monthKey periodEnd')
      .lean();

    res.json({
      type,
      range,
      friendsOnly,
      period: {
        start: start.toISOString(),
        end: end.toISOString(),
      },
      comparePeriod: {
        start: prevStart.toISOString(),
        end: prevEnd.toISOString(),
      },
      rewards: {
        lastProcessedMonthKey: latestRewardBatch?.monthKey || null,
        lastProcessedAt: latestRewardBatch?.periodEnd || null,
      },
      users: enrichedRows,
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getMyMonthlyRewardSummary = async (req, res) => {
  try {
    const userId = req.user._id.toString();
    const rewards = await MonthlyLeaderboardReward.find({
      'rewardedUsers.user': req.user._id,
    })
      .sort({ periodEnd: -1 })
      .limit(6)
      .lean();

    const summary = rewards.map((entry) => {
      const my = (entry.rewardedUsers || []).find(
        (r) => r.user?.toString() === userId
      );
      return {
        monthKey: entry.monthKey,
        rank: my?.rank || null,
        points: my?.points || 0,
        coinsAwarded: my?.coinsAwarded || 0,
        periodStart: entry.periodStart,
        periodEnd: entry.periodEnd,
      };
    });

    res.json({ rewards: summary });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
