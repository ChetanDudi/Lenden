const Community = require('../models/community');
const CommunityPost = require('../models/communityPost');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');
const Subscription = require('../models/subscription');
const AdminSettings = require('../models/adminSettings');
const Notification = require('../models/notification');
const { getCoinPricing } = require('../utils/coinPricing');

const _fallbackPool = [
  'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1543269865-cbf427effbad?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1491438590914-bc09fcaaf77a?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1517048676732-d65bc937f952?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?w=800&fit=crop&auto=format',
  'https://images.unsplash.com/photo-1574957831710-f3c2292ad6e0?w=800&fit=crop&auto=format',
];

function _idHash(id) {
  const s = String(id || '');
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

function defaultCommunityImageUrl(name, id) {
  const n = (name || '').toLowerCase();
  const categories = [
    ['https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&fit=crop&auto=format', ['spirit','reiki','heal','meditat','yoga','chakra','zen','mantra','divine']],
    ['https://images.unsplash.com/photo-1513364776144-60967b0f800f?w=800&fit=crop&auto=format', ['art','craft','paint','design','creat','draw','sculpt']],
    ['https://images.unsplash.com/photo-1621416894569-0f39ed31d247?w=800&fit=crop&auto=format', ['crypto','bitcoin','invest','finance','stock','trade','nft','web3']],
    ['https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&fit=crop&auto=format', ['fit','gym','sport','workout','run','muscle','athlet']],
    ['https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=800&fit=crop&auto=format', ['food','cook','recipe','kitchen','bake','chef']],
    ['https://images.unsplash.com/photo-1476514525535-07fb3b4ae5f1?w=800&fit=crop&auto=format', ['travel','trip','adventur','journey','tour','wander','explore']],
    ['https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=800&fit=crop&auto=format', ['music','band','song','concert','guitar','sing']],
    ['https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=800&fit=crop&auto=format', ['tech','code','program','dev','software','hack','data','ai','ml']],
    ['https://images.unsplash.com/photo-1567954970774-58d6aa6c50dc?w=800&fit=crop&auto=format', ['crystal','gem','stone','mineral','quartz','tarot']],
    ['https://images.unsplash.com/photo-1511895426328-dc8714191011?w=800&fit=crop&auto=format', ['family','home','parent','child','baby','mom','dad']],
    ['https://images.unsplash.com/photo-1497366216548-37526070297c?w=800&fit=crop&auto=format', ['business','office','work','career','professional','entrepreneur']],
    ['https://images.unsplash.com/photo-1524178232363-1fb2b075b655?w=800&fit=crop&auto=format', ['study','learn','educat','student','college','school']],
    ['https://images.unsplash.com/photo-1535268647677-300dbf3d78d1?w=800&fit=crop&auto=format', ['pet','animal','dog','cat','bird']],
  ];
  for (const [url, keywords] of categories) {
    if (keywords.some(k => n.includes(k))) return url;
  }
  return _fallbackPool[_idHash(id) % _fallbackPool.length];
}

exports.createCommunity = async (req, res) => {
  try {
    const { name, description, color } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Community name is required' });

    // ── Limit check ───────────────────────────────────────────────────────────
    const settings = await AdminSettings.getOrCreate();
    const limit = settings.maxCommunitiesPerUser ?? 1;
    const existing = await Community.countDocuments({ creator: req.user._id });

    if (existing >= limit) {
      const subscription = await Subscription.findOne({ user: req.user._id, status: 'active' });
      if (!subscription) {
        const pricing = await getCoinPricing();
        const cost = pricing.communityCoinCost ?? 30;
        // Atomic check-and-deduct — prevents race condition where two concurrent
        // requests both pass the balance check before either deducts.
        const deducted = await User.findOneAndUpdate(
          { _id: req.user._id, lenDenCoins: { $gte: cost } },
          { $inc: { lenDenCoins: -cost } },
          { new: false },
        );
        if (!deducted) {
          const user = await User.findById(req.user._id).select('lenDenCoins');
          return res.status(402).json({
            error: `You have reached the community limit (${limit}). Create more with ${cost} LenDen coins.`,
            limit,
            cost,
            currentCoins: user?.lenDenCoins ?? 0,
          });
        }
      }
    }
    // ─────────────────────────────────────────────────────────────────────────

    const community = new Community({
      name: name.trim(),
      description: (description || '').trim(),
      color: color || '#00B4D8',
      creator: req.user._id,
      members: [{ user: req.user._id, role: 'admin' }],
    });
    await community.save();
    await community.populate('members.user', 'name email username');
    res.status(201).json({ community });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getLimitInfo = async (req, res) => {
  try {
    const settings = await AdminSettings.getOrCreate();
    const limit = settings.maxCommunitiesPerUser ?? 1;
    const count = await Community.countDocuments({ creator: req.user._id });
    const pricing = await getCoinPricing();
    const cost = pricing.communityCoinCost ?? 30;
    const subscription = await Subscription.findOne({ user: req.user._id, status: 'active' });
    const user = await User.findById(req.user._id).select('lenDenCoins');
    res.json({
      limit,
      count,
      overLimit: count >= limit,
      hasSubscription: !!subscription,
      cost,
      userCoins: user?.lenDenCoins ?? 0,
    });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getMyCommunities = async (req, res) => {
  try {
    const communities = await Community.find({ 'members.user': req.user._id })
      .populate('members.user', 'name email username')
      .populate('groups', 'title color')
      .sort({ updatedAt: -1 })
      .select('-communityImage');
    res.json({ communities });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id)
      .populate('creator', 'name email username')
      .populate('groups', 'title color description')
      .select('-communityImage');

    if (!community) return res.status(404).json({ error: 'Community not found' });

    // Sync: add any active group members not yet in community members
    const existingMemberIds = new Set(community.members.map(m => m.user.toString()));
    let needsSave = false;
    for (const groupRef of community.groups) {
      const group = await GroupTransaction.findById(groupRef._id).select('members');
      if (!group) continue;
      for (const gm of group.members.filter(m => !m.leftAt)) {
        if (!existingMemberIds.has(gm.user.toString())) {
          community.members.push({ user: gm.user, role: 'member' });
          existingMemberIds.add(gm.user.toString());
          needsSave = true;
        }
      }
    }
    if (needsSave) await community.save();

    await community.populate('members.user', 'name email username');
    const isMember = community.members.some(m => m.user._id.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Not a member of this community' });
    res.json({ community });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.updateCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'Admin only' });

    const { name, description, color, settings } = req.body;
    if (name?.trim()) community.name = name.trim();
    if (description !== undefined) community.description = description.trim();
    if (color) community.color = color;
    if (settings) community.settings = { ...community.settings.toObject?.() ?? community.settings, ...settings };
    await community.save();
    res.json({ community });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.joinCommunity = async (req, res) => {
  try {
    const { inviteCode } = req.body;
    if (!inviteCode) return res.status(400).json({ error: 'Invite code required' });

    const community = await Community.findOne({ inviteCode: inviteCode.trim().toUpperCase() });
    if (!community) return res.status(404).json({ error: 'Invalid invite code' });

    const alreadyMember = community.members.some(m => m.user.toString() === req.user._id.toString());
    if (alreadyMember) return res.status(400).json({ error: 'Already a member' });

    community.members.push({ user: req.user._id, role: 'member' });
    await community.save();
    await community.populate('members.user', 'name email username');
    res.json({ community });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.addGroupToCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'Admin only' });

    const { groupId } = req.body;
    const group = await GroupTransaction.findById(groupId);
    if (!group) return res.status(404).json({ error: 'Group not found' });

    // Link group ↔ community
    const gidStr = group._id.toString();
    if (!community.groups.map(g => g.toString()).includes(gidStr)) {
      community.groups.push(group._id);
    }
    if (!group.communityIds.map(id => id.toString()).includes(req.params.id)) {
      group.communityIds.push(community._id);
      await group.save();
    }

    // Auto-add active group members who aren't already in the community
    const existingMemberIds = new Set(community.members.map(m => m.user.toString()));
    const activeGroupMembers = group.members.filter(m => !m.leftAt);
    for (const gm of activeGroupMembers) {
      if (!existingMemberIds.has(gm.user.toString())) {
        community.members.push({ user: gm.user, role: 'member', invitedBy: req.user._id });
        existingMemberIds.add(gm.user.toString());
      }
    }

    await community.save();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.removeGroupFromCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'Admin only' });
    await Community.findByIdAndUpdate(req.params.id, { $pull: { groups: req.params.groupId } });
    await GroupTransaction.findByIdAndUpdate(req.params.groupId, { $pull: { communityIds: req.params.id } });
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getCommunityBalance = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id)
      .populate({ path: 'groups', select: 'title color expenses' });
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isMember = community.members.some(m => m.user.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Not a member' });
    const uid = req.user._id.toString();
    let totalSplits = 0;
    let netBalance = 0;
    const groups = (community.groups || []).map(g => {
      let totalSplit = 0; // all splits for this user (settled + unsettled)
      let userOwes = 0;   // unsettled: user is in split, someone else paid
      let owedToUser = 0; // unsettled: user paid, others haven't settled

      (g.expenses || []).forEach(exp => {
        const addedBy = (exp.addedBy || '').toString();
        (exp.split || []).forEach(s => {
          const splitUser = (s.user || '').toString();
          const amt = Number(s.amountInr || s.amount || 0);
          if (splitUser === uid) totalSplit += amt;
          if (!s.settled) {
            if (splitUser === uid && addedBy !== uid) userOwes += amt;
            else if (addedBy === uid && splitUser !== uid) owedToUser += amt;
          }
        });
      });

      const groupNet = userOwes - owedToUser; // positive = you owe, negative = you're owed
      totalSplits += totalSplit;
      netBalance += groupNet;
      return { groupId: g._id, title: g.title, color: g.color, amount: totalSplit, pendingAmount: groupNet, netBalance: groupNet };
    });
    res.json({ totalSplits, netBalance, groups });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.uploadImage = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'Admin only' });
    if (!req.file) return res.status(400).json({ error: 'No image uploaded' });
    const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
    if (!ALLOWED_IMAGE_TYPES.includes(req.file.mimetype)) {
      return res.status(400).json({ error: 'Unsupported image type. Upload a JPEG, PNG, or WebP.' });
    }

    community.communityImage = req.file.buffer;
    community.communityImageMimeType = req.file.mimetype;
    await community.save();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getImage = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id).select('communityImage communityImageMimeType name');
    if (!community) return res.status(404).end();
    if (!community.communityImage) {
      return res.redirect(defaultCommunityImageUrl(community.name, req.params.id));
    }
    res.set('Content-Type', community.communityImageMimeType);
    res.send(community.communityImage);
  } catch (e) {
    res.status(500).end();
  }
};

exports.addMember = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isAdmin = community.members.some(m => m.user.toString() === req.user._id.toString() && m.role === 'admin');
    if (!isAdmin) return res.status(403).json({ error: 'Admin only' });

    const { email } = req.body;
    if (!email?.trim()) return res.status(400).json({ error: 'Email required' });
    const normalizedEmail = email.trim().toLowerCase();

    const targetUser = await User.findOne({ email: normalizedEmail }).select('_id privacySettings');
    if (!targetUser) return res.status(404).json({ error: 'No user found with that email' });

    if (community.members.some(m => m.user.toString() === targetUser._id.toString())) {
      return res.status(400).json({ error: 'User is already a member' });
    }

    if (targetUser.privacySettings?.allowDirectCommunityAdd === false) {
      // Send in-app + device notification so the user can join themselves
      try {
        const { sendToUser } = require('../services/notificationService');
        const inviter = await User.findById(req.user._id).select('name email');
        const inviterName = inviter?.name || inviter?.email || 'Someone';
        await Notification.create({
          sender: req.user._id, senderModel: 'User',
          recipientType: 'specific-users', recipients: [targetUser._id], recipientModel: 'User',
          message: `${inviterName} invited you to join the community "${community.name}".`,
          category: 'general',
          deliveryStatus: 'sent', sentAt: new Date(),
        });
        sendToUser(User, targetUser._id, {
          title: 'Community Invite',
          body: `${inviterName} invited you to join "${community.name}". Tap to view.`,
          data: { type: 'community_join_invite', communityId: community._id.toString(), communityName: community.name },
        });
      } catch (_) {}
      return res.json({ notified: true, message: 'User has restricted direct additions. They have been notified and can join using the invite code.' });
    }

    if (community.settings.allowDirectAdd) {
      community.members.push({ user: targetUser._id, role: 'member', invitedBy: req.user._id });
      await community.save();
      return res.json({ added: true, message: 'Member added successfully' });
    } else {
      if (community.pendingInvites.some(i => i.email === normalizedEmail)) {
        return res.status(400).json({ error: 'Invite already sent to this user' });
      }
      community.pendingInvites.push({ email: normalizedEmail, invitedBy: req.user._id });
      await community.save();
      return res.json({ invited: true, message: 'Invite sent successfully' });
    }
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getMyInvites = async (req, res) => {
  try {
    const userEmail = (req.user.email || '').toLowerCase();
    if (!userEmail) return res.json({ invites: [] });
    const communities = await Community.find({ 'pendingInvites.email': userEmail })
      .select('name color description pendingInvites inviteCode')
      .populate('creator', 'name email');
    const invites = communities.map(c => {
      const inv = c.pendingInvites.find(i => i.email === userEmail);
      return {
        communityId: c._id,
        name: c.name,
        color: c.color,
        description: c.description,
        invitedAt: inv?.invitedAt,
      };
    });
    res.json({ invites });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.acceptInvite = async (req, res) => {
  try {
    const userEmail = (req.user.email || '').toLowerCase();
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });

    const inviteIdx = community.pendingInvites.findIndex(i => i.email === userEmail);
    if (inviteIdx === -1) return res.status(404).json({ error: 'No invite found' });

    if (!community.members.some(m => m.user.toString() === req.user._id.toString())) {
      const invite = community.pendingInvites[inviteIdx];
      community.members.push({ user: req.user._id, role: 'member', invitedBy: invite.invitedBy });
    }
    community.pendingInvites.splice(inviteIdx, 1);
    await community.save();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.declineInvite = async (req, res) => {
  try {
    const userEmail = (req.user.email || '').toLowerCase();
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });

    const inviteIdx = community.pendingInvites.findIndex(i => i.email === userEmail);
    if (inviteIdx === -1) return res.status(404).json({ error: 'No invite found' });

    community.pendingInvites.splice(inviteIdx, 1);
    await community.save();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.deleteCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    if (community.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can delete' });

    // Unlink all groups
    if (community.groups.length > 0) {
      await GroupTransaction.updateMany({ _id: { $in: community.groups } }, { $pull: { communityIds: community._id } });
    }
    await community.deleteOne();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

// ── Community Feed ────────────────────────────────────────────────────────────

function _fmtPost(post, uid) {
  const p = post.toObject ? post.toObject() : { ...post };
  p.likesCount = Array.isArray(p.likes) ? p.likes.length : 0;
  p.likedByMe = Array.isArray(p.likes) ? p.likes.some(id => id.toString() === uid) : false;
  delete p.likes;
  return p;
}

exports.createPost = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id).select('members');
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isMember = community.members.some(m => m.user.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Members only' });

    const { text } = req.body;
    if (!text?.trim()) return res.status(400).json({ error: 'Post text is required' });
    if (text.trim().length > 1000) return res.status(400).json({ error: 'Post cannot exceed 1000 characters' });

    const post = await CommunityPost.create({ community: req.params.id, author: req.user._id, text: text.trim() });
    await post.populate([
      { path: 'author', select: 'name email username' },
      { path: 'comments.author', select: 'name username' },
    ]);
    res.status(201).json({ post: _fmtPost(post, req.user._id.toString()) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getPosts = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id).select('members');
    if (!community) return res.status(404).json({ error: 'Community not found' });
    const isMember = community.members.some(m => m.user.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Members only' });

    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    const before = req.query.before;
    const query = { community: req.params.id };
    if (before) query.createdAt = { $lt: new Date(before) };

    const posts = await CommunityPost.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1)
      .populate('author', 'name email username')
      .populate('comments.author', 'name username');

    const hasMore = posts.length > limit;
    const uid = req.user._id.toString();
    res.json({ posts: posts.slice(0, limit).map(p => _fmtPost(p, uid)), hasMore });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.getFeed = async (req, res) => {
  try {
    const communities = await Community.find({ 'members.user': req.user._id }).select('_id name color');
    const communityIds = communities.map(c => c._id);

    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    const before = req.query.before;
    const query = { community: { $in: communityIds } };
    if (before) query.createdAt = { $lt: new Date(before) };

    const posts = await CommunityPost.find(query)
      .sort({ createdAt: -1 })
      .limit(limit + 1)
      .populate('author', 'name email username')
      .populate('community', 'name color')
      .populate('comments.author', 'name username');

    const hasMore = posts.length > limit;
    const uid = req.user._id.toString();
    res.json({ posts: posts.slice(0, limit).map(p => _fmtPost(p, uid)), hasMore });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.deletePost = async (req, res) => {
  try {
    const post = await CommunityPost.findById(req.params.postId);
    if (!post) return res.status(404).json({ error: 'Post not found' });

    const community = await Community.findById(post.community).select('members');
    const member = community?.members.find(m => m.user.toString() === req.user._id.toString());
    const isAdmin = member?.role === 'admin';
    const isAuthor = post.author.toString() === req.user._id.toString();
    if (!isAuthor && !isAdmin) return res.status(403).json({ error: 'Forbidden' });

    await post.deleteOne();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.likePost = async (req, res) => {
  try {
    const post = await CommunityPost.findById(req.params.postId).select('community likes');
    if (!post) return res.status(404).json({ error: 'Post not found' });

    const community = await Community.findById(post.community).select('members');
    const isMember = community?.members.some(m => m.user.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Members only' });

    const uid = req.user._id;
    const idx = post.likes.findIndex(id => id.toString() === uid.toString());
    if (idx === -1) post.likes.push(uid);
    else post.likes.splice(idx, 1);

    await post.save();
    res.json({ likesCount: post.likes.length, likedByMe: idx === -1 });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.addComment = async (req, res) => {
  try {
    const post = await CommunityPost.findById(req.params.postId);
    if (!post) return res.status(404).json({ error: 'Post not found' });

    const community = await Community.findById(post.community).select('members');
    const isMember = community?.members.some(m => m.user.toString() === req.user._id.toString());
    if (!isMember) return res.status(403).json({ error: 'Members only' });

    const { text } = req.body;
    if (!text?.trim()) return res.status(400).json({ error: 'Comment text is required' });
    if (text.trim().length > 500) return res.status(400).json({ error: 'Comment cannot exceed 500 characters' });

    post.comments.push({ author: req.user._id, text: text.trim() });
    await post.save();
    await post.populate('comments.author', 'name username');

    const added = post.comments[post.comments.length - 1];
    res.status(201).json({ comment: added });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};

exports.deleteComment = async (req, res) => {
  try {
    const post = await CommunityPost.findById(req.params.postId);
    if (!post) return res.status(404).json({ error: 'Post not found' });

    const comment = post.comments.id(req.params.commentId);
    if (!comment) return res.status(404).json({ error: 'Comment not found' });

    const community = await Community.findById(post.community).select('members');
    const member = community?.members.find(m => m.user.toString() === req.user._id.toString());
    const isAdmin = member?.role === 'admin';
    const isAuthor = comment.author.toString() === req.user._id.toString();
    if (!isAuthor && !isAdmin) return res.status(403).json({ error: 'Forbidden' });

    comment.deleteOne();
    await post.save();
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};
