const mongoose = require('mongoose');
const Offer = require('../models/offer');
const OfferClaim = require('../models/offerClaim');
const User = require('../models/user');
const Notification = require('../models/notification');
const Admin = require('../models/admin');
const { createActivityLog } = require('./activityController');
const { recordCoinLedgerEntry } = require('../utils/coinLedgerService');

const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const MAX_COINS_PER_OFFER = 10000;
const MAX_ACTIVE_OFFERS = 50;
const MAX_DAILY_CLAIMS_PER_USER = 20;
const ENDED_OFFER_RETENTION_DAYS = 30;

const ensureValidDate = (value, fieldName) => {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`${fieldName} must be a valid date`);
  }
  return parsed;
};

const normalizeStatus = (status) => {
  if (!status) return null;
  const s = status.toString().trim().toLowerCase();
  if (['draft', 'scheduled', 'active', 'ended'].includes(s)) return s;
  return null;
};

const computeOfferStatus = ({ status, startsAt, endsAt, isActive }) => {
  const now = new Date();
  const start = startsAt instanceof Date ? startsAt : new Date(startsAt);
  const end = endsAt instanceof Date ? endsAt : new Date(endsAt);
  const normalized = normalizeStatus(status);

  if (normalized === 'draft') return 'draft';
  if (!isActive) return 'draft';
  if (end < now) return 'ended';
  if (start > now) return 'scheduled';
  return 'active';
};

const toObjectIdStrings = (ids = []) =>
  ids.map((id) => id.toString().trim()).filter(Boolean);

const resolveRecipientUserIds = async ({ recipientType, recipientUserIds, recipientEmails }) => {
  if (recipientType !== 'specific-users') return [];

  const ids = Array.isArray(recipientUserIds) ? toObjectIdStrings(recipientUserIds) : [];
  const emails = Array.isArray(recipientEmails)
    ? recipientEmails.map((e) => e.toString().trim().toLowerCase()).filter(Boolean)
    : [];

  let users = [];
  if (ids.length) users = users.concat(await User.find({ _id: { $in: ids } }, '_id'));
  if (emails.length) users = users.concat(await User.find({ email: { $in: emails } }, '_id'));

  const unique = [...new Set(users.map((u) => u._id.toString()))];
  if (!unique.length) throw new Error('No valid users found for specific-users offer');
  return unique;
};

const getOfferSnapshot = (offer) => ({
  name: offer.name,
  description: offer.description,
  coins: offer.coins,
  startsAt: offer.startsAt,
  endsAt: offer.endsAt,
  isActive: offer.isActive,
  status: offer.status,
  recipientType: offer.recipientType,
  recipients: offer.recipients || [],
});

const validateOfferConstraints = async ({ coins, status }) => {
  if (coins > MAX_COINS_PER_OFFER) {
    throw new Error(`coins cannot exceed ${MAX_COINS_PER_OFFER}`);
  }

  if (status === 'active') {
    const activeCount = await Offer.countDocuments({ status: 'active' });
    if (activeCount >= MAX_ACTIVE_OFFERS) {
      throw new Error(`Maximum ${MAX_ACTIVE_OFFERS} active offers allowed`);
    }
  }
};

const getTodayRange = () => {
  const now = new Date();
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  const end = new Date(now);
  end.setHours(23, 59, 59, 999);
  return { start, end };
};

const normalizePermissions = (permissions = {}) => ({
  canManageUsers: permissions.canManageUsers !== false,
  canManageTransactions: permissions.canManageTransactions !== false,
  canManageSupport: permissions.canManageSupport !== false,
  canManageContent: permissions.canManageContent !== false,
  canManageDigitise: permissions.canManageDigitise !== false,
  canManageSettings: permissions.canManageSettings !== false,
  canViewAuditLogs: permissions.canViewAuditLogs !== false,
});

const getCurrentAdmin = async (req) => {
  const adminId = req.user?._id || req.user?.userId || req.user?.id;
  if (adminId) {
    const admin = await Admin.findById(adminId).select('_id email isSuperAdmin permissions').lean();
    if (admin) return admin;
  }
  if (req.user?.email) {
    return Admin.findOne({ email: req.user.email })
      .select('_id email isSuperAdmin permissions')
      .lean();
  }
  return null;
};

const ensureDigitisePermission = async (req, res) => {
  const currentAdmin = await getCurrentAdmin(req);
  if (
    !currentAdmin ||
    !(currentAdmin.isSuperAdmin === true ||
      normalizePermissions(currentAdmin.permissions || {}).canManageDigitise === true)
  ) {
    res.status(403).json({ error: 'You do not have permission to manage offers' });
    return null;
  }
  return currentAdmin;
};

const sendOfferNotificationToUsers = async ({
  adminId,
  message,
  recipientType = 'all-users',
  recipientIds = [],
}) => {
  let recipients = [];
  let notificationRecipientType = 'all-users';

  if (recipientType === 'specific-users') {
    notificationRecipientType = 'specific-users';
    recipients = recipientIds;
    if (!recipients.length) return;
  } else {
    const users = await User.find({}, '_id');
    recipients = users.map((u) => u._id);
    if (!recipients.length) return;
  }

  const notification = new Notification({
    sender: adminId,
    senderModel: 'Admin',
    recipientType: notificationRecipientType,
    recipients,
    recipientModel: 'User',
    message,
  });
  await notification.save();
};

const syncOfferStatuses = async () => {
  const now = new Date();
  await Offer.updateMany(
    { isActive: true, status: { $in: ['scheduled', 'active'] }, endsAt: { $lt: now } },
    { $set: { status: 'ended' } }
  );

  const readyToActivate = await Offer.find({
    isActive: true,
    status: 'scheduled',
    startsAt: { $lte: now },
    endsAt: { $gte: now },
  });

  for (const offer of readyToActivate) {
    offer.status = 'active';
    await offer.save();

    const shouldNotify = (offer.lastNotifiedVersion || 0) < (offer.version || 1);
    if (shouldNotify) {
      try {
        await sendOfferNotificationToUsers({
          adminId: offer.updatedBy || offer.createdBy,
          message: `Offer is now live v${offer.version}: "${offer.name}" (+${offer.coins} coins). Accept before ${offer.endsAt.toLocaleString()}.`,
          recipientType: offer.recipientType,
          recipientIds: offer.recipients,
        });
        offer.lastNotifiedVersion = offer.version || 1;
        await offer.save();
      } catch (error) {
        console.error(
          `[OfferNotification] Failed for activated offer ${offer._id}: ${error.message}`
        );
      }
    }
  }
};

const notifyIfOfferIsActive = async (offer, adminId, prefix = 'New offer') => {
  if (offer.status !== 'active') return;

  const notifiedVersion = offer.lastNotifiedVersion || 0;
  const currentVersion = offer.version || 1;
  if (notifiedVersion >= currentVersion) return;

  await sendOfferNotificationToUsers({
    adminId,
    message: `${prefix} v${currentVersion}: "${offer.name}" (+${offer.coins} coins). Accept before ${offer.endsAt.toLocaleString()}.`,
    recipientType: offer.recipientType,
    recipientIds: offer.recipients,
  });
  offer.lastNotifiedVersion = currentVersion;
  await offer.save();
};

const cleanupExpiredOffers = async () => {
  await syncOfferStatuses();

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - ENDED_OFFER_RETENTION_DAYS);

  const oldEnded = await Offer.find({
    status: 'ended',
    endsAt: { $lt: cutoff },
  }).select('_id');
  if (!oldEnded.length) return { deletedOffers: 0, deletedClaims: 0 };

  const offerIds = oldEnded.map((o) => o._id);
  const claimDelete = await OfferClaim.deleteMany({ offer: { $in: offerIds } });
  const offerDelete = await Offer.deleteMany({ _id: { $in: offerIds } });
  return {
    deletedOffers: offerDelete.deletedCount || 0,
    deletedClaims: claimDelete.deletedCount || 0,
  };
};

const rollbackOfferClaimsForUpdate = async (offerId, reason = 'Offer updated') => {
  const claims = await OfferClaim.find({ offer: offerId, revoked: false }).select(
    'user coinsAwarded'
  );
  if (!claims.length) {
    return { affectedUsers: 0, revertedCoins: 0, revertedClaims: 0 };
  }

  const coinsByUser = new Map();
  let revertedCoins = 0;
  for (const claim of claims) {
    const userId = claim.user.toString();
    const coins = Number(claim.coinsAwarded || 0);
    revertedCoins += coins;
    coinsByUser.set(userId, (coinsByUser.get(userId) || 0) + coins);
  }

  const userBulkOps = [...coinsByUser.entries()].map(([userId, coins]) => ({
    updateOne: { filter: { _id: userId }, update: { $inc: { lenDenCoins: -coins } } },
  }));
  if (userBulkOps.length) await User.bulkWrite(userBulkOps);

  const now = new Date();
  const claimUpdate = await OfferClaim.updateMany(
    { offer: offerId, revoked: false },
    { $set: { revoked: true, revokedAt: now, revokedReason: reason } }
  );

  return {
    affectedUsers: coinsByUser.size,
    revertedCoins,
    revertedClaims: claimUpdate.modifiedCount || 0,
  };
};

exports.cleanupExpiredOffers = cleanupExpiredOffers;

exports.createOffer = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    const {
      name,
      description,
      coins,
      startsAt,
      endsAt,
      isActive,
      recipientType = 'all-users',
      recipientUserIds,
      recipientEmails,
      status,
    } = req.body;

    if (!name || !coins || !startsAt || !endsAt) {
      return res
        .status(400)
        .json({ error: 'name, coins, startsAt and endsAt are required' });
    }
    if (!['all-users', 'specific-users'].includes(recipientType)) {
      return res
        .status(400)
        .json({ error: 'recipientType must be all-users or specific-users' });
    }

    await cleanupExpiredOffers();

    const startDate = ensureValidDate(startsAt, 'startsAt');
    const endDate = ensureValidDate(endsAt, 'endsAt');
    if (endDate <= startDate) {
      return res.status(400).json({ error: 'endsAt must be later than startsAt' });
    }

    const resolvedRecipientIds = await resolveRecipientUserIds({
      recipientType,
      recipientUserIds,
      recipientEmails,
    });

    const normalizedStatus = normalizeStatus(status) || computeOfferStatus({
      startsAt: startDate,
      endsAt: endDate,
      isActive: typeof isActive === 'boolean' ? isActive : true,
      status: status || null,
    });

    await validateOfferConstraints({
      coins: Number(coins),
      status: normalizedStatus,
    });

    const newOffer = await Offer.create({
      name: name.toString().trim(),
      description: (description || '').toString().trim(),
      coins: Number(coins),
      startsAt: startDate,
      endsAt: endDate,
      isActive: typeof isActive === 'boolean' ? isActive : true,
      status: normalizedStatus,
      version: 1,
      lastNotifiedVersion: 0,
      recipientType,
      recipients: resolvedRecipientIds,
      createdBy: req.user._id,
      updatedBy: req.user._id,
      changeLog: [],
    });

    try {
      await notifyIfOfferIsActive(newOffer, req.user._id, 'New offer');
    } catch (error) {
      console.error(`[OfferNotification] Create notify failed: ${error.message}`);
    }

    const populated = await Offer.findById(newOffer._id)
      .populate('createdBy', 'name email username')
      .populate('updatedBy', 'name email username')
      .populate('recipients', 'name username email');
    return res.status(201).json(populated);
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }
};

exports.getAdminOffers = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    await cleanupExpiredOffers();
    const {
      includeInactive = 'true',
      status,
      search = '',
      page = '1',
      limit = '50',
      sortBy = 'createdAt',
      order = 'desc',
    } = req.query;

    const query = {};
    if (includeInactive !== 'true') query.isActive = true;
    if (status) query.status = status;
    if (search.toString().trim()) {
      const safeSearch = escapeRegex(search.toString().trim());
      query.$or = [
        { name: { $regex: safeSearch, $options: 'i' } },
        { description: { $regex: safeSearch, $options: 'i' } },
      ];
    }

    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
    const sort = { [sortBy]: order === 'asc' ? 1 : -1 };

    const [offers, total] = await Promise.all([
      Offer.find(query)
        .populate('createdBy', 'name email username')
        .populate('updatedBy', 'name email username')
        .populate('recipients', 'name username email')
        .sort(sort)
        .skip((parsedPage - 1) * parsedLimit)
        .limit(parsedLimit),
      Offer.countDocuments(query),
    ]);

    const offerIds = offers.map((o) => o._id);
    const claimAgg = await OfferClaim.aggregate([
      { $match: { offer: { $in: offerIds }, revoked: false } },
      { $group: { _id: '$offer', acceptedCount: { $sum: 1 }, coins: { $sum: '$coinsAwarded' } } },
    ]);
    const claimMap = new Map(claimAgg.map((c) => [c._id.toString(), c]));

    const enriched = offers.map((offer) => {
      const claim = claimMap.get(offer._id.toString()) || { acceptedCount: 0, coins: 0 };
      const targetedCount =
        offer.recipientType === 'specific-users' ? (offer.recipients?.length || 0) : null;
      const acceptanceRate =
        targetedCount && targetedCount > 0
          ? Number(((claim.acceptedCount / targetedCount) * 100).toFixed(2))
          : null;

      return {
        ...offer.toObject(),
        analytics: {
          acceptedCount: claim.acceptedCount,
          distributedCoins: claim.coins,
          targetedCount,
          acceptanceRate,
        },
      };
    });

    return res.json({
      items: enriched,
      pagination: {
        page: parsedPage,
        limit: parsedLimit,
        total,
        totalPages: Math.ceil(total / parsedLimit),
      },
    });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.updateOffer = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    await cleanupExpiredOffers();
    const { offerId } = req.params;
    const offer = await Offer.findById(offerId);
    if (!offer) return res.status(404).json({ error: 'Offer not found' });

    const {
      name,
      description,
      coins,
      startsAt,
      endsAt,
      isActive,
      recipientType,
      recipientUserIds,
      recipientEmails,
      status,
      updateReason = 'Offer updated',
    } = req.body;

    const previousSnapshot = getOfferSnapshot(offer);

    if (name !== undefined) offer.name = name.toString().trim();
    if (description !== undefined) offer.description = description.toString().trim();
    if (coins !== undefined) offer.coins = Number(coins);
    if (startsAt !== undefined) offer.startsAt = ensureValidDate(startsAt, 'startsAt');
    if (endsAt !== undefined) offer.endsAt = ensureValidDate(endsAt, 'endsAt');
    if (isActive !== undefined) offer.isActive = Boolean(isActive);

    if (recipientType !== undefined) {
      if (!['all-users', 'specific-users'].includes(recipientType)) {
        return res
          .status(400)
          .json({ error: 'recipientType must be all-users or specific-users' });
      }
      offer.recipientType = recipientType;
      offer.recipients = await resolveRecipientUserIds({
        recipientType,
        recipientUserIds,
        recipientEmails,
      });
    } else if (
      offer.recipientType === 'specific-users' &&
      (recipientUserIds !== undefined || recipientEmails !== undefined)
    ) {
      offer.recipients = await resolveRecipientUserIds({
        recipientType: 'specific-users',
        recipientUserIds,
        recipientEmails,
      });
    }

    if (offer.endsAt <= offer.startsAt) {
      return res.status(400).json({ error: 'endsAt must be later than startsAt' });
    }

    const explicitStatus = normalizeStatus(status);
    offer.status = explicitStatus || computeOfferStatus(offer);
    await validateOfferConstraints({ coins: offer.coins, status: offer.status });

    offer.changeLog.push({
      version: offer.version,
      changedAt: new Date(),
      changedBy: req.user._id,
      reason: updateReason.toString(),
      snapshot: previousSnapshot,
    });
    offer.version += 1;
    offer.updatedBy = req.user._id;
    await offer.save();

    const rollbackSummary = await rollbackOfferClaimsForUpdate(
      offer._id,
      `Offer updated to v${offer.version}`
    );

    try {
      await notifyIfOfferIsActive(
        offer,
        req.user._id,
        'Offer updated'
      );
    } catch (error) {
      console.error(`[OfferNotification] Update notify failed: ${error.message}`);
    }

    const populated = await Offer.findById(offer._id)
      .populate('createdBy', 'name email username')
      .populate('updatedBy', 'name email username')
      .populate('recipients', 'name username email');

    return res.json({ offer: populated, rollbackSummary });
  } catch (error) {
    return res.status(400).json({ error: error.message });
  }
};

exports.deleteOffer = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    const { offerId } = req.params;
    const offer = await Offer.findById(offerId);
    if (!offer) return res.status(404).json({ error: 'Offer not found' });

    await OfferClaim.deleteMany({ offer: offer._id });
    await offer.deleteOne();
    return res.json({ message: 'Offer deleted successfully' });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.getAvailableOffers = async (req, res) => {
  try {
    await cleanupExpiredOffers();
    const userId = req.user._id;
    const {
      sortBy = 'endsAt',
      order = 'asc',
      q = '',
      claimStatus = 'all',
      page = '1',
      limit = '50',
    } = req.query;

    const query = {
      status: 'active',
      $or: [
        { recipientType: 'all-users' },
        { recipientType: 'specific-users', recipients: userId },
      ],
    };

    if (q.toString().trim()) {
      const safeQ = escapeRegex(q.toString().trim());
      query.$and = [
        {
          $or: [
            { name: { $regex: safeQ, $options: 'i' } },
            { description: { $regex: safeQ, $options: 'i' } },
          ],
        },
      ];
    }

    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);
    const sort = { [sortBy]: order === 'desc' ? -1 : 1, createdAt: -1 };

    const offers = await Offer.find(query)
      .sort(sort)
      .skip((parsedPage - 1) * parsedLimit)
      .limit(parsedLimit);

    if (!offers.length) {
      return res.json({
        items: [],
        pagination: { page: parsedPage, limit: parsedLimit, total: 0, totalPages: 0 },
      });
    }

    const offerIds = offers.map((o) => o._id);
    const claims = await OfferClaim.find({
      user: userId,
      offer: { $in: offerIds },
      revoked: false,
    }).select('offer claimedAt coinsAwarded offerVersion');
    const claimMap = new Map(claims.map((c) => [c.offer.toString(), c]));

    let items = offers.map((offer) => {
      const claim = claimMap.get(offer._id.toString());
      const now = Date.now();
      const endsMs = new Date(offer.endsAt).getTime();
      const remainingMs = Math.max(0, endsMs - now);
      return {
        _id: offer._id,
        name: offer.name,
        description: offer.description,
        coins: offer.coins,
        startsAt: offer.startsAt,
        endsAt: offer.endsAt,
        createdAt: offer.createdAt,
        status: offer.status,
        version: offer.version,
        recipientType: offer.recipientType,
        claimed: Boolean(claim),
        claimedAt: claim?.claimedAt || null,
        claimedCoins: claim?.coinsAwarded || null,
        claimedVersion: claim?.offerVersion || null,
        timeRemainingMs: remainingMs,
      };
    });

    if (claimStatus === 'claimed') items = items.filter((i) => i.claimed);
    if (claimStatus === 'unclaimed') items = items.filter((i) => !i.claimed);

    return res.json({
      items,
      pagination: {
        page: parsedPage,
        limit: parsedLimit,
        total: items.length,
        totalPages: Math.ceil(items.length / parsedLimit),
      },
    });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.acceptOffer = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    await cleanupExpiredOffers();
    const { offerId } = req.params;
    const userId = req.user._id;
    const idempotencyKey =
      req.headers['x-idempotency-key']?.toString().trim() ||
      req.body?.idempotencyKey?.toString().trim() ||
      null;

    let responsePayload = null;
    await session.withTransaction(async () => {
      const offer = await Offer.findById(offerId).session(session);
      if (!offer) throw new Error('Offer not found or expired');
      if (offer.status !== 'active') throw new Error('Offer is not active');

      const allowedForUser =
        offer.recipientType === 'all-users' ||
        (offer.recipientType === 'specific-users' &&
          offer.recipients.some((id) => id.toString() === userId.toString()));
      if (!allowedForUser) throw new Error('This offer is not assigned to your account');

      const { start, end } = getTodayRange();
      const dailyClaims = await OfferClaim.countDocuments({
        user: userId,
        claimedAt: { $gte: start, $lte: end },
        revoked: false,
      }).session(session);
      if (dailyClaims >= MAX_DAILY_CLAIMS_PER_USER) {
        throw new Error(`Daily claim limit reached (${MAX_DAILY_CLAIMS_PER_USER})`);
      }

      const existing = await OfferClaim.findOne({
        offer: offer._id,
        user: userId,
        revoked: false,
      }).session(session);
      if (existing) {
        const user = await User.findById(userId).session(session);
        responsePayload = {
          message: 'Offer already accepted',
          coinsAwarded: existing.coinsAwarded,
          totalCoins: user?.lenDenCoins || 0,
          offerId: offer._id,
          alreadyAccepted: true,
        };
        return;
      }

      const nowClaimTime = new Date();
      const revokedClaimToReuse = await OfferClaim.findOne({
        offer: offer._id,
        user: userId,
        revoked: true,
      })
        .sort({ claimedAt: -1 })
        .session(session);

      if (revokedClaimToReuse) {
        revokedClaimToReuse.coinsAwarded = offer.coins;
        revokedClaimToReuse.claimedAt = nowClaimTime;
        revokedClaimToReuse.offerVersion = offer.version;
        revokedClaimToReuse.idempotencyKey = idempotencyKey || null;
        revokedClaimToReuse.revoked = false;
        revokedClaimToReuse.revokedAt = null;
        revokedClaimToReuse.revokedReason = null;
        await revokedClaimToReuse.save({ session });
      } else {
        try {
          await OfferClaim.create(
            [
              {
                offer: offer._id,
                user: userId,
                coinsAwarded: offer.coins,
                claimedAt: nowClaimTime,
                offerVersion: offer.version,
                idempotencyKey,
                revoked: false,
              },
            ],
            { session }
          );
        } catch (err) {
          if (err.code === 11000) {
            const claim = await OfferClaim.findOne({
              offer: offer._id,
              user: userId,
              revoked: false,
            }).session(session);
            if (claim) {
              const user = await User.findById(userId).session(session);
              responsePayload = {
                message: 'Offer already accepted',
                coinsAwarded: claim.coinsAwarded || 0,
                totalCoins: user?.lenDenCoins || 0,
                offerId: offer._id,
                alreadyAccepted: true,
              };
              return;
            }
            throw new Error('Offer claim conflict. Please retry.');
          }
          throw err;
        }
      }

      const user = await User.findByIdAndUpdate(
        userId,
        { $inc: { lenDenCoins: offer.coins } },
        { new: true, session }
      );
      if (!user) throw new Error('User not found');

      responsePayload = {
        message: 'Offer accepted successfully',
        coinsAwarded: offer.coins,
        totalCoins: user.lenDenCoins,
        offerId: offer._id,
        alreadyAccepted: false,
      };
    });

    if (!responsePayload) throw new Error('Failed to process offer claim');

    if (!responsePayload.alreadyAccepted) {
      const offer = await Offer.findById(req.params.offerId);
      await recordCoinLedgerEntry({
        userId: req.user._id,
        direction: 'earned',
        coins: responsePayload.coinsAwarded,
        source: 'offer_claim',
        title: 'Offer Reward Earned',
        description: `Earned ${responsePayload.coinsAwarded} LenDen coins by accepting "${offer?.name || 'Offer'}".`,
        metadata: {
          offerId: req.params.offerId,
          offerName: offer?.name || 'Offer',
        },
      });
      await createActivityLog(
        req.user._id,
        'offer_accepted',
        'Offer Accepted',
        `Accepted offer "${offer?.name || 'Offer'}" and earned ${responsePayload.coinsAwarded} LenDen coins`,
        {
          offerId: req.params.offerId,
          offerName: offer?.name || 'Offer',
          coinsAwarded: responsePayload.coinsAwarded,
          offerVersion: offer?.version || null,
        }
      );
    }

    return res.json(responsePayload);
  } catch (error) {
    const msg = error.message || 'Failed to accept offer';
    if (
      msg.includes('not assigned') ||
      msg.includes('not active') ||
      msg.includes('limit reached') ||
      msg.includes('not found')
    ) {
      return res.status(400).json({ error: msg });
    }
    return res.status(500).json({ error: msg });
  } finally {
    session.endSession();
  }
};

exports.getMyOfferClaims = async (req, res) => {
  try {
    await cleanupExpiredOffers();
    const { page = '1', limit = '50', includeRevoked = 'false' } = req.query;
    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);

    const query = { user: req.user._id };
    if (includeRevoked !== 'true') query.revoked = false;

    const [claims, total] = await Promise.all([
      OfferClaim.find(query)
        .populate('offer', 'name description coins startsAt endsAt status version')
        .sort({ claimedAt: -1 })
        .skip((parsedPage - 1) * parsedLimit)
        .limit(parsedLimit),
      OfferClaim.countDocuments(query),
    ]);

    return res.json({
      items: claims,
      pagination: {
        page: parsedPage,
        limit: parsedLimit,
        total,
        totalPages: Math.ceil(total / parsedLimit),
      },
    });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.searchUsersForOffers = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    const { search = '', limit = 20 } = req.query;
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 100);
    const trimmed = search.toString().trim();

    const query = trimmed
      ? {
          $or: [
            { email: { $regex: trimmed, $options: 'i' } },
            { username: { $regex: trimmed, $options: 'i' } },
            { name: { $regex: trimmed, $options: 'i' } },
          ],
        }
      : {};

    const users = await User.find(query, '_id name username email createdAt')
      .sort({ createdAt: -1 })
      .limit(parsedLimit);
    return res.json({ users });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.getOfferAnalytics = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    await cleanupExpiredOffers();
    const { offerId } = req.params;
    const offer = await Offer.findById(offerId).populate(
      'recipients',
      'name username email createdAt'
    );
    if (!offer) return res.status(404).json({ error: 'Offer not found' });

    const claims = await OfferClaim.find({ offer: offer._id, revoked: false }).populate(
      'user',
      'name username email'
    );
    const acceptedCount = claims.length;
    const distributedCoins = claims.reduce((sum, c) => sum + (c.coinsAwarded || 0), 0);

    let targetedCount = 0;
    if (offer.recipientType === 'all-users') {
      targetedCount = await User.countDocuments({});
    } else {
      targetedCount = offer.recipients.length;
    }
    const pendingCount = Math.max(0, targetedCount - acceptedCount);
    const acceptanceRate =
      targetedCount > 0 ? Number(((acceptedCount / targetedCount) * 100).toFixed(2)) : 0;

    return res.json({
      offer: {
        _id: offer._id,
        name: offer.name,
        status: offer.status,
        version: offer.version,
        coins: offer.coins,
        startsAt: offer.startsAt,
        endsAt: offer.endsAt,
        recipientType: offer.recipientType,
      },
      metrics: {
        targetedCount,
        acceptedCount,
        pendingCount,
        acceptanceRate,
        distributedCoins,
      },
      acceptedUsers: claims.map((c) => ({
        claimId: c._id,
        user: c.user,
        claimedAt: c.claimedAt,
        coinsAwarded: c.coinsAwarded,
        offerVersion: c.offerVersion,
      })),
    });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.getOfferClaimsAudit = async (req, res) => {
  try {
    const permitted = await ensureDigitisePermission(req, res);
    if (!permitted) return;
    await cleanupExpiredOffers();
    const { offerId } = req.params;
    const {
      search = '',
      from,
      to,
      page = '1',
      limit = '50',
      includeRevoked = 'true',
    } = req.query;

    const offer = await Offer.findById(offerId);
    if (!offer) return res.status(404).json({ error: 'Offer not found' });

    const query = { offer: offer._id };
    if (includeRevoked !== 'true') query.revoked = false;
    if (from || to) {
      query.claimedAt = {};
      if (from) query.claimedAt.$gte = new Date(from);
      if (to) query.claimedAt.$lte = new Date(to);
    }

    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 100);

    let claimsQuery = OfferClaim.find(query)
      .populate('user', 'name username email')
      .sort({ claimedAt: -1 })
      .skip((parsedPage - 1) * parsedLimit)
      .limit(parsedLimit);

    let claims = await claimsQuery;
    if (search.toString().trim()) {
      const searchLower = search.toString().trim().toLowerCase();
      claims = claims.filter((c) => {
        const user = c.user || {};
        return (
          (user.name || '').toString().toLowerCase().includes(searchLower) ||
          (user.username || '').toString().toLowerCase().includes(searchLower) ||
          (user.email || '').toString().toLowerCase().includes(searchLower)
        );
      });
    }

    const total = await OfferClaim.countDocuments(query);
    return res.json({
      offer: {
        _id: offer._id,
        name: offer.name,
        version: offer.version,
        status: offer.status,
      },
      items: claims,
      pagination: {
        page: parsedPage,
        limit: parsedLimit,
        total,
        totalPages: Math.ceil(total / parsedLimit),
      },
    });
  } catch (error) {
    return res.status(500).json({ error: 'Server error' });
  }
};

exports.__testables = {
  computeOfferStatus,
  normalizeStatus,
};
