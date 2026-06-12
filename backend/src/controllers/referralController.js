const User = require('../models/user');
const ReferralShare = require('../models/referralShare');
const {
  ensureUserReferralCode,
  getReferralConfig,
} = require('../utils/referralService');

const normalizeShareOptions = (options = []) => {
  return (options || [])
    .filter((item) => item && item.enabled !== false)
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0))
    .map((item) => ({
      key: (item.key || '').toString().trim().toLowerCase(),
      label: (item.label || '').toString().trim(),
      icon: (item.icon || '').toString().trim().toLowerCase(),
      urlTemplate: (item.urlTemplate || '').toString().trim(),
      enabled: item.enabled !== false,
      sortOrder: Number(item.sortOrder || 0),
    }))
    .filter((item) => item.key && item.label && item.urlTemplate);
};

const mapAdminShareOptions = (options = []) => {
  return (options || [])
    .map((item) => ({
      key: (item.key || '').toString().trim().toLowerCase(),
      label: (item.label || '').toString().trim(),
      icon: (item.icon || '').toString().trim().toLowerCase(),
      urlTemplate: (item.urlTemplate || '').toString().trim(),
      enabled: item.enabled !== false,
      sortOrder: Number(item.sortOrder || 0),
    }))
    .filter((item) => item.key && item.label && item.urlTemplate)
    .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
};

const buildInviteLink = (baseUrl, referralCode) => {
  const safeBase = (baseUrl || 'https://lenden-seven.vercel.app').toString().trim();
  const separator = safeBase.includes('?') ? '&' : '?';
  return `${safeBase}${separator}ref=${encodeURIComponent(referralCode)}`;
};

exports.getReferralInfo = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('_id email');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const [referralCode, config] = await Promise.all([
      ensureUserReferralCode(user._id),
      getReferralConfig(),
    ]);

    const inviteLink = buildInviteLink(config.inviteBaseUrl, referralCode);
    const message = `Join me on LenDen! Track lending, borrowing, groups, and quick transactions in one app.\nUse my invite code: ${referralCode}\n${inviteLink}`;

    const sharesLimit = Math.min(parseInt(req.query.sharesLimit, 10) || 10, 50);
    const [totalShares, recentShares, invitedUsers, convertedUsers] = await Promise.all([
      ReferralShare.countDocuments({ user: user._id }),
      ReferralShare.find({ user: user._id })
        .sort({ createdAt: -1 })
        .limit(sharesLimit)
        .select('channel createdAt'),
      User.countDocuments({ referredByUser: user._id }),
      User.countDocuments({
        referredByUser: user._id,
        referralRewardGranted: true,
      }),
    ]);

    const shareOptions = normalizeShareOptions(config.shareOptions);

    res.json({
      referralCode,
      inviteLink,
      message,
      shareOptions,
      rewards: {
        inviterRewardCoins: Number(config.inviterRewardCoins || 20),
        refereeRewardCoins: Number(config.refereeRewardCoins || 10),
      },
      stats: {
        totalShares,
        invitedUsers,
        convertedUsers,
        recentShares,
      },
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.logReferralShare = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('_id');
    if (!user) return res.status(404).json({ error: 'User not found' });

    const [referralCode, config] = await Promise.all([
      ensureUserReferralCode(user._id),
      getReferralConfig(),
    ]);
    const allowedChannels = normalizeShareOptions(config.shareOptions).map((i) => i.key);
    const channelRaw = (req.body?.channel || 'other').toString().toLowerCase();
    const channel = allowedChannels.includes(channelRaw) ? channelRaw : 'other';
    const message = (req.body?.message || '').toString().slice(0, 1000);

    await ReferralShare.create({
      user: user._id,
      channel,
      referralCode,
      message,
    });

    res.json({ success: true, message: 'Referral share logged.' });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.getReferralConfigForAdmin = async (_req, res) => {
  try {
    const config = await getReferralConfig();
    res.json({
      inviteBaseUrl: config.inviteBaseUrl,
      inviterRewardCoins: Number(config.inviterRewardCoins || 20),
      refereeRewardCoins: Number(config.refereeRewardCoins || 10),
      shareOptions: mapAdminShareOptions(config.shareOptions),
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};

exports.updateReferralConfigForAdmin = async (req, res) => {
  try {
    const config = await getReferralConfig();
    const { inviteBaseUrl, inviterRewardCoins, refereeRewardCoins, shareOptions } = req.body || {};

    if (typeof inviteBaseUrl === 'string' && inviteBaseUrl.trim()) {
      config.inviteBaseUrl = inviteBaseUrl.trim();
    }
    if (inviterRewardCoins !== undefined) {
      const inviter = Number(inviterRewardCoins);
      if (Number.isNaN(inviter) || inviter < 0) {
        return res.status(400).json({ error: 'inviterRewardCoins must be a non-negative number.' });
      }
      config.inviterRewardCoins = inviter;
    }
    if (refereeRewardCoins !== undefined) {
      const referee = Number(refereeRewardCoins);
      if (Number.isNaN(referee) || referee < 0) {
        return res.status(400).json({ error: 'refereeRewardCoins must be a non-negative number.' });
      }
      config.refereeRewardCoins = referee;
    }
    if (Array.isArray(shareOptions)) {
      const seen = new Set();
      const nextOptions = [];
      for (let i = 0; i < shareOptions.length; i += 1) {
        const item = shareOptions[i] || {};
        const key = (item.key || '').toString().trim().toLowerCase();
        const label = (item.label || '').toString().trim();
        const icon = (item.icon || key).toString().trim().toLowerCase();
        const urlTemplate = (item.urlTemplate || '').toString().trim();
        const enabled = item.enabled !== false;
        const sortOrder = Number(item.sortOrder ?? i + 1);
        if (!key || !label || !urlTemplate || Number.isNaN(sortOrder)) {
          return res.status(400).json({ error: 'Each share option requires key, label, urlTemplate, and valid sortOrder.' });
        }
        if (seen.has(key)) {
          return res.status(400).json({ error: `Duplicate share option key: ${key}` });
        }
        seen.add(key);
        nextOptions.push({
          key,
          label,
          icon,
          urlTemplate,
          enabled,
          sortOrder,
        });
      }
      config.shareOptions = nextOptions;
    }

    await config.save();
    res.json({
      success: true,
      message: 'Referral configuration updated.',
      inviteBaseUrl: config.inviteBaseUrl,
      inviterRewardCoins: Number(config.inviterRewardCoins || 20),
      refereeRewardCoins: Number(config.refereeRewardCoins || 10),
      shareOptions: mapAdminShareOptions(config.shareOptions),
    });
  } catch (err) {
    res.status(500).json({ error: 'Server error' });
  }
};
