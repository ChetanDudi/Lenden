const SubscriptionPlan = require('../models/subscriptionPlan');
const PremiumBenefit = require('../models/premiumBenefit');
const Faq = require('../models/faq');
const Subscription = require('../models/subscription');
const User = require('../models/user');
const Admin = require('../models/admin');

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
        const { name, price, duration, features, offer, discount, free } = req.body;
        const newPlan = new SubscriptionPlan({ name, price, duration, features, offer, discount, free });
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
        const { name, price, duration, features, isAvailable, offer, discount, free } = req.body;
        const updatedPlan = await SubscriptionPlan.findByIdAndUpdate(id, { name, price, duration, features, isAvailable, offer, discount, free }, { new: true });
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

            subscriptions = await Subscription.find({ user: { $in: userIds }, status: 'active' }).populate('user', 'name email');

            if (subscriptions.length === 0) {
                return res.status(404).json({ message: 'No active subscription found for this user' });
            }
        } else {
            subscriptions = await Subscription.find({ status: 'active' }).populate('user', 'name email');
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
