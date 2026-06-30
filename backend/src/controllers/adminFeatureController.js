const SubscriptionPlan = require('../models/subscriptionPlan');
const PremiumBenefit = require('../models/premiumBenefit');
const Faq = require('../models/faq');
const Subscription = require('../models/subscription');
const User = require('../models/user');
const Admin = require('../models/admin');
const Notification = require('../models/notification');
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
        const updatedSubscription = await Subscription.findByIdAndUpdate(id, { status: 'expired' }, { new: true });
        if (!updatedSubscription) {
            return res.status(404).json({ message: 'Subscription not found' });
        }
        res.status(200).json({ message: 'Subscription deactivated successfully', subscription: updatedSubscription });
    } catch (error) {
        res.status(500).json({ message: 'Error deactivating subscription' });
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
