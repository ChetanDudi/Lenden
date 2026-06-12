const mongoose = require('mongoose');
const User = require('../models/user');
const FriendRequest = require('../models/friendRequest');
const Notification = require('../models/notification');
const Transaction = require('../models/transaction');
const QuickTransaction = require('../models/quickTransaction');
const GroupTransaction = require('../models/groupTransaction');
const { logFriendActivity } = require('./userActivityController');

const sanitizeQuery = (q) => (q || '').toString().trim();

const isBlocked = (user, otherId) =>
  (user.blockedUsers || []).some((id) => id.toString() === otherId.toString());

exports.searchUsers = async (req, res) => {
  try {
    const q = sanitizeQuery(req.query.q);
    if (!q) {
      return res.status(200).json({ users: [] });
    }

    const currentUser = await User.findById(req.user._id).select(
      'friends blockedUsers'
    );
    const excludeIds = [
      req.user._id,
      ...(currentUser.friends || []),
      ...(currentUser.blockedUsers || []),
    ];

    const regex = new RegExp(q, 'i');
    const requestedLimit = parseInt(req.query.limit, 10);
    const limit = (!isNaN(requestedLimit) && requestedLimit > 0)
      ? Math.min(requestedLimit, 50) : 20;

    const users = await User.find({
      _id: { $nin: excludeIds },
      $or: [{ email: regex }, { username: regex }, { name: regex }],
    })
      .select('name username email blockedUsers')
      .limit(limit);

    // Filter out users who have blocked the current user
    const filtered = users.filter(
      (u) =>
        !(u.blockedUsers || []).some(
          (id) => id.toString() === req.user._id.toString()
        )
    );

    res
      .status(200)
      .json({ users: filtered.map(({ _id, name, username, email }) => ({ _id, name, username, email })) });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getFriends = async (req, res) => {
  try {
    const { search } = req.query;
    const user = await User.findById(req.user._id)
      .populate('friends', 'name username email blockedUsers')
      .populate('blockedUsers', 'name username email')
      .select('friends blockedUsers');

    let friends = (user?.friends || []).map((f) => ({
      _id: f._id,
      name: f.name,
      username: f.username,
      email: f.email,
      blockedByThem: (f.blockedUsers || []).some(
        (id) => id.toString() === req.user._id.toString()
      ),
    }));

    let blockedUsers = user?.blockedUsers || [];

    // Apply search filter
    if (search && search.trim()) {
      const q = search.trim().toLowerCase();
      friends = friends.filter(
        (f) =>
          (f.name || '').toLowerCase().includes(q) ||
          (f.email || '').toLowerCase().includes(q) ||
          (f.username || '').toLowerCase().includes(q)
      );
      blockedUsers = blockedUsers.filter(
        (u) =>
          (u.name || '').toLowerCase().includes(q) ||
          (u.email || '').toLowerCase().includes(q) ||
          (u.username || '').toLowerCase().includes(q)
      );
    }

    res.status(200).json({ friends, blockedUsers });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getFriendRequests = async (req, res) => {
  try {
    const incoming = await FriendRequest.find({
      to: req.user._id,
      status: 'pending',
    }).populate('from', 'name username email');
    const outgoing = await FriendRequest.find({
      from: req.user._id,
      status: 'pending',
    }).populate('to', 'name username email');

    res.status(200).json({ incoming, outgoing });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getMutualFriends = async (req, res) => {
  try {
    const { email, userId } = req.query;
    let target = null;

    if (userId) {
      target = await User.findById(userId).select('friends');
    } else if (email) {
      target = await User.findOne({ email: email.toString() }).select('friends');
    } else {
      return res.status(400).json({ error: 'email or userId is required' });
    }

    if (!target) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (target._id.toString() === req.user._id.toString()) {
      return res.status(200).json({ mutualFriends: [] });
    }

    const me = await User.findById(req.user._id).select('friends');
    const myFriendIds = new Set((me.friends || []).map((id) => id.toString()));
    const mutualIds = (target.friends || []).filter((id) =>
      myFriendIds.has(id.toString())
    );

    const mutualFriends = await User.find({ _id: { $in: mutualIds } })
      .select('name username email')
      .limit(20);

    res.status(200).json({ mutualFriends });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getMutualFriendCounts = async (req, res) => {
  try {
    const { userIds = [], emails = [] } = req.body || {};
    if ((!userIds || userIds.length === 0) && (!emails || emails.length === 0)) {
      return res.status(400).json({ error: 'userIds or emails required' });
    }

    const me = await User.findById(req.user._id).select('friends');
    const myFriends = (me.friends || []).map((id) => id.toString());

    const match = userIds && userIds.length > 0
      ? { _id: { $in: userIds } }
      : { email: { $in: emails } };

    const mongoose = require('mongoose');
    const results = await User.aggregate([
      { $match: match },
      {
        $project: {
          _id: 1,
          mutualCount: {
            $size: {
              $setIntersection: [
                '$friends',
                myFriends.map((id) => new mongoose.Types.ObjectId(id)),
              ],
            },
          },
        },
      },
    ]);

    const counts = {};
    results.forEach((r) => {
      counts[r._id.toString()] = r.mutualCount || 0;
    });

    res.status(200).json({ counts });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};
exports.sendFriendRequest = async (req, res) => {
  try {
    const { userId, query } = req.body || {};
    let target = null;

    if (userId) {
      target = await User.findById(userId);
    } else {
      const q = sanitizeQuery(query);
      if (!q) {
        return res.status(400).json({ error: 'Email or username is required' });
      }
      target = await User.findOne({
        $or: [{ email: q }, { username: q }],
      });
    }

    if (!target) {
      return res.status(404).json({ error: 'User not found' });
    }
    if (target._id.toString() === req.user._id.toString()) {
      return res.status(400).json({ error: 'You cannot add yourself' });
    }

    const user = await User.findById(req.user._id);
    if (isBlocked(user, target._id) || isBlocked(target, user._id)) {
      return res.status(403).json({ error: 'Action not allowed' });
    }

    const alreadyFriend = (user.friends || []).some(
      (id) => id.toString() === target._id.toString()
    );
    if (alreadyFriend) {
      return res.status(200).json({ message: 'Already friends' });
    }

    const existingPending = await FriendRequest.findOne({
      $or: [
        { from: user._id, to: target._id, status: 'pending' },
        { from: target._id, to: user._id, status: 'pending' },
      ],
    });
    if (existingPending) {
      return res.status(200).json({ message: 'Request already pending' });
    }

    // Reuse a previously-cancelled or declined record to avoid the unique {from,to} index violation
    let request = await FriendRequest.findOneAndUpdate(
      { from: user._id, to: target._id, status: { $in: ['canceled', 'declined'] } },
      { $set: { status: 'pending', updatedAt: new Date() } },
      { new: true }
    );

    if (!request) {
      request = await FriendRequest.create({
        from: user._id,
        to: target._id,
        status: 'pending',
      });
    }

    // Activity log
    await logFriendActivity(user._id, 'friend_request_sent', { to: target.email });
    await logFriendActivity(target._id, 'friend_request_received', { from: user.email });

    // Notification for recipient (if enabled)
    const recipientUser = await User.findById(target._id, 'notificationSettings');
    if (recipientUser?.notificationSettings?.pushNotifications !== false) {
      await Notification.create({
        sender: user._id,
        senderModel: 'User',
        recipientType: 'specific-users',
        recipients: [target._id],
        recipientModel: 'User',
        message: `Friend request from ${user.name || user.username || user.email}`,
      });
    }

    res.status(201).json({ message: 'Request sent', requestId: request._id });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(200).json({ message: 'Request already pending' });
    }
    res.status(500).json({ error: 'Server error' });
  }
};

exports.acceptFriendRequest = async (req, res) => {
  try {
    const { requestId } = req.params;
    const request = await FriendRequest.findById(requestId);
    if (!request || request.status !== 'pending') {
      return res.status(404).json({ error: 'Request not found' });
    }
    if (request.to.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Not allowed' });
    }

    request.status = 'accepted';
    await request.save();

    const user = await User.findById(req.user._id);
    const other = await User.findById(request.from);
    user.friends = Array.from(
      new Set([...(user.friends || []), other._id])
    );
    other.friends = Array.from(
      new Set([...(other.friends || []), user._id])
    );
    await user.save();
    await other.save();

    await FriendRequest.deleteMany({
      $or: [
        { from: user._id, to: other._id, status: 'pending' },
        { from: other._id, to: user._id, status: 'pending' },
      ],
    });

    await logFriendActivity(user._id, 'friend_request_accepted', { with: other.email });
    await logFriendActivity(other._id, 'friend_request_accepted', { with: user.email });

    const senderUser = await User.findById(other._id, 'notificationSettings');
    if (senderUser?.notificationSettings?.pushNotifications !== false) {
      await Notification.create({
        sender: user._id,
        senderModel: 'User',
        recipientType: 'specific-users',
        recipients: [other._id],
        recipientModel: 'User',
        message: `${user.name || user.username || user.email} accepted your friend request`,
      });
    }

    res.status(200).json({ message: 'Request accepted' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.declineFriendRequest = async (req, res) => {
  try {
    const { requestId } = req.params;
    const request = await FriendRequest.findById(requestId);
    if (!request || request.status !== 'pending') {
      return res.status(404).json({ error: 'Request not found' });
    }
    if (request.to.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Not allowed' });
    }
    request.status = 'declined';
    await request.save();
    await logFriendActivity(req.user._id, 'friend_request_declined', {});
    const sender = await User.findById(request.from).select('email');
    if (sender) {
      await logFriendActivity(sender._id, 'friend_request_declined', { with: req.user.email });
    }
    res.status(200).json({ message: 'Request declined' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.cancelFriendRequest = async (req, res) => {
  try {
    const { requestId } = req.params;
    const request = await FriendRequest.findById(requestId);
    if (!request || request.status !== 'pending') {
      return res.status(404).json({ error: 'Request not found' });
    }
    if (request.from.toString() !== req.user._id.toString()) {
      return res.status(403).json({ error: 'Not allowed' });
    }
    request.status = 'canceled';
    await request.save();
    await logFriendActivity(req.user._id, 'friend_request_canceled', {});
    const recipient = await User.findById(request.to).select('email');
    if (recipient) {
      await logFriendActivity(recipient._id, 'friend_request_canceled', { with: req.user.email });
    }
    res.status(200).json({ message: 'Request canceled' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.removeFriend = async (req, res) => {
  try {
    const { friendId } = req.params;
    const user = await User.findById(req.user._id);
    const friend = await User.findById(friendId);
    if (!friend) {
      return res.status(404).json({ error: 'User not found' });
    }
    user.friends = (user.friends || []).filter(
      (id) => id.toString() !== friendId.toString()
    );
    friend.friends = (friend.friends || []).filter(
      (id) => id.toString() !== user._id.toString()
    );
    await user.save();
    await friend.save();
    await logFriendActivity(req.user._id, 'friend_removed', { with: friend.email });
    await logFriendActivity(friend._id, 'friend_removed', { with: user.email });
    res.status(200).json({ message: 'Friend removed' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.blockUser = async (req, res) => {
  try {
    const { userId } = req.body || {};
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }
    if (userId.toString() === req.user._id.toString()) {
      return res.status(400).json({ error: 'You cannot block yourself' });
    }

    const user = await User.findById(req.user._id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    if (!isBlocked(user, userId)) {
      user.blockedUsers = [...(user.blockedUsers || []), userId];
    }
    await user.save();

    await FriendRequest.deleteMany({
      $or: [
        { from: req.user._id, to: userId, status: 'pending' },
        { from: userId, to: req.user._id, status: 'pending' },
      ],
    });

    await logFriendActivity(req.user._id, 'user_blocked', { userId });
    await logFriendActivity(userId, 'user_blocked', { by: req.user.email });
    res.status(200).json({ message: 'User blocked' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.unblockUser = async (req, res) => {
  try {
    const { userId } = req.body || {};
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }
    const user = await User.findById(req.user._id);
    user.blockedUsers = (user.blockedUsers || []).filter(
      (id) => id.toString() !== userId.toString()
    );
    await user.save();
    await logFriendActivity(req.user._id, 'user_unblocked', { userId });
    await logFriendActivity(userId, 'user_unblocked', { by: req.user.email });
    res.status(200).json({ message: 'User unblocked' });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getFriendSuggestions = async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 10, 30);

    // ── Load my data ──────────────────────────────────────────────────────────
    const me = await User.findById(req.user._id).select('friends blockedUsers email');
    const myFriendIds = (me.friends || []).map((id) => id.toString());
    const myBlockedIds = (me.blockedUsers || []).map((id) => id.toString());
    const myEmail = (me.email || '').toLowerCase();

    // Build exclude set: self + friends + blocked
    const excludeIds = new Set([req.user._id.toString(), ...myFriendIds, ...myBlockedIds]);

    // Exclude anyone with a pending or cancelled request involving me
    const requests = await FriendRequest.find({
      $or: [
        { from: req.user._id, status: { $in: ['pending', 'canceled'] } },
        { to: req.user._id, status: 'pending' },
      ],
    }).select('from to');
    for (const r of requests) {
      excludeIds.add(r.from.toString());
      excludeIds.add(r.to.toString());
    }

    // score: candidateId (string) → numeric score
    const scoreMap = {};
    const addScore = (idStr, points) => {
      const key = (idStr || '').toString();
      if (key && !excludeIds.has(key)) {
        scoreMap[key] = (scoreMap[key] || 0) + points;
      }
    };

    // ── Signal 1: Friends of friends (+2 per mutual friend) ──────────────────
    if (myFriendIds.length > 0) {
      const friendsData = await User.find(
        { _id: { $in: myFriendIds } },
        { friends: 1 }
      ).lean();
      for (const f of friendsData) {
        for (const cid of (f.friends || [])) {
          addScore(cid.toString(), 2);
        }
      }
    }

    // ── Signal 2: Counterparties of friends (+1 per shared transaction) ───────
    if (myFriendIds.length > 0) {
      const friendUsers = await User.find(
        { _id: { $in: myFriendIds } },
        { email: 1 }
      ).lean();
      const friendEmails = friendUsers.map((f) => (f.email || '').toLowerCase()).filter(Boolean);
      const friendEmailSet = new Set(friendEmails);

      // Collect candidate emails from secure + quick transactions in parallel
      const [secureTxns, quickTxns, groupTxns] = await Promise.all([
        friendEmails.length > 0
          ? Transaction.find(
              { $or: [{ userEmail: { $in: friendEmails } }, { counterpartyEmail: { $in: friendEmails } }] },
              { userEmail: 1, counterpartyEmail: 1 }
            ).lean()
          : [],
        friendEmails.length > 0
          ? QuickTransaction.find({ users: { $in: friendEmails } }, { users: 1 }).lean()
          : [],
        GroupTransaction.find(
          { 'members.user': { $in: myFriendIds.map((id) => new mongoose.Types.ObjectId(id)) } },
          { 'members.user': 1 }
        ).lean(),
      ]);

      // Secure transaction counterparties → emails
      const cpEmailSet = new Set();
      for (const t of secureTxns) {
        const cpEmail = friendEmailSet.has((t.userEmail || '').toLowerCase())
          ? t.counterpartyEmail
          : t.userEmail;
        if (cpEmail) cpEmailSet.add(cpEmail.toLowerCase());
      }

      // Quick transaction counterparties → emails
      for (const t of quickTxns) {
        for (const email of (t.users || [])) {
          const e = (email || '').toLowerCase();
          if (e && e !== myEmail && !friendEmailSet.has(e)) cpEmailSet.add(e);
        }
      }

      // Resolve counterparty emails → ObjectIds and score
      if (cpEmailSet.size > 0) {
        const cpUsers = await User.find({ email: { $in: [...cpEmailSet] } }, { _id: 1 }).lean();
        for (const u of cpUsers) addScore(u._id.toString(), 1);
      }

      // Group transaction counterparties (already ObjectIds)
      for (const g of groupTxns) {
        for (const m of (g.members || [])) {
          const mid = m.user?.toString();
          if (mid) addScore(mid, 1);
        }
      }
    }

    // ── Signal 3: Leaderboard top 10 (+1 bonus for active users) ─────────────
    const monthAgo = new Date();
    monthAgo.setMonth(monthAgo.getMonth() - 1);

    const [quickTop, secureTop, groupTop] = await Promise.all([
      QuickTransaction.aggregate([
        { $match: { createdAt: { $gte: monthAgo } } },
        { $group: { _id: '$creatorEmail', count: { $sum: 1 } } },
        { $sort: { count: -1 } }, { $limit: 20 },
      ]),
      Transaction.aggregate([
        { $match: { createdAt: { $gte: monthAgo } } },
        { $group: { _id: '$userEmail', count: { $sum: 1 } } },
        { $sort: { count: -1 } }, { $limit: 20 },
      ]),
      GroupTransaction.aggregate([
        { $match: { createdAt: { $gte: monthAgo } } },
        { $group: { _id: '$creator', count: { $sum: 1 } } },
        { $sort: { count: -1 } }, { $limit: 20 },
      ]),
    ]);

    // Resolve leaderboard emails to IDs and score top 10 unique users
    const lbEmails = [
      ...quickTop.map((r) => r._id),
      ...secureTop.map((r) => r._id),
    ].filter(Boolean);
    const lbObjIds = groupTop.map((r) => r._id?.toString()).filter(Boolean);

    const lbIdSet = new Set(lbObjIds);
    if (lbEmails.length > 0) {
      const lbUsers = await User.find({ email: { $in: lbEmails } }, { _id: 1 }).lean();
      for (const u of lbUsers) lbIdSet.add(u._id.toString());
    }

    let lbBonus = 0;
    for (const id of lbIdSet) {
      if (lbBonus >= 10) break;
      if (!excludeIds.has(id)) { addScore(id, 1); lbBonus++; }
    }

    // ── Finalize: rank by score, fetch user details ───────────────────────────
    const candidateIds = Object.keys(scoreMap)
      .sort((a, b) => scoreMap[b] - scoreMap[a])
      .slice(0, limit);

    if (candidateIds.length === 0) {
      return res.status(200).json({ suggestions: [] });
    }

    const myFriendIdSet = new Set(myFriendIds);
    const candidateUsers = await User.find(
      { _id: { $in: candidateIds } },
      { name: 1, username: 1, email: 1, friends: 1 }
    ).lean();

    const suggestions = candidateUsers
      .map((u) => {
        const uid = u._id.toString();
        const mutualCount = (u.friends || []).filter((fid) => myFriendIdSet.has(fid.toString())).length;
        return {
          _id: u._id,
          name: u.name || '',
          username: u.username || '',
          email: u.email || '',
          mutualFriends: mutualCount,
          reason: mutualCount > 0
            ? `${mutualCount} mutual friend${mutualCount === 1 ? '' : 's'}`
            : 'Active in transactions',
          _score: scoreMap[uid] || 0,
        };
      })
      .sort((a, b) => b._score - a._score)
      .map(({ _score, ...rest }) => rest); // strip internal field

    res.status(200).json({ suggestions });
  } catch (error) {
    res.status(500).json({ error: 'Server error' });
  }
};
