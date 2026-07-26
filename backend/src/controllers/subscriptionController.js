const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');
const PremiumBenefit = require('../models/premiumBenefit');
const Faq = require('../models/faq');

// Get subscription status for the logged-in user
exports.getSubscriptionStatus = async (req, res) => {
    try {
        const subscription = await Subscription.findOne({ user: req.user._id, status: 'active' }).sort({ subscribedDate: -1 });
        const now = new Date();

        if (subscription && subscription.subscribed && subscription.endDate >= now) {
            // Resolve the plan's allowedFeatures so the client can gate per-feature.
            // null means "all features" (legacy plans with no allowedFeatures set).
            let allowedFeatures = null;
            if (subscription.subscriptionPlan) {
                const plan = await SubscriptionPlan.findOne({ name: subscription.subscriptionPlan }).lean();
                if (plan && Array.isArray(plan.allowedFeatures) && plan.allowedFeatures.length > 0) {
                    allowedFeatures = plan.allowedFeatures;
                }
            }
            res.status(200).json({
                subscribed: true,
                subscriptionPlan: subscription.subscriptionPlan,
                subscribedDate: subscription.subscribedDate,
                endDate: subscription.endDate,
                free: subscription.free,
                actualPrice: subscription.actualPrice,
                paymentMethod: subscription.paymentMethod || 'razorpay',
                autoRenew: subscription.autoRenew || false,
                allowedFeatures, // null = all features; array = plan-specific feature keys
            });
        } else {
            // Auto-expire stale active records so the DB reflects reality
            if (subscription && subscription.status === 'active') {
                Subscription.findByIdAndUpdate(subscription._id, { $set: { status: 'expired' } }).catch(() => {});
            }

            // Auto-resume a paused bridging subscription (queued behind the now-expired reactivated plan)
            const pausedBridging = await Subscription.findOne({
                user: req.user._id,
                status: 'paused',
                pausedByBridging: true,
            }).sort({ pausedAt: 1 }); // oldest paused first (FIFO)

            if (pausedBridging && pausedBridging.pausedRemainingDays > 0) {
                const newEndDate = new Date(Date.now() + pausedBridging.pausedRemainingDays * 24 * 60 * 60 * 1000);
                const resumedSub = await Subscription.findByIdAndUpdate(
                    pausedBridging._id,
                    { $set: { status: 'active', pausedByBridging: false, pausedAt: null, endDate: newEndDate } },
                    { new: true }
                );
                let allowedFeatures = null;
                if (resumedSub.subscriptionPlan) {
                    const plan = await SubscriptionPlan.findOne({ name: resumedSub.subscriptionPlan }).lean();
                    if (plan && Array.isArray(plan.allowedFeatures) && plan.allowedFeatures.length > 0) {
                        allowedFeatures = plan.allowedFeatures;
                    }
                }
                return res.status(200).json({
                    subscribed: true,
                    subscriptionPlan: resumedSub.subscriptionPlan,
                    subscribedDate: resumedSub.subscribedDate,
                    endDate: resumedSub.endDate,
                    free: resumedSub.free,
                    actualPrice: resumedSub.actualPrice,
                    paymentMethod: resumedSub.paymentMethod || 'razorpay',
                    autoRenew: resumedSub.autoRenew || false,
                    allowedFeatures,
                });
            }

            // Check if the user has an admin-deactivated subscription with remaining days
            const deactivated = await Subscription.findOne({
                user: req.user._id,
                adminDeactivated: true,
            }).sort({ deactivatedAt: -1 });
            if (deactivated && deactivated.endDate && deactivated.deactivatedAt) {
                const remainingMs = Math.max(0, deactivated.endDate.getTime() - deactivated.deactivatedAt.getTime());
                const remainingDays = Math.ceil(remainingMs / (1000 * 60 * 60 * 24));
                return res.status(200).json({
                    subscribed: false,
                    adminDeactivated: true,
                    deactivationReason: deactivated.deactivationReason || null,
                    remainingDays,
                    subscriptionPlan: deactivated.subscriptionPlan,
                });
            }
            res.status(200).json({ subscribed: false });
        }
    } catch (error) {
        console.error('Error fetching subscription status:', error);
        res.status(500).json({ message: 'Error fetching subscription status' });
    }
};

// Get subscription history for the logged-in user
exports.getSubscriptionHistory = async (req, res) => {
    try {
        const subscriptions = await Subscription.find({ user: req.user._id }).sort({ subscribedDate: -1 });
        res.status(200).json(subscriptions);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription history' });
    }
};

// Get all active subscription plans
exports.getSubscriptionPlans = async (req, res) => {
    try {
        const plans = await SubscriptionPlan.find({ isAvailable: true });
        res.status(200).json(plans);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription plans' });
    }
};

// Get all premium benefits
exports.getPremiumBenefits = async (req, res) => {
    try {
        const benefits = await PremiumBenefit.find();
        res.status(200).json(benefits);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching premium benefits' });
    }
};

// Get all FAQs
exports.getFaqs = async (req, res) => {
    try {
        const faqs = await Faq.find();
        res.status(200).json(faqs);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching FAQs' });
    }
};

// Toggle auto-renew on the logged-in user's current active subscription
exports.setAutoRenew = async (req, res) => {
    try {
        const { enabled } = req.body;
        const subscription = await Subscription.findOne({ user: req.user._id, status: 'active' }).sort({ subscribedDate: -1 });
        const now = new Date();
        if (!subscription || !subscription.subscribed || subscription.endDate < now) {
            return res.status(404).json({ message: 'No active subscription found' });
        }
        subscription.autoRenew = !!enabled;
        await subscription.save();
        res.status(200).json({ message: 'Auto-renew preference updated', autoRenew: subscription.autoRenew });
    } catch (error) {
        res.status(500).json({ message: 'Error updating auto-renew preference' });
    }
};
