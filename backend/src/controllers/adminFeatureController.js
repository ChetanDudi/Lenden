const SubscriptionPlan = require('../models/subscriptionPlan');
const PremiumBenefit = require('../models/premiumBenefit');
const Faq = require('../models/faq');
const Subscription = require('../models/subscription');
const User = require('../models/user');
const Admin = require('../models/admin');
const Notification = require('../models/notification');
const WalletTransaction = require('../models/walletTransaction');
const { ALL_FEATURE_KEYS } = require('../utils/subscriptionFeatures');

const sanitizeAllowedFeatures = (allowedFeatures) =>
    Array.isArray(allowedFeatures)
        ? allowedFeatures.filter((key) => ALL_FEATURE_KEYS.includes(key))
        : undefined;

const escapeRegex = (value = '') => value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

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
        res.status(403).json({ message: 'You do not have permission to manage digitise features' });
        return null;
    }
    return currentAdmin;
};

// Subscription Plan Controllers
exports.createSubscriptionPlan = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { name, price, duration, features, discount, free, allowedFeatures } = req.body;
        if (!(price > 0)) return res.status(400).json({ message: 'Price must be greater than 0' });
        if (!(duration > 0)) return res.status(400).json({ message: 'Duration must be greater than 0' });
        const newPlan = new SubscriptionPlan({
            name, price, duration, features, discount, free,
            allowedFeatures: sanitizeAllowedFeatures(allowedFeatures) || [],
        });
        await newPlan.save();
        res.status(201).json({ message: 'Subscription plan created successfully', plan: newPlan });
    } catch (error) {
        res.status(500).json({ message: 'Error creating subscription plan' });
    }
};

exports.getSubscriptionPlans = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const plans = await SubscriptionPlan.find();
        res.status(200).json(plans);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription plans' });
    }
};

exports.updateSubscriptionPlan = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const { name, price, duration, features, isAvailable, discount, free, allowedFeatures } = req.body;
        if (price !== undefined && !(price > 0)) return res.status(400).json({ message: 'Price must be greater than 0' });
        if (duration !== undefined && !(duration > 0)) return res.status(400).json({ message: 'Duration must be greater than 0' });
        const updateData = { name, price, duration, features, isAvailable, discount, free };
        const sanitizedAllowedFeatures = sanitizeAllowedFeatures(allowedFeatures);
        if (sanitizedAllowedFeatures !== undefined) updateData.allowedFeatures = sanitizedAllowedFeatures;
        const updatedPlan = await SubscriptionPlan.findByIdAndUpdate(id, updateData, { new: true });
        if (!updatedPlan) {
            return res.status(404).json({ message: 'Subscription plan not found' });
        }
        res.status(200).json({ message: 'Subscription plan updated successfully', plan: updatedPlan });
    } catch (error) {
        res.status(500).json({ message: 'Error updating subscription plan' });
    }
};

exports.deleteSubscriptionPlan = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const deletedPlan = await SubscriptionPlan.findByIdAndDelete(id);
        if (!deletedPlan) {
            return res.status(404).json({ message: 'Subscription plan not found' });
        }
        res.status(200).json({ message: 'Subscription plan deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Error deleting subscription plan' });
    }
};

// Premium Benefit Controllers
exports.createPremiumBenefit = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { text } = req.body;
        const newBenefit = new PremiumBenefit({ text });
        await newBenefit.save();
        res.status(201).json({ message: 'Premium benefit created successfully', benefit: newBenefit });
    } catch (error) {
        res.status(500).json({ message: 'Error creating premium benefit' });
    }
};

exports.getPremiumBenefits = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const benefits = await PremiumBenefit.find();
        res.status(200).json(benefits);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching premium benefits' });
    }
};

exports.updatePremiumBenefit = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const { text } = req.body;
        const updatedBenefit = await PremiumBenefit.findByIdAndUpdate(id, { text }, { new: true });
        if (!updatedBenefit) {
            return res.status(404).json({ message: 'Premium benefit not found' });
        }
        res.status(200).json({ message: 'Premium benefit updated successfully', benefit: updatedBenefit });
    } catch (error) {
        res.status(500).json({ message: 'Error updating premium benefit' });
    }
};

exports.deletePremiumBenefit = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const deletedBenefit = await PremiumBenefit.findByIdAndDelete(id);
        if (!deletedBenefit) {
            return res.status(404).json({ message: 'Premium benefit not found' });
        }
        res.status(200).json({ message: 'Premium benefit deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Error deleting premium benefit' });
    }
};

// FAQ Controllers
exports.createFaq = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { question, answer } = req.body;
        const newFaq = new Faq({ question, answer });
        await newFaq.save();
        res.status(201).json({ message: 'FAQ created successfully', faq: newFaq });
    } catch (error) {
        res.status(500).json({ message: 'Error creating FAQ' });
    }
};

exports.getFaqs = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const faqs = await Faq.find();
        res.status(200).json(faqs);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching FAQs' });
    }
};

exports.updateFaq = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const { question, answer } = req.body;
        const updatedFaq = await Faq.findByIdAndUpdate(id, { question, answer }, { new: true });
        if (!updatedFaq) {
            return res.status(404).json({ message: 'FAQ not found' });
        }
        res.status(200).json({ message: 'FAQ updated successfully', faq: updatedFaq });
    } catch (error) {
        res.status(500).json({ message: 'Error updating FAQ' });
    }
};

exports.deleteFaq = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const deletedFaq = await Faq.findByIdAndDelete(id);
        if (!deletedFaq) {
            return res.status(404).json({ message: 'FAQ not found' });
        }
        res.status(200).json({ message: 'FAQ deleted successfully' });
    } catch (error) {
        res.status(500).json({ message: 'Error deleting FAQ' });
    }
};

// Manage Subscriptions
exports.getAllSubscriptions = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { search } = req.query;
        let subscriptions;

        // Returns every subscription (active, expired, free, paid — any status), newest
        // first. The admin UI has its own All/Active/Expired filter and sort options
        // that work off endDate, so pre-filtering to status:'active' here only hid
        // expired and legacy records (some older documents predate the status field
        // and don't match an exact 'active' equality match) from that UI.
        if (search) {
            const safeSearch = escapeRegex(search.toString().trim());
            const users = await User.find({
                $or: [
                    { name: { $regex: safeSearch, $options: 'i' } },
                    { email: { $regex: safeSearch, $options: 'i' } },
                ],
            });

            if (users.length === 0) {
                return res.status(404).json({ message: 'User not found' });
            }

            const userIds = users.map(user => user._id);

            subscriptions = await Subscription.find({ user: { $in: userIds } })
                .sort({ createdAt: -1 })
                .populate('user', 'name email');

            if (subscriptions.length === 0) {
                return res.status(404).json({ message: 'No subscription found for this user' });
            }
        } else {
            subscriptions = await Subscription.find({}).sort({ createdAt: -1 }).populate('user', 'name email');
        }

        res.status(200).json(subscriptions);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscriptions' });
    }
};

exports.updateUserSubscription = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const { subscriptionPlan, duration, price, discount, free, endDate } = req.body;
        if (duration !== undefined && !(duration > 0)) return res.status(400).json({ message: 'Duration must be greater than 0' });
        if (price !== undefined && price < 0) return res.status(400).json({ message: 'Price cannot be negative' });
        const updatedSubscription = await Subscription.findByIdAndUpdate(id, { subscriptionPlan, duration, price, discount, free, endDate }, { new: true });
        if (!updatedSubscription) {
            return res.status(404).json({ message: 'Subscription not found' });
        }
        res.status(200).json({ message: 'Subscription updated successfully', subscription: updatedSubscription });
    } catch (error) {
        res.status(500).json({ message: 'Error updating subscription' });
    }
};

exports.deactivateUserSubscription = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const sub = await Subscription.findById(id);
        if (!sub) return res.status(404).json({ message: 'Subscription not found' });
        if (sub.adminDeactivated) return res.status(400).json({ message: 'Subscription is already deactivated' });
        const reason = (req.body.reason || '').toString().trim() || null;
        const now = new Date();
        const updatedSubscription = await Subscription.findByIdAndUpdate(
            id,
            {
                $set: { status: 'expired', adminDeactivated: true, deactivatedAt: now, deactivationReason: reason },
                $push: { adminEvents: { type: 'deactivated', at: now, reason } },
            },
            { new: true }
        );
        res.status(200).json({ message: 'Subscription deactivated successfully', subscription: updatedSubscription });
    } catch (error) {
        res.status(500).json({ message: 'Error deactivating subscription' });
    }
};

exports.reactivateUserSubscription = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { id } = req.params;
        const sub = await Subscription.findById(id);
        if (!sub) return res.status(404).json({ message: 'Subscription not found' });
        if (!sub.adminDeactivated) return res.status(400).json({ message: 'Subscription is not admin-deactivated' });

        const deactivatedAt = sub.deactivatedAt || new Date();
        const originalEndDate = sub.endDate || new Date();
        const remainingMs = Math.max(0, originalEndDate.getTime() - deactivatedAt.getTime());
        const newEndDate = new Date(Date.now() + remainingMs);

        // Keep deactivatedAt/deactivationReason for audit; only clear the active-pause flag
        const now = new Date();
        const updatedSubscription = await Subscription.findByIdAndUpdate(
            id,
            {
                $set: { status: 'active', adminDeactivated: false, reactivatedAt: now, endDate: newEndDate },
                $push: { adminEvents: { type: 'reactivated', at: now, reason: null } },
            },
            { new: true }
        );

        // Pause any active "bridge" subscriptions the user got while this plan was deactivated.
        // They will auto-resume once this reactivated plan expires.
        const bridgingSubs = await Subscription.find({
            user: sub.user,
            _id: { $ne: sub._id },
            status: 'active',
            adminDeactivated: { $ne: true },
        });
        for (const bridge of bridgingSubs) {
            const pauseNow = new Date();
            const remainingMs = Math.max(0, (bridge.endDate || pauseNow).getTime() - pauseNow.getTime());
            const pausedRemainingDays = Math.ceil(remainingMs / (1000 * 60 * 60 * 24));
            await Subscription.findByIdAndUpdate(bridge._id, {
                $set: { status: 'paused', pausedAt: pauseNow, pausedRemainingDays, pausedByBridging: true },
            });
        }

        res.status(200).json({ message: 'Subscription reactivated successfully', subscription: updatedSubscription });
    } catch (error) {
        res.status(500).json({ message: 'Error reactivating subscription' });
    }
};

// Grant a brand-new subscription to a user (support/compensation cases) — unlike
// updateUserSubscription, which only edits a subscription document that already
// exists, this creates one from scratch for a user who may have none at all.
exports.grantSubscription = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;
        const { userEmail, planId, subscriptionPlan, duration, price, discount, free } = req.body;
        if (!userEmail) return res.status(400).json({ message: 'User email is required' });

        const user = await User.findOne({ email: userEmail.toString().toLowerCase().trim() });
        if (!user) return res.status(404).json({ message: 'User not found' });

        let planName = subscriptionPlan;
        let planDuration = duration;
        let planPrice = price;
        let planDiscount = discount || 0;
        let planFree = free || 0;

        if (planId) {
            const plan = await SubscriptionPlan.findById(planId);
            if (!plan) return res.status(404).json({ message: 'Subscription plan not found' });
            planName = plan.name;
            planDuration = plan.duration;
            planPrice = plan.price;
            planDiscount = plan.discount || 0;
            planFree = plan.free || 0;
        }

        if (!planName) return res.status(400).json({ message: 'Subscription plan name is required' });
        if (!(planDuration > 0)) return res.status(400).json({ message: 'Duration must be greater than 0' });
        if (planPrice !== undefined && planPrice < 0) return res.status(400).json({ message: 'Price cannot be negative' });

        const actualPrice = (planPrice || 0) - ((planPrice || 0) * (planDiscount / 100));

        const now = new Date();
        const currentActive = await Subscription.findOne({ user: user._id, status: 'active' });
        const startFrom = (currentActive && currentActive.endDate > now) ? currentActive.endDate : now;
        const endDate = new Date(startFrom);
        endDate.setDate(endDate.getDate() + planDuration + planFree);

        const created = await Subscription.create({
            user: user._id,
            subscribed: true,
            subscriptionPlan: planName,
            duration: planDuration,
            price: planPrice || 0,
            discount: planDiscount,
            actualPrice,
            free: planFree,
            subscribedDate: now,
            endDate,
            status: 'active',
            paymentMethod: 'admin',
        });

        await Subscription.updateMany(
            { user: user._id, status: 'active', _id: { $ne: created._id } },
            { $set: { status: 'expired' } }
        );

        try {
            await Notification.create({
                sender: permitted._id,
                senderModel: 'Admin',
                recipientType: 'specific-users',
                recipients: [user._id],
                recipientModel: 'User',
                category: 'subscription',
                message: `An admin has granted you the "${planName}" subscription, active until ${endDate.toDateString()}.`,
            });
        } catch (notifyError) {
            console.error('Failed to notify user of granted subscription:', notifyError);
        }

        res.status(201).json({ message: 'Subscription granted successfully', subscription: created });
    } catch (error) {
        res.status(500).json({ message: 'Error granting subscription' });
    }
};

// Aggregate stats for the admin "Analytics" view.
exports.getSubscriptionAnalytics = async (req, res) => {
    try {
        const permitted = await ensureDigitisePermission(req, res);
        if (!permitted) return;

        const now = new Date();
        const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
        const sevenDaysFromNow = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

        const [
            totalSubscriptions,
            activeSubscribers,
            expiringNext7Days,
            newSubscriptionsLast30Days,
            revenueAgg,
            planBreakdown,
            paymentMethodBreakdown,
        ] = await Promise.all([
            Subscription.countDocuments({}),
            Subscription.countDocuments({ status: 'active', endDate: { $gte: now } }),
            Subscription.countDocuments({ status: 'active', endDate: { $gte: now, $lte: sevenDaysFromNow } }),
            Subscription.countDocuments({ subscribedDate: { $gte: thirtyDaysAgo } }),
            Subscription.aggregate([
                { $group: { _id: null, total: { $sum: '$actualPrice' } } },
            ]),
            Subscription.aggregate([
                { $group: { _id: '$subscriptionPlan', count: { $sum: 1 }, revenue: { $sum: '$actualPrice' } } },
                { $sort: { count: -1 } },
            ]),
            Subscription.aggregate([
                { $group: { _id: '$paymentMethod', count: { $sum: 1 } } },
                { $sort: { count: -1 } },
            ]),
        ]);

        res.status(200).json({
            totalSubscriptions,
            activeSubscribers,
            expiringNext7Days,
            newSubscriptionsLast30Days,
            totalRevenue: revenueAgg[0]?.total || 0,
            planBreakdown: planBreakdown.map((p) => ({
                plan: p._id || 'Unknown',
                count: p.count,
                revenue: p.revenue || 0,
            })),
            paymentMethodBreakdown: paymentMethodBreakdown.map((p) => ({
                method: p._id || 'razorpay',
                count: p.count,
            })),
        });
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription analytics' });
    }
};

// ── Admin: in-app wallet transactions (debit/credit between users) ─────────────
// Categories are identified via `sourceType` (set at creation time) with a
// note-regex fallback for records created before the field was added.
// Withdrawal records are excluded (they belong to the Real Payments page).

const CoinLedger = require('../models/coinLedger');
const QuickTransaction = require('../models/quickTransaction');

// CoinLedger source key for each special category (null = all sources = rewards tab)
const COIN_LEDGER_SOURCES = {
  rewards:     null,
  gift_cards:  'gift_card_scratch',
  offer_coins: 'offer_claim',
};

const _stOr = (sourceTypes, noteRegex, extra = {}) => ({
  $or: [
    { sourceType: { $in: sourceTypes } },
    { note: { $regex: noteRegex, $options: 'i' }, ...extra },
    ...(Object.keys(extra).length ? [extra] : []),
  ],
});

const IN_APP_CATEGORIES = {
  p2p:          _stOr(['p2p'],                              'wallet transfer'),
  quick:        _stOr(['quick'],                            'quick transaction'),
  secure:       _stOr(['secure'],                           'secure transaction'),
  group:        _stOr(['group'],                            'group expense'),
  qr: {
    $or: [
      { sourceType: { $in: ['qr_internal', 'qr_external'] } },
      { note: { $regex: 'qr payment', $options: 'i' } },
      { scanPaymentRequestId: { $exists: true, $ne: null } },
    ],
  },
  subscription: _stOr(['subscription'],                    'subscription'),
  coins:        _stOr(['coins'],                           'lenden coin'),
};

// Shared base filter builder — refunds use a different base to capture
// withdrawal-related refund credits that the normal base would exclude.
const _buildInAppBase = (category) => {
  if (category === 'refunds') {
    return { type: 'credit', note: { $regex: 'refund|reversed', $options: 'i' } };
  }
  return {
    type: { $in: ['debit', 'credit'] },
    withdrawalRequestId: null,
    note: { $not: /withdrawal/i },
  };
};

// Fills an array of {date, count, amount} for each of the past `daysInt` days.
const _fillDays = (since, daysInt, results) =>
  Array.from({ length: daysInt }, (_, i) => {
    const d = new Date(since);
    d.setDate(d.getDate() + i);
    const key = d.toISOString().slice(0, 10);
    const found = results.find(r => r._id === key);
    return { date: key, count: found?.count ?? 0, amount: found?.amount ?? 0 };
  });

exports.getAdminInAppTransactions = async (req, res) => {
  try {
    const { category = 'all', search, startDate, endDate, userId, flagged, minAmount, maxAmount, cleared, status } = req.query;
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const skip  = Math.max(0, parseInt(req.query.skip, 10) || 0);

    // ── CoinLedger tabs: Rewards, Gift Cards, Offer Coins ────────────────────
    if (Object.prototype.hasOwnProperty.call(COIN_LEDGER_SOURCES, category)) {
      const coinSource = COIN_LEDGER_SOURCES[category]; // null = all sources
      const andClauses = [];
      if (coinSource) andClauses.push({ source: coinSource });
      if (startDate || endDate) {
        const df = {};
        if (startDate) df.$gte = new Date(startDate);
        if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
        andClauses.push({ occurredAt: df });
      }
      if (userId) andClauses.push({ user: userId });
      if (search?.trim()) {
        const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        const matchingUsers = await User.find({ $or: [{ name: sr }, { email: sr }] }).select('_id').lean();
        andClauses.push({ $or: [{ user: { $in: matchingUsers.map(u => u._id) } }, { title: sr }, { description: sr }] });
      }
      if (minAmount || maxAmount) {
        const af = {};
        if (minAmount) af.$gte = parseFloat(minAmount);
        if (maxAmount) af.$lte = parseFloat(maxAmount);
        andClauses.push({ coins: af });
      }
      const rewardFilter = andClauses.length ? { $and: andClauses } : {};

      const [entries, total, agg] = await Promise.all([
        CoinLedger.find(rewardFilter).sort({ occurredAt: -1 }).skip(skip).limit(limit).populate('user', 'name email').lean(),
        CoinLedger.countDocuments(rewardFilter),
        CoinLedger.aggregate([{ $match: coinSource ? { source: coinSource } : {} }, { $group: { _id: '$direction', total: { $sum: '$coins' }, count: { $sum: 1 } } }]),
      ]);

      const globalStats = {};
      agg.forEach(a => { globalStats[a._id] = { total: a.total, count: a.count }; });
      const catAgg = await CoinLedger.aggregate([
        { $match: rewardFilter },
        { $group: { _id: null, total: { $sum: '$coins' }, count: { $sum: 1 } } },
      ]);

      return res.json({ transactions: entries, total, limit, skip, stats: globalStats, categoryStats: catAgg[0] ?? { total: 0, count: 0 }, isCoinLedger: true });
    }

    // ── Quick Transactions tab: query QuickTransaction model directly ─────────
    // WalletTransactions are only created for wallet-paid quick transactions;
    // manually settled / pending ones have no wallet record, so we query the
    // source model to give the admin a complete view of all quick transactions.
    if (category === 'quick') {
      const qtClauses = [];
      if (startDate || endDate) {
        const df = {};
        if (startDate) df.$gte = new Date(startDate);
        if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
        qtClauses.push({ createdAt: df });
      }
      if (userId) {
        const uDoc = await User.findById(userId).select('email').lean();
        if (uDoc) qtClauses.push({ users: uDoc.email });
      }
      if (search?.trim()) {
        const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        qtClauses.push({ $or: [{ users: sr }, { description: sr }, { category: sr }] });
      }
      if (cleared !== undefined) {
        qtClauses.push({ cleared: cleared === 'true' });
      }
      if (minAmount || maxAmount) {
        const af = {};
        if (minAmount) af.$gte = parseFloat(minAmount);
        if (maxAmount) af.$lte = parseFloat(maxAmount);
        qtClauses.push({ amount: af });
      }
      const qtFilter = qtClauses.length ? { $and: qtClauses } : {};

      const [entries, total, aggStats] = await Promise.all([
        QuickTransaction.find(qtFilter).sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
        QuickTransaction.countDocuments(qtFilter),
        QuickTransaction.aggregate([
          { $match: {} },
          { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 }, cleared: { $sum: { $cond: ['$cleared', 1, 0] } } } },
        ]),
      ]);

      // Resolve names for all participant emails in one query
      const allEmails = [...new Set(entries.flatMap(e => e.users || []))];
      const userDocs = allEmails.length
        ? await User.find({ email: { $in: allEmails } }).select('name email _id').lean()
        : [];
      const userByEmail = Object.fromEntries(userDocs.map(u => [u.email, u]));
      const populated = entries.map(e => ({
        ...e,
        usersPopulated: (e.users || []).map(em => userByEmail[em] || { email: em, name: em }),
      }));

      const catAgg = await QuickTransaction.aggregate([
        { $match: qtFilter },
        { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 }, cleared: { $sum: { $cond: ['$cleared', 1, 0] } } } },
      ]);

      return res.json({
        transactions: populated,
        total,
        limit,
        skip,
        stats: aggStats[0] ?? { total: 0, count: 0, cleared: 0 },
        categoryStats: catAgg[0] ?? { total: 0, count: 0, cleared: 0 },
        isQuickLedger: true,
      });
    }

    // Base: in-app transfers only
    const base = _buildInAppBase(category);

    // Accumulate $and clauses for additional filters
    const andClauses = [];
    if (category !== 'all' && category !== 'refunds' && IN_APP_CATEGORIES[category]) {
      andClauses.push(IN_APP_CATEGORIES[category]);
    }
    if (startDate || endDate) {
      const df = {};
      if (startDate) df.$gte = new Date(startDate);
      if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
      andClauses.push({ createdAt: df });
    }
    if (userId) andClauses.push({ user: userId });
    if (flagged === 'true') andClauses.push({ adminFlagged: true });
    if (minAmount || maxAmount) {
      const af = {};
      if (minAmount) af.$gte = parseFloat(minAmount);
      if (maxAmount) af.$lte = parseFloat(maxAmount);
      andClauses.push({ amount: af });
    }
    if (status && ['failed', 'reversed', 'processing', 'processed'].includes(status)) {
      andClauses.push({ status });
    }

    if (search?.trim()) {
      const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      const matchingUsers = await User.find({ $or: [{ name: sr }, { email: sr }] }).select('_id email').lean();
      const uIds = matchingUsers.map(u => u._id);
      const uEmails = matchingUsers.map(u => u.email);
      andClauses.push({ $or: [{ user: { $in: uIds } }, { fromEmail: { $in: uEmails } }, { toEmail: { $in: uEmails } }, { note: sr }] });
    }

    const filter = andClauses.length ? { $and: [base, ...andClauses] } : base;
    const globalBase = { type: { $in: ['debit', 'credit'] }, withdrawalRequestId: null, note: { $not: /withdrawal/i } };

    const [txns, total, aggGlobal, aggCategory] = await Promise.all([
      WalletTransaction.find(filter).sort({ createdAt: -1 }).skip(skip).limit(limit).populate('user', 'name email').lean(),
      WalletTransaction.countDocuments(filter),
      WalletTransaction.aggregate([{ $match: globalBase }, { $group: { _id: '$type', total: { $sum: '$amount' }, count: { $sum: 1 } } }]),
      WalletTransaction.aggregate([{ $match: filter }, { $group: { _id: null, total: { $sum: '$amount' }, count: { $sum: 1 } } }]),
    ]);

    const globalStats = {};
    aggGlobal.forEach(a => { globalStats[a._id] = { total: a.total, count: a.count }; });

    res.json({ transactions: txns, total, limit, skip, stats: globalStats, categoryStats: aggCategory[0] ?? { total: 0, count: 0 } });
  } catch (err) {
    console.error('[AdminInApp] Error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Per-category counts for tab badges
exports.getInAppTransactionCounts = async (req, res) => {
  try {
    const base = { type: { $in: ['debit', 'credit'] }, withdrawalRequestId: null, note: { $not: /withdrawal/i } };
    const refBase = { type: 'credit', note: { $regex: 'refund|reversed', $options: 'i' } };

    const [p2p, quick, secure, group, qr, subscription, coins, rewards, refunds, gift_cards, offer_coins] = await Promise.all([
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.p2p] }),
      QuickTransaction.countDocuments({}),
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.secure] }),
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.group] }),
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.qr] }),
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.subscription] }),
      WalletTransaction.countDocuments({ $and: [base, IN_APP_CATEGORIES.coins] }),
      CoinLedger.countDocuments({}),
      WalletTransaction.countDocuments(refBase),
      CoinLedger.countDocuments({ source: 'gift_card_scratch' }),
      CoinLedger.countDocuments({ source: 'offer_claim' }),
    ]);

    res.json({ all: p2p + secure + group + qr + subscription + coins, p2p, quick, secure, group, qr, subscription, coins, rewards, refunds, gift_cards, offer_coins });
  } catch (err) {
    console.error('[AdminInApp] Counts error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// 7-day (or N-day) transaction volume per day for the chart widget
exports.getInAppVolumeData = async (req, res) => {
  try {
    const { category = 'all' } = req.query;
    const daysInt = Math.min(90, Math.max(1, parseInt(req.query.days, 10) || 7));
    const since = new Date();
    since.setDate(since.getDate() - daysInt + 1);
    since.setHours(0, 0, 0, 0);

    // CoinLedger-backed categories
    if (Object.prototype.hasOwnProperty.call(COIN_LEDGER_SOURCES, category)) {
      const coinSource = COIN_LEDGER_SOURCES[category];
      const matchStage = { occurredAt: { $gte: since }, ...(coinSource ? { source: coinSource } : {}) };
      const results = await CoinLedger.aggregate([
        { $match: matchStage },
        { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$occurredAt' } }, count: { $sum: 1 }, amount: { $sum: '$coins' } } },
        { $sort: { _id: 1 } },
      ]);
      return res.json({ days: _fillDays(since, daysInt, results), coinLedger: true });
    }

    // QuickTransaction tab
    if (category === 'quick') {
      const results = await QuickTransaction.aggregate([
        { $match: { createdAt: { $gte: since } } },
        { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 }, amount: { $sum: '$amount' } } },
        { $sort: { _id: 1 } },
      ]);
      return res.json({ days: _fillDays(since, daysInt, results) });
    }

    const base = { ..._buildInAppBase(category), createdAt: { $gte: since } };
    const catFilter = category !== 'all' && category !== 'refunds' && IN_APP_CATEGORIES[category]
      ? { $and: [base, IN_APP_CATEGORIES[category]] }
      : base;

    const results = await WalletTransaction.aggregate([
      { $match: catFilter },
      { $group: { _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt' } }, count: { $sum: 1 }, amount: { $sum: '$amount' } } },
      { $sort: { _id: 1 } },
    ]);
    res.json({ days: _fillDays(since, daysInt, results) });
  } catch (err) {
    console.error('[AdminInApp] Volume error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// CSV export — mirrors getAdminInAppTransactions filter logic, no pagination
exports.exportInAppTransactions = async (req, res) => {
  try {
    const { category = 'all', search, startDate, endDate, flagged } = req.query;
    const esc = (v) => `"${String(v ?? '').replace(/"/g, '""')}"`;

    // CoinLedger categories (rewards, gift_cards, offer_coins)
    if (Object.prototype.hasOwnProperty.call(COIN_LEDGER_SOURCES, category)) {
      const coinSource = COIN_LEDGER_SOURCES[category];
      const andClauses = coinSource ? [{ source: coinSource }] : [];
      if (startDate || endDate) {
        const df = {};
        if (startDate) df.$gte = new Date(startDate);
        if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
        andClauses.push({ occurredAt: df });
      }
      if (search?.trim()) {
        const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        const us = await User.find({ $or: [{ name: sr }, { email: sr }] }).select('_id').lean();
        andClauses.push({ $or: [{ user: { $in: us.map(u => u._id) } }, { title: sr }, { description: sr }] });
      }
      const rewardFilter = andClauses.length ? { $and: andClauses } : {};
      const entries = await CoinLedger.find(rewardFilter).sort({ occurredAt: -1 }).limit(5000).populate('user', 'name email').lean();
      const headers = 'ID,Direction,Coins,Source,Title,User Name,User Email,Date';
      const rows = entries.map(e => [esc(e._id), esc(e.direction), esc(e.coins), esc(e.source), esc(e.title), esc(e.user?.name), esc(e.user?.email), esc(e.occurredAt)].join(','));
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      return res.send([headers, ...rows].join('\n'));
    }

    // QuickTransaction category
    if (category === 'quick') {
      const qtClauses = [];
      if (startDate || endDate) {
        const df = {};
        if (startDate) df.$gte = new Date(startDate);
        if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
        qtClauses.push({ createdAt: df });
      }
      if (search?.trim()) {
        const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
        qtClauses.push({ $or: [{ users: sr }, { description: sr }] });
      }
      const qtFilter = qtClauses.length ? { $and: qtClauses } : {};
      const entries = await QuickTransaction.find(qtFilter).sort({ createdAt: -1 }).limit(5000).lean();
      const headers = 'ID,Amount,Currency,Creator,Counterparty,Description,Role,Cleared,Settlement Status,Date';
      const rows = entries.map(e => {
        const creator = (e.users || [])[0] || e.creatorEmail || '';
        const counterparty = (e.users || []).find(u => u !== e.creatorEmail) || '';
        return [esc(e._id), esc(e.amount), esc(e.currency), esc(creator), esc(counterparty), esc(e.description), esc(e.role), esc(e.cleared ? 'Yes' : 'No'), esc(e.settlementStatus), esc(e.createdAt)].join(',');
      });
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      return res.send([headers, ...rows].join('\n'));
    }

    const base = _buildInAppBase(category);
    const andClauses = [];
    if (category !== 'all' && category !== 'refunds' && IN_APP_CATEGORIES[category]) andClauses.push(IN_APP_CATEGORIES[category]);
    if (startDate || endDate) {
      const df = {};
      if (startDate) df.$gte = new Date(startDate);
      if (endDate) { const to = new Date(endDate); to.setHours(23, 59, 59, 999); df.$lte = to; }
      andClauses.push({ createdAt: df });
    }
    if (flagged === 'true') andClauses.push({ adminFlagged: true });
    if (search?.trim()) {
      const sr = new RegExp(search.trim().replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      const us = await User.find({ $or: [{ name: sr }, { email: sr }] }).select('_id email').lean();
      andClauses.push({ $or: [{ user: { $in: us.map(u => u._id) } }, { fromEmail: { $in: us.map(u => u.email) } }, { toEmail: { $in: us.map(u => u.email) } }, { note: sr }] });
    }
    const filter = andClauses.length ? { $and: [base, ...andClauses] } : base;
    const txns = await WalletTransaction.find(filter).sort({ createdAt: -1 }).limit(5000).populate('user', 'name email').lean();

    const headers = 'ID,Type,Category,Amount,User Name,User Email,From,To,Note,Date,Flagged';
    const rows = txns.map(tx => [esc(tx._id), esc(tx.type), esc(tx.sourceType || category), esc(tx.amount), esc(tx.user?.name), esc(tx.user?.email), esc(tx.fromEmail), esc(tx.toEmail), esc(tx.note), esc(tx.createdAt), esc(tx.adminFlagged ? 'Yes' : 'No')].join(','));
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.send([headers, ...rows].join('\n'));
  } catch (err) {
    console.error('[AdminInApp] Export error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};

// Toggle adminFlagged on a wallet transaction
exports.flagInAppTransaction = async (req, res) => {
  try {
    const tx = await WalletTransaction.findById(req.params.id);
    if (!tx) return res.status(404).json({ error: 'Transaction not found' });
    tx.adminFlagged = !tx.adminFlagged;
    await tx.save();
    res.json({ _id: tx._id, adminFlagged: tx.adminFlagged });
  } catch (err) {
    console.error('[AdminInApp] Flag error:', err);
    res.status(500).json({ error: 'Server error' });
  }
};
