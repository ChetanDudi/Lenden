const mongoose = require('mongoose');
const fs = require('fs');
const Admin = require('../models/admin');
const AppAdEvent = require('../models/appAdEvent');
const AppUpdate = require('../models/appUpdate');
const AppUpdateRead = require('../models/appUpdateRead');
const AppAd = require('../models/appAd');
const Subscription = require('../models/subscription');
const Notification = require('../models/notification');
const User = require('../models/user');
const { getAdMediaBucket } = require('../utils/adMediaBucket');

const normalizeCreator = (creator) => {
  if (!creator) return null;
  if (creator._id) {
    return {
      _id: creator._id,
      name: creator.name || '',
      email: creator.email || '',
      isSuperAdmin: creator.isSuperAdmin === true,
    };
  }
  return creator;
};

const canManageContent = (admin, content) => {
  if (!admin || !content) return false;
  if (admin.isSuperAdmin === true) return true;
  const creatorId = content.createdBy?._id || content.createdBy;
  const adminId = admin._id || admin.userId || admin.id;
  return creatorId?.toString() === adminId?.toString();
};

const toUpdateResponse = (req, update, currentAdmin = null) => {
  const history = Array.isArray(update.editHistory) ? update.editHistory : [];
  const lastEditedAt = history.length > 0 ? history[history.length - 1].editedAt : null;
  return {
    _id: update._id,
    title: update.title,
    body: update.body,
    summary: update.summary || '',
    versionTag: update.versionTag || '',
    category: update.category || 'general',
    importance: update.importance || 'normal',
    targetAudience: update.targetAudience || 'all',
    platforms: Array.isArray(update.platforms) ? update.platforms : ['all'],
    tags: Array.isArray(update.tags) ? update.tags : [],
    status: update.status || 'published',
    scheduledFor: update.scheduledFor || null,
    pinned: !!update.pinned,
    publishedAt: update.publishedAt,
    createdAt: update.createdAt,
    updatedAt: update.updatedAt,
    lastEditedAt,
    editHistory: history.map((entry) => ({
      editedAt: entry.editedAt,
      title: entry.title || '',
      body: entry.body || '',
      summary: entry.summary || '',
      versionTag: entry.versionTag || '',
      category: entry.category || 'general',
      importance: entry.importance || 'normal',
      tags: Array.isArray(entry.tags) ? entry.tags : [],
      platforms: Array.isArray(entry.platforms) ? entry.platforms : ['all'],
      targetAudience: entry.targetAudience || 'all',
      status: entry.status || 'published',
    })),
    createdBy: normalizeCreator(update.createdBy),
    canManage: currentAdmin ? canManageContent(currentAdmin, update) : undefined,
  };
};

const toAdResponse = (req, ad, currentAdmin = null) => ({
  _id: ad._id,
  title: ad.title,
  body: ad.body || '',
  callToActionText: ad.callToActionText || '',
  callToActionUrl: ad.callToActionUrl || '',
  mediaKind: ad.mediaKind || 'none',
  audience: ad.audience || 'nonsubscribed',
  placements: Array.isArray(ad.placements) ? ad.placements : ['dashboard'],
  tags: Array.isArray(ad.tags) ? ad.tags : [],
  priorityWeight: ad.priorityWeight || 1,
  dailyCapPerUser: ad.dailyCapPerUser || 3,
  mediaFilename: ad.mediaFilename || '',
  mediaMimeType: ad.mediaMimeType || '',
  videoCloseAtPercent: normalizeVideoClosePercent(ad.videoCloseAtPercent),
  mediaUrl:
    ad.mediaFileId != null
      ? `${req.protocol}://${req.get('host')}/api/ads/media/${ad.mediaFileId}`
      : null,
  active: !!ad.active,
  startsAt: ad.startsAt,
  endsAt: ad.endsAt,
  createdAt: ad.createdAt,
  updatedAt: ad.updatedAt,
  createdBy: normalizeCreator(ad.createdBy),
  canManage: currentAdmin ? canManageContent(currentAdmin, ad) : undefined,
});

const getCurrentAdmin = async (req) => {
  const adminId = req.user?._id || req.user?.userId || req.user?.id;
  if (req.user?.role !== 'admin') return null;

  let admin = null;
  if (adminId) {
    admin = await Admin.findById(adminId).select('_id email name isSuperAdmin').lean();
  }
  if (!admin && req.user?.email) {
    admin = await Admin.findOne({ email: req.user.email })
      .select('_id email name isSuperAdmin')
      .lean();
  }
  return admin;
};

const detectMediaKind = (mimeType = '') => {
  if (mimeType.startsWith('image/')) return 'image';
  if (mimeType.startsWith('video/')) return 'video';
  return 'none';
};

const normalizeVideoClosePercent = (value) => {
  const parsed = Number.parseInt(value, 10);
  return [25, 50, 75, 100].includes(parsed) ? parsed : 100;
};

const normalizeCategory = (value) => {
  const allowed = ['general', 'feature', 'bug_fix', 'security', 'maintenance'];
  return allowed.includes(value) ? value : 'general';
};

const normalizeImportance = (value) => {
  const allowed = ['normal', 'important', 'critical'];
  return allowed.includes(value) ? value : 'normal';
};

const normalizeUpdateStatus = (value) => {
  const allowed = ['draft', 'published', 'scheduled'];
  return allowed.includes(value) ? value : 'published';
};

const normalizeAudience = (value, fallback = 'all') => {
  const allowed = ['all', 'subscribed', 'nonsubscribed'];
  return allowed.includes(value) ? value : fallback;
};

const normalizeStringArray = (value, fallback = []) => {
  if (Array.isArray(value)) {
    return value
      .map((item) => item?.toString().trim())
      .filter((item) => item);
  }
  if (typeof value === 'string' && value.trim().startsWith('[')) {
    try {
      const parsed = JSON.parse(value);
      return normalizeStringArray(parsed, fallback);
    } catch (_) {
      return fallback;
    }
  }
  if (typeof value === 'string' && value.trim()) {
    return value
      .split(',')
      .map((item) => item.trim())
      .filter((item) => item);
  }
  return fallback;
};

const normalizePlatforms = (value) => {
  const normalized = normalizeStringArray(value, ['all']);
  return normalized.length ? normalized : ['all'];
};

const normalizeWeight = (value) => {
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed)) return 1;
  return Math.min(100, Math.max(1, parsed));
};

const normalizeDailyCap = (value) => {
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed)) return 3;
  return Math.min(50, Math.max(1, parsed));
};

const getPlatformFromRequest = (req) => {
  const platformHeader = (req.headers['x-platform'] || '').toString().toLowerCase();
  if (platformHeader) return platformHeader;
  const userAgent = (req.headers['user-agent'] || '').toString().toLowerCase();
  if (userAgent.includes('windows')) return 'windows';
  if (userAgent.includes('android')) return 'android';
  if (userAgent.includes('iphone') || userAgent.includes('ios')) return 'ios';
  if (userAgent.includes('macintosh') || userAgent.includes('mac os')) return 'macos';
  if (userAgent.includes('chrome') || userAgent.includes('edge')) return 'web';
  return 'all';
};

const isUserSubscribed = async (userId) => {
  if (!userId) return false;
  const subscription = await Subscription.findOne({
    user: userId,
    subscribed: true,
    endDate: { $gte: new Date() },
  })
    .sort({ endDate: -1 })
    .lean();
  return !!subscription;
};

const aggregateAdStats = async (adIds) => {
  if (!adIds.length) return {};
  const stats = await AppAdEvent.aggregate([
    { $match: { ad: { $in: adIds } } },
    {
      $group: {
        _id: { ad: '$ad', type: '$type' },
        count: { $sum: 1 },
      },
    },
  ]);

  const watchStats = await AppAdEvent.aggregate([
    { $match: { ad: { $in: adIds } } },
    {
      $group: {
        _id: '$ad',
        totalWatchSeconds: { $sum: { $ifNull: ['$watchSeconds', 0] } },
        averageWatchSeconds: { $avg: { $ifNull: ['$watchSeconds', 0] } },
        uniqueUsers: { $addToSet: '$user' },
      },
    },
  ]);

  const aggregated = stats.reduce((acc, item) => {
    const adId = item._id.ad.toString();
    if (!acc[adId]) {
      acc[adId] = {
        impressions: 0,
        clicks: 0,
        closes: 0,
        hides: 0,
        reports: 0,
        totalWatchSeconds: 0,
        averageWatchSeconds: 0,
        uniqueUsers: 0,
      };
    }
    if (item._id.type === 'impression') acc[adId].impressions = item.count;
    if (item._id.type === 'click') acc[adId].clicks = item.count;
    if (item._id.type === 'close') acc[adId].closes = item.count;
    if (item._id.type === 'hide') acc[adId].hides = item.count;
    if (item._id.type === 'report') acc[adId].reports = item.count;
    return acc;
  }, {});

  for (const item of watchStats) {
    const adId = item._id.toString();
    if (!aggregated[adId]) {
      aggregated[adId] = {
        impressions: 0,
        clicks: 0,
        closes: 0,
        hides: 0,
        reports: 0,
        totalWatchSeconds: 0,
        averageWatchSeconds: 0,
        uniqueUsers: 0,
      };
    }
    aggregated[adId].totalWatchSeconds = item.totalWatchSeconds || 0;
    aggregated[adId].averageWatchSeconds = Math.round(item.averageWatchSeconds || 0);
    aggregated[adId].uniqueUsers = Array.isArray(item.uniqueUsers)
      ? item.uniqueUsers.length
      : 0;
  }

  return aggregated;
};

const aggregateUpdateReadStats = async (updateIds) => {
  if (!updateIds.length) return {};
  const stats = await AppUpdateRead.aggregate([
    { $match: { update: { $in: updateIds } } },
    {
      $group: {
        _id: '$update',
        readCount: { $sum: 1 },
        lastReadAt: { $max: '$readAt' },
      },
    },
  ]);

  return stats.reduce((acc, item) => {
    acc[item._id.toString()] = {
      readCount: item.readCount || 0,
      lastReadAt: item.lastReadAt || null,
    };
    return acc;
  }, {});
};

const aggregateAdModeration = async (adIds) => {
  if (!adIds.length) return {};

  const events = await AppAdEvent.find({
    ad: { $in: adIds },
    type: { $in: ['report', 'hide'] },
  })
    .select('ad type occurredAt metadata')
    .sort({ occurredAt: -1 })
    .lean();

  return events.reduce((acc, event) => {
    const adId = event.ad.toString();
    if (!acc[adId]) {
      acc[adId] = {
        recentReports: [],
        recentHides: [],
      };
    }

    if (event.type === 'report' && acc[adId].recentReports.length < 3) {
      acc[adId].recentReports.push({
        occurredAt: event.occurredAt,
        reason: (event.metadata?.reason || '').toString(),
      });
    }

    if (event.type === 'hide' && acc[adId].recentHides.length < 3) {
      acc[adId].recentHides.push({
        occurredAt: event.occurredAt,
      });
    }

    return acc;
  }, {});
};

const uploadAdMedia = async (file) => {
  if (!file) {
    return {
      mediaFileId: null,
      mediaFilename: '',
      mediaMimeType: '',
      mediaKind: 'none',
    };
  }

  const bucket = getAdMediaBucket();
  const uploadStream = bucket.openUploadStream(file.originalname, {
    contentType: file.mimetype,
    metadata: {
      uploadedAt: new Date(),
      originalName: file.originalname,
    },
  });

  try {
    await new Promise((resolve, reject) => {
      uploadStream.on('error', reject);
      uploadStream.on('finish', resolve);

      if (file.path) {
        const readStream = fs.createReadStream(file.path);
        readStream.on('error', reject);
        readStream.pipe(uploadStream);
        return;
      }

      uploadStream.end(file.buffer, (error) => {
        if (error) reject(error);
      });
    });
  } finally {
    if (file.path) {
      fs.promises.unlink(file.path).catch(() => {});
    }
  }

  return {
    mediaFileId: uploadStream.id,
    mediaFilename: file.originalname,
    mediaMimeType: file.mimetype || '',
    mediaKind: detectMediaKind(file.mimetype),
  };
};

const removeAdMedia = async (fileId) => {
  if (!fileId) return;
  try {
    const bucket = getAdMediaBucket();
    await bucket.delete(
      typeof fileId === 'string' ? new mongoose.Types.ObjectId(fileId) : fileId
    );
  } catch (error) {
    console.error('Failed to delete ad media from GridFS:', error);
  }
};

exports.listUpdates = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const isSubscribed =
      req.user?.role === 'user' ? await isUserSubscribed(req.user._id) : false;
    const userPlatform = getPlatformFromRequest(req);
    const updates = await AppUpdate.find({})
      .populate('createdBy', 'name email isSuperAdmin')
      .sort({ pinned: -1, publishedAt: -1 })
      .lean();

    const visibleUpdates = updates.filter((update) => {
      if (req.user?.role === 'user') {
        if ((update.status || 'published') === 'draft') return false;
        const scheduledFor = update.scheduledFor ? new Date(update.scheduledFor) : null;
        if (scheduledFor && scheduledFor > new Date()) return false;
      }
      const audience = update.targetAudience || 'all';
      if (req.user?.role === 'user') {
        if (audience === 'subscribed' && !isSubscribed) return false;
        if (audience === 'nonsubscribed' && isSubscribed) return false;
        const platforms = Array.isArray(update.platforms) ? update.platforms : ['all'];
        if (!platforms.includes('all') && !platforms.includes(userPlatform)) {
          return false;
        }
      }
      return true;
    });

    let readMap = new Map();
    if (req.user?.role === 'user' && visibleUpdates.length) {
      const reads = await AppUpdateRead.find({
        user: req.user._id,
        update: { $in: visibleUpdates.map((item) => item._id) },
      })
        .select('update readAt')
        .lean();
      readMap = new Map(reads.map((item) => [item.update.toString(), item.readAt]));
    }

    const readStatsByUpdate =
      req.user?.role === 'admin'
        ? await aggregateUpdateReadStats(visibleUpdates.map((item) => item._id))
        : {};

    res.json({
      updates: visibleUpdates.map((update) => ({
        ...toUpdateResponse(req, update, currentAdmin),
        isRead: readMap.has(update._id.toString()),
        readAt: readMap.get(update._id.toString()) || null,
        stats: readStatsByUpdate[update._id.toString()] || {
          readCount: 0,
          lastReadAt: null,
        },
      })),
    });
  } catch (error) {
    console.error('Failed to list updates:', error);
    res.status(500).json({ error: 'Failed to load updates' });
  }
};

exports.createUpdate = async (req, res) => {
  try {
    const {
      title,
      body,
      summary,
      versionTag,
      pinned,
      category,
      importance,
      targetAudience,
      platforms,
      tags,
      status,
      scheduledFor,
    } = req.body;
    if (!title?.trim() || !body?.trim()) {
      return res.status(400).json({ error: 'Title and body are required.' });
    }

    const normalizedStatus = normalizeUpdateStatus(status);
    const scheduledDate =
      normalizedStatus === 'scheduled' && scheduledFor ? new Date(scheduledFor) : null;
    const publishedAt =
      normalizedStatus === 'scheduled' && scheduledDate ? scheduledDate : new Date();

    const update = await AppUpdate.create({
      title: title.trim(),
      body: body.trim(),
      summary: (summary || '').trim(),
      versionTag: (versionTag || '').trim(),
      category: normalizeCategory(category),
      importance: normalizeImportance(importance),
      targetAudience: normalizeAudience(targetAudience, 'all'),
      platforms: normalizePlatforms(platforms),
      tags: normalizeStringArray(tags),
      status: normalizedStatus,
      scheduledFor: scheduledDate,
      pinned: pinned === true || pinned === 'true',
      publishedAt,
      createdBy: req.user._id,
    });

    const populated = await AppUpdate.findById(update._id)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    const currentAdmin = await getCurrentAdmin(req);

    // Fan out a notification to all users for published updates so it
    // appears in the user notifications page under the "Updates" tab.
    if (normalizedStatus === 'published') {
      try {
        const allUsers = await User.find({}, '_id').lean();
        const recipientIds = allUsers.map((u) => u._id);
        const notifMessage =
          update.summary?.trim() ||
          (update.body?.trim() || '').substring(0, 200) ||
          update.title.trim();
        await Notification.create({
          sender: req.user._id,
          senderModel: 'Admin',
          recipientType: 'all-users',
          recipients: recipientIds,
          recipientModel: 'User',
          title: update.title.trim(),
          message: notifMessage,
          category: 'update',
          deliveryStatus: 'sent',
          sentAt: new Date(),
          estimatedAudience: recipientIds.length,
          metadata: {
            updateId: update._id,
            updateCategory: update.category,
            importance: update.importance,
          },
        });
      } catch (notifErr) {
        // Non-fatal — the update is already saved; log and move on.
        console.error('Failed to fan out update notification:', notifErr);
      }
    }

    res.status(201).json({
      message: 'Update published successfully.',
      update: toUpdateResponse(req, populated, currentAdmin),
    });
  } catch (error) {
    console.error('Failed to create update:', error);
    res.status(500).json({ error: 'Failed to publish update' });
  }
};

exports.updateUpdate = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const existing = await AppUpdate.findById(req.params.updateId)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    if (!existing) {
      return res.status(404).json({ error: 'Update not found.' });
    }
    if (!canManageContent(currentAdmin, existing)) {
      return res.status(403).json({ error: 'You can only edit your own updates unless you are a superadmin.' });
    }

    const {
      title,
      body,
      summary,
      versionTag,
      pinned,
      category,
      importance,
      targetAudience,
      platforms,
      tags,
      status,
      scheduledFor,
    } = req.body;
    if (!title?.trim() || !body?.trim()) {
      return res.status(400).json({ error: 'Title and body are required.' });
    }

    const normalizedStatus = normalizeUpdateStatus(status);
    const scheduledDate =
      normalizedStatus === 'scheduled' && scheduledFor ? new Date(scheduledFor) : null;
    const publishedAt =
      normalizedStatus === 'scheduled' && scheduledDate ? scheduledDate : existing.publishedAt || new Date();

    // Snapshot current content before overwriting so viewers can see what changed.
    const snapshot = {
      editedAt: new Date(),
      title: existing.title,
      body: existing.body,
      summary: existing.summary || '',
      versionTag: existing.versionTag || '',
      category: existing.category || 'general',
      importance: existing.importance || 'normal',
      tags: Array.isArray(existing.tags) ? existing.tags : [],
      platforms: Array.isArray(existing.platforms) ? existing.platforms : ['all'],
      targetAudience: existing.targetAudience || 'all',
      status: existing.status || 'published',
    };

    const update = await AppUpdate.findByIdAndUpdate(
      req.params.updateId,
      {
        $set: {
          title: title.trim(),
          body: body.trim(),
          summary: (summary || '').trim(),
          versionTag: (versionTag || '').trim(),
          category: normalizeCategory(category),
          importance: normalizeImportance(importance),
          targetAudience: normalizeAudience(targetAudience, 'all'),
          platforms: normalizePlatforms(platforms),
          tags: normalizeStringArray(tags),
          status: normalizedStatus,
          scheduledFor: scheduledDate,
          pinned: pinned === true || pinned === 'true',
          publishedAt,
        },
        $push: { editHistory: snapshot },
      },
      { new: true }
    )
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();

    // Editing an update resets read state for all viewers — treat it as new content.
    await AppUpdateRead.deleteMany({ update: req.params.updateId });

    res.json({
      message: 'Update edited successfully.',
      update: toUpdateResponse(req, update, currentAdmin),
    });
  } catch (error) {
    console.error('Failed to update update:', error);
    res.status(500).json({ error: 'Failed to edit update' });
  }
};

exports.deleteUpdate = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const update = await AppUpdate.findById(req.params.updateId)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    if (!update) {
      return res.status(404).json({ error: 'Update not found.' });
    }
    if (!canManageContent(currentAdmin, update)) {
      return res.status(403).json({ error: 'You can only delete your own updates unless you are a superadmin.' });
    }
    await AppUpdate.findByIdAndDelete(req.params.updateId);
    res.json({ message: 'Update deleted successfully.' });
  } catch (error) {
    console.error('Failed to delete update:', error);
    res.status(500).json({ error: 'Failed to delete update' });
  }
};

exports.listAdminAds = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const ads = await AppAd.find({})
      .populate('createdBy', 'name email isSuperAdmin')
      .sort({ createdAt: -1 })
      .lean();
    const statsByAd = await aggregateAdStats(ads.map((ad) => ad._id));
    const moderationByAd = await aggregateAdModeration(ads.map((ad) => ad._id));

    res.json({
      ads: ads.map((ad) => ({
        ...toAdResponse(req, ad, currentAdmin),
        stats: statsByAd[ad._id.toString()] || {
          impressions: 0,
          clicks: 0,
          closes: 0,
          hides: 0,
          reports: 0,
          totalWatchSeconds: 0,
          averageWatchSeconds: 0,
          uniqueUsers: 0,
        },
        moderation: moderationByAd[ad._id.toString()] || {
          recentReports: [],
          recentHides: [],
        },
      })),
    });
  } catch (error) {
    console.error('Failed to load ads:', error);
    res.status(500).json({ error: 'Failed to load ads' });
  }
};

exports.getAdminContentAnalytics = async (req, res) => {
  try {
    const now = new Date();
    const [ads, updates] = await Promise.all([
      AppAd.find({}).populate('createdBy', 'name email isSuperAdmin').lean(),
      AppUpdate.find({})
        .populate('createdBy', 'name email isSuperAdmin')
        .lean(),
    ]);

    const adIds = ads.map((ad) => ad._id);
    const updateIds = updates.map((update) => update._id);
    const [statsByAd, moderationByAd, readStatsByUpdate] = await Promise.all([
      aggregateAdStats(adIds),
      aggregateAdModeration(adIds),
      aggregateUpdateReadStats(updateIds),
    ]);

    const adItems = ads.map((ad) => {
      const stats = statsByAd[ad._id.toString()] || {
        impressions: 0,
        clicks: 0,
        closes: 0,
        hides: 0,
        reports: 0,
        totalWatchSeconds: 0,
        averageWatchSeconds: 0,
        uniqueUsers: 0,
      };
      const ctr = stats.impressions > 0 ? (stats.clicks / stats.impressions) * 100 : 0;
      return {
        ...toAdResponse(req, ad),
        stats: {
          ...stats,
          ctr: Number(ctr.toFixed(1)),
        },
        moderation: moderationByAd[ad._id.toString()] || {
          recentReports: [],
          recentHides: [],
        },
      };
    });

    const updateItems = updates.map((update) => ({
      ...toUpdateResponse(req, update),
      stats: readStatsByUpdate[update._id.toString()] || {
        readCount: 0,
        lastReadAt: null,
      },
    }));

    const adSummary = adItems.reduce(
      (acc, ad) => {
        acc.totalAds += 1;
        if (ad.active) acc.activeAds += 1;
        if (ad.startsAt && new Date(ad.startsAt) > now) acc.scheduledAds += 1;
        acc.totalImpressions += ad.stats.impressions || 0;
        acc.totalClicks += ad.stats.clicks || 0;
        acc.totalReports += ad.stats.reports || 0;
        acc.totalHides += ad.stats.hides || 0;
        acc.totalWatchSeconds += ad.stats.totalWatchSeconds || 0;
        acc.totalReach += ad.stats.uniqueUsers || 0;
        return acc;
      },
      {
        totalAds: 0,
        activeAds: 0,
        scheduledAds: 0,
        totalImpressions: 0,
        totalClicks: 0,
        totalReports: 0,
        totalHides: 0,
        totalWatchSeconds: 0,
        totalReach: 0,
      }
    );

    const updateSummary = updateItems.reduce(
      (acc, update) => {
        acc.totalUpdates += 1;
        const status = (update.status || 'published').toString();
        if (status === 'published') acc.publishedUpdates += 1;
        if (status === 'draft') acc.draftUpdates += 1;
        if (status === 'scheduled') acc.scheduledUpdates += 1;
        if ((update.importance || 'normal') === 'critical') acc.criticalUpdates += 1;
        acc.totalReads += update.stats.readCount || 0;
        return acc;
      },
      {
        totalUpdates: 0,
        publishedUpdates: 0,
        draftUpdates: 0,
        scheduledUpdates: 0,
        criticalUpdates: 0,
        totalReads: 0,
      }
    );

    const ctr =
      adSummary.totalImpressions > 0
        ? (adSummary.totalClicks / adSummary.totalImpressions) * 100
        : 0;

    res.json({
      summary: {
        ...adSummary,
        ...updateSummary,
        averageCtr: Number(ctr.toFixed(1)),
      },
      topAds: [...adItems]
        .sort((a, b) => (b.stats.clicks || 0) - (a.stats.clicks || 0))
        .slice(0, 5),
      topUpdates: [...updateItems]
        .sort((a, b) => (b.stats.readCount || 0) - (a.stats.readCount || 0))
        .slice(0, 5),
      moderationQueue: [...adItems]
        .filter(
          (ad) =>
            (ad.stats.reports || 0) > 0 ||
            (ad.stats.hides || 0) > 0 ||
            (ad.moderation.recentReports || []).length > 0
        )
        .sort((a, b) => (b.stats.reports || 0) - (a.stats.reports || 0))
        .slice(0, 10),
    });
  } catch (error) {
    console.error('Failed to load admin content analytics:', error);
    res.status(500).json({ error: 'Failed to load content analytics' });
  }
};

exports.createAd = async (req, res) => {
  try {
    const {
      title,
      body,
      callToActionText,
      callToActionUrl,
      startsAt,
      endsAt,
      audience,
      placements,
      tags,
      priorityWeight,
      dailyCapPerUser,
      videoCloseAtPercent,
    } = req.body;

    if (!title?.trim()) {
      return res.status(400).json({ error: 'Ad title is required.' });
    }

    if (callToActionUrl && !/^https?:\/\//i.test(callToActionUrl.trim())) {
      return res
        .status(400)
        .json({ error: 'Call-to-action URL must start with http:// or https://.' });
    }

    const media = await uploadAdMedia(req.file);
    const ad = await AppAd.create({
      title: title.trim(),
      body: (body || '').trim(),
      callToActionText: (callToActionText || '').trim(),
      callToActionUrl: (callToActionUrl || '').trim(),
      audience: normalizeAudience(audience, 'nonsubscribed'),
      placements: normalizeStringArray(placements, ['dashboard']),
      tags: normalizeStringArray(tags),
      priorityWeight: normalizeWeight(priorityWeight),
      dailyCapPerUser: normalizeDailyCap(dailyCapPerUser),
      videoCloseAtPercent: normalizeVideoClosePercent(videoCloseAtPercent),
      startsAt: startsAt ? new Date(startsAt) : new Date(),
      endsAt: endsAt ? new Date(endsAt) : null,
      createdBy: req.user._id,
      ...media,
    });

    const saved = await AppAd.findById(ad._id).lean();
    const populated = await AppAd.findById(saved._id)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    const currentAdmin = await getCurrentAdmin(req);
    res.status(201).json({
      message: 'Ad created successfully.',
      ad: toAdResponse(req, populated, currentAdmin),
    });
  } catch (error) {
    console.error('Failed to create ad:', error);
    res.status(500).json({ error: 'Failed to create ad' });
  }
};

exports.updateAd = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const existing = await AppAd.findById(req.params.adId)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    if (!existing) {
      return res.status(404).json({ error: 'Ad not found.' });
    }
    if (!canManageContent(currentAdmin, existing)) {
      return res.status(403).json({ error: 'You can only edit your own ads unless you are a superadmin.' });
    }

    const {
      title,
      body,
      callToActionText,
      callToActionUrl,
      startsAt,
      endsAt,
      active,
      audience,
      placements,
      tags,
      priorityWeight,
      dailyCapPerUser,
      videoCloseAtPercent,
    } = req.body;

    if (!title?.trim()) {
      return res.status(400).json({ error: 'Ad title is required.' });
    }
    if (callToActionUrl && !/^https?:\/\//i.test(callToActionUrl.trim())) {
      return res
        .status(400)
        .json({ error: 'Call-to-action URL must start with http:// or https://.' });
    }

    let mediaUpdate = {};
    if (req.file) {
      await removeAdMedia(existing.mediaFileId);
      mediaUpdate = await uploadAdMedia(req.file);
    }

    const ad = await AppAd.findByIdAndUpdate(
      req.params.adId,
      {
        title: title.trim(),
        body: (body || '').trim(),
        callToActionText: (callToActionText || '').trim(),
        callToActionUrl: (callToActionUrl || '').trim(),
        audience: normalizeAudience(audience, 'nonsubscribed'),
        placements: normalizeStringArray(placements, ['dashboard']),
        tags: normalizeStringArray(tags),
        priorityWeight: normalizeWeight(priorityWeight),
        dailyCapPerUser: normalizeDailyCap(dailyCapPerUser),
        videoCloseAtPercent: normalizeVideoClosePercent(videoCloseAtPercent),
        startsAt: startsAt ? new Date(startsAt) : new Date(),
        endsAt: endsAt ? new Date(endsAt) : null,
        active: active === true || active === 'true',
        ...mediaUpdate,
      },
      { new: true }
    )
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();

    res.json({
      message: 'Ad edited successfully.',
      ad: toAdResponse(req, ad, currentAdmin),
    });
  } catch (error) {
    console.error('Failed to edit ad:', error);
    res.status(500).json({ error: 'Failed to edit ad' });
  }
};

exports.toggleAd = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const existing = await AppAd.findById(req.params.adId)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    if (!existing) {
      return res.status(404).json({ error: 'Ad not found.' });
    }
    if (!canManageContent(currentAdmin, existing)) {
      return res.status(403).json({ error: 'You can only edit your own ads unless you are a superadmin.' });
    }

    const { active } = req.body;
    const ad = await AppAd.findByIdAndUpdate(
      req.params.adId,
      { active: active === true || active === 'true' },
      { new: true }
    ).populate('createdBy', 'name email isSuperAdmin').lean();

    res.json({
      message: 'Ad status updated.',
      ad: toAdResponse(req, ad, currentAdmin),
    });
  } catch (error) {
    console.error('Failed to update ad:', error);
    res.status(500).json({ error: 'Failed to update ad' });
  }
};

exports.deleteAd = async (req, res) => {
  try {
    const currentAdmin = await getCurrentAdmin(req);
    const ad = await AppAd.findById(req.params.adId)
      .populate('createdBy', 'name email isSuperAdmin')
      .lean();
    if (!ad) {
      return res.status(404).json({ error: 'Ad not found.' });
    }
    if (!canManageContent(currentAdmin, ad)) {
      return res.status(403).json({ error: 'You can only delete your own ads unless you are a superadmin.' });
    }

    await AppAd.findByIdAndDelete(req.params.adId);
    await removeAdMedia(ad.mediaFileId);
    res.json({ message: 'Ad deleted successfully.' });
  } catch (error) {
    console.error('Failed to delete ad:', error);
    res.status(500).json({ error: 'Failed to delete ad' });
  }
};

exports.getRandomActiveAd = async (req, res) => {
  try {
    // Ads are a user-only feature — never serve them to admin accounts.
    if (req.user?.role === 'admin') {
      return res.json({ ad: null });
    }

    const now = new Date();
    const platform = getPlatformFromRequest(req);
    const userId = req.user?._id;
    const subscribed =
      req.user?.role === 'user' ? await isUserSubscribed(userId) : false;

    const ads = await AppAd.find({
      active: true,
      startsAt: { $lte: now },
      $or: [{ endsAt: null }, { endsAt: { $gte: now } }],
    }).lean();

    const startOfDay = new Date(now);
    startOfDay.setHours(0, 0, 0, 0);

    const dailyEvents = userId
      ? await AppAdEvent.aggregate([
          {
            $match: {
              user: userId,
              type: 'impression',
              occurredAt: { $gte: startOfDay },
            },
          },
          { $group: { _id: '$ad', count: { $sum: 1 } } },
        ])
      : [];
    const dailyCounts = new Map(
      dailyEvents.map((item) => [item._id.toString(), item.count])
    );

    const hideWindowStart = new Date(now);
    hideWindowStart.setDate(hideWindowStart.getDate() - 7);

    const hiddenAdIds = userId
      ? new Set(
          (
            await AppAdEvent.find({
              user: userId,
              type: 'hide',
              occurredAt: { $gte: hideWindowStart },
            })
              .select('ad metadata occurredAt')
              .lean()
          )
            .filter((item) => {
              const mode = (item.metadata?.hideMode || 'today').toString();
              if (mode === 'week' || mode === 'not_interested') {
                return true;
              }
              return new Date(item.occurredAt) >= startOfDay;
            })
            .map((item) => item.ad.toString())
        )
      : new Set();

    const eligibleAds = ads.filter((ad) => {
      const audience = ad.audience || 'nonsubscribed';
      if (audience === 'subscribed' && !subscribed) return false;
      if (audience === 'nonsubscribed' && subscribed) return false;
      const placements = Array.isArray(ad.placements) ? ad.placements : ['dashboard'];
      if (!placements.includes('all') && !placements.includes('dashboard')) return false;
      if (hiddenAdIds.has(ad._id.toString())) return false;
      const cap = normalizeDailyCap(ad.dailyCapPerUser);
      if ((dailyCounts.get(ad._id.toString()) || 0) >= cap) return false;
      return true;
    });

    let ad = null;
    if (eligibleAds.length) {
      const totalWeight = eligibleAds.reduce(
        (sum, item) => sum + normalizeWeight(item.priorityWeight),
        0
      );
      let draw = Math.random() * totalWeight;
      for (const item of eligibleAds) {
        draw -= normalizeWeight(item.priorityWeight);
        if (draw <= 0) {
          ad = item;
          break;
        }
      }
      ad = ad || eligibleAds[eligibleAds.length - 1];
    }

    // Unique ETag per call prevents 304 — ad selection is random so responses may always differ.
    // Express only auto-generates an ETag when none is set, so setting one here locks it in.
    const uniqueTag = `"${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}"`;
    res.setHeader('ETag', uniqueTag);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

    if (!ad) {
      return res.json({ ad: null });
    }

    res.json({ ad: toAdResponse(req, ad) });
  } catch (error) {
    console.error('Failed to fetch random ad:', error);
    res.status(500).json({ error: 'Failed to fetch ad' });
  }
};

exports.markUpdateRead = async (req, res) => {
  try {
    if (req.user?.role !== 'user') {
      return res.status(403).json({ error: 'Only users can mark updates as read.' });
    }
    const update = await AppUpdate.findById(req.params.updateId).lean();
    if (!update) {
      return res.status(404).json({ error: 'Update not found.' });
    }

    await AppUpdateRead.findOneAndUpdate(
      { update: update._id, user: req.user._id },
      { $set: { readAt: new Date() } },
      { upsert: true, new: true }
    );

    res.json({ message: 'Update marked as read.' });
  } catch (error) {
    console.error('Failed to mark update as read:', error);
    res.status(500).json({ error: 'Failed to mark update as read' });
  }
};

exports.markAllUpdatesRead = async (req, res) => {
  try {
    if (req.user?.role !== 'user') {
      return res.status(403).json({ error: 'Only users can mark updates as read.' });
    }

    const now = new Date();
    const isSubscribed = await isUserSubscribed(req.user._id);
    const userPlatform = getPlatformFromRequest(req);
    const updates = await AppUpdate.find({
      status: { $ne: 'draft' },
      $or: [{ scheduledFor: null }, { scheduledFor: { $lte: now } }],
      $or: [{ publishedAt: null }, { publishedAt: { $lte: now } }],
    })
      .select('_id targetAudience platforms')
      .lean();

    const visibleIds = updates
      .filter((update) => {
        const audience = update.targetAudience || 'all';
        if (audience === 'subscribed' && !isSubscribed) return false;
        if (audience === 'nonsubscribed' && isSubscribed) return false;
        const platforms = Array.isArray(update.platforms) ? update.platforms : ['all'];
        if (!platforms.includes('all') && !platforms.includes(userPlatform)) return false;
        return true;
      })
      .map((update) => update._id);

    if (!visibleIds.length) {
      return res.json({ message: 'No visible updates to mark as read.' });
    }

    await Promise.all(
      visibleIds.map((updateId) =>
        AppUpdateRead.findOneAndUpdate(
          { update: updateId, user: req.user._id },
          { $set: { readAt: now } },
          { upsert: true, new: true }
        )
      )
    );

    res.json({ message: 'All visible updates marked as read.' });
  } catch (error) {
    console.error('Failed to mark all updates as read:', error);
    res.status(500).json({ error: 'Failed to mark all updates as read' });
  }
};

exports.trackAdEvent = async (req, res) => {
  try {
    if (req.user?.role !== 'user') {
      return res.status(403).json({ error: 'Only users can track ad events.' });
    }

    const { type, watchSeconds, metadata } = req.body || {};
    if (!['impression', 'click', 'close', 'hide', 'report'].includes(type)) {
      return res.status(400).json({ error: 'Invalid ad event type.' });
    }

    const ad = await AppAd.findById(req.params.adId).select('_id').lean();
    if (!ad) {
      return res.status(404).json({ error: 'Ad not found.' });
    }

    await AppAdEvent.create({
      ad: ad._id,
      user: req.user._id,
      type,
      watchSeconds: Number.parseInt(watchSeconds, 10) || 0,
      metadata: metadata && typeof metadata === 'object' ? metadata : {},
      occurredAt: new Date(),
    });

    res.json({ message: 'Ad event tracked.' });
  } catch (error) {
    console.error('Failed to track ad event:', error);
    res.status(500).json({ error: 'Failed to track ad event' });
  }
};

const _mimeFromFilename = (filename = '') => {
  const ext = filename.split('.').pop().toLowerCase();
  const map = {
    mp4: 'video/mp4',
    mov: 'video/quicktime',
    avi: 'video/x-msvideo',
    mkv: 'video/x-matroska',
    webm: 'video/webm',
    jpg: 'image/jpeg',
    jpeg: 'image/jpeg',
    png: 'image/png',
    gif: 'image/gif',
    webp: 'image/webp',
  };
  return map[ext] || null;
};

exports.streamAdMedia = async (req, res) => {
  // Allow cross-origin video loading (needed for Flutter Web and browser-based players)
  res.set({
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Expose-Headers': 'Content-Range, Content-Length, Accept-Ranges, Content-Disposition',
  });

  if (req.method === 'OPTIONS') {
    res.set('Access-Control-Allow-Headers', 'Range');
    return res.sendStatus(204);
  }

  let fileId;
  try {
    fileId = new mongoose.Types.ObjectId(req.params.fileId);
  } catch {
    return res.status(400).json({ error: 'Invalid media ID.' });
  }

  try {
    const bucket = getAdMediaBucket();
    const files = await bucket.find({ _id: fileId }).toArray();
    const file = files[0];

    if (!file) {
      return res.status(404).json({ error: 'Media not found.' });
    }

    // Derive content type from filename extension as the reliable fallback
    const contentType =
      (file.contentType && file.contentType !== 'application/octet-stream')
        ? file.contentType
        : (_mimeFromFilename(file.filename) || 'application/octet-stream');

    const disposition = `inline; filename="${file.filename || 'media'}"`;
    const range = req.headers.range;

    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10) || 0;
      const end = parts[1] && parts[1].trim() !== ''
        ? Math.min(parseInt(parts[1], 10), file.length - 1)
        : file.length - 1;

      if (start > end || start >= file.length) {
        res.set('Content-Range', `bytes */${file.length}`);
        return res.status(416).json({ error: 'Range not satisfiable.' });
      }

      const chunkSize = end - start + 1;
      res.status(206);
      res.set({
        'Content-Range': `bytes ${start}-${end}/${file.length}`,
        'Accept-Ranges': 'bytes',
        'Content-Length': chunkSize,
        'Content-Type': contentType,
        'Content-Disposition': disposition,
        'Cache-Control': 'public, max-age=3600',
      });

      const downloadStream = bucket.openDownloadStream(fileId, { start, end: end + 1 });
      req.on('close', () => downloadStream.destroy());
      downloadStream.on('error', (err) => {
        console.error('GridFS range stream error:', err);
        if (!res.writableEnded) res.end();
      });
      downloadStream.pipe(res);
      return;
    }

    res.status(200);
    res.set({
      'Content-Length': file.length,
      'Content-Type': contentType,
      'Accept-Ranges': 'bytes',
      'Content-Disposition': disposition,
      'Cache-Control': 'public, max-age=3600',
    });

    const downloadStream = bucket.openDownloadStream(fileId);
    req.on('close', () => downloadStream.destroy());
    downloadStream.on('error', (err) => {
      console.error('GridFS stream error:', err);
      if (!res.writableEnded) res.end();
    });
    downloadStream.pipe(res);
  } catch (error) {
    console.error('Failed to stream ad media:', error);
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to stream media.' });
    }
  }
};
