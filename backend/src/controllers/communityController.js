const Community = require('../models/community');
const GroupTransaction = require('../models/groupTransaction');
const User = require('../models/user');

exports.createCommunity = async (req, res) => {
  try {
    const { name, description, color } = req.body;
    if (!name?.trim()) return res.status(400).json({ error: 'Community name is required' });

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
      .populate('members.user', 'name email username')
      .populate('creator', 'name email username')
      .populate('groups', 'title color description')
      .select('-communityImage');

    if (!community) return res.status(404).json({ error: 'Community not found' });
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

    const gidStr = group._id.toString();
    if (!community.groups.map(g => g.toString()).includes(gidStr)) {
      community.groups.push(group._id);
      await community.save();
      group.communityId = community._id;
      await group.save();
    }
    res.json({ success: true });
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
    const community = await Community.findById(req.params.id).select('communityImage communityImageMimeType');
    if (!community || !community.communityImage) return res.status(404).end();
    res.set('Content-Type', community.communityImageMimeType);
    res.send(community.communityImage);
  } catch (e) {
    res.status(500).end();
  }
};

exports.deleteCommunity = async (req, res) => {
  try {
    const community = await Community.findById(req.params.id);
    if (!community) return res.status(404).json({ error: 'Community not found' });
    if (community.creator.toString() !== req.user._id.toString()) return res.status(403).json({ error: 'Only creator can delete' });

    // Unlink all groups
    if (community.groups.length > 0) {
      await GroupTransaction.updateMany({ _id: { $in: community.groups } }, { $unset: { communityId: '' } });
    }
    await community.deleteOne();
    res.json({ success: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
};
