const User = require('../models/user');
const FriendRequest = require('../models/friendRequest');
const Notification = require('../models/notification');
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
    const users = await User.find({
      _id: { $nin: excludeIds },
      $or: [{ email: regex }, { username: regex }, { name: regex }],
    })
      .select('name username email blockedUsers')
      .limit(20);

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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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

    const existing = await FriendRequest.findOne({
      $or: [
        { from: user._id, to: target._id, status: 'pending' },
        { from: target._id, to: user._id, status: 'pending' },
      ],
    });
    if (existing) {
      return res.status(200).json({ message: 'Request already pending' });
    }

    const request = await FriendRequest.create({
      from: user._id,
      to: target._id,
      status: 'pending',
    });

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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
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
    res.status(500).json({ error: error.message });
  }
};
