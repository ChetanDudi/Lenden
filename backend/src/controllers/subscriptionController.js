const Subscription = require('../models/subscription');
const User = require('../models/user');
const mongoose = require('mongoose');
const SubscriptionPlan = require('../models/subscriptionPlan');
const PremiumBenefit = require('../models/premiumBenefit');
const Faq = require('../models/faq');

// Update or create a subscription
exports.updateSubscription = async (req, res) => {
    const { subscriptionPlan, duration, price, discount, free } = req.body; // duration in months
    const userId = req.user._id;

    try {
        // Expire all existing subscriptions for the user
        await Subscription.updateMany({ user: userId }, { $set: { status: 'expired' } });

        const subscribedDate = new Date();
        const endDate = new Date(subscribedDate);
        endDate.setDate(endDate.getDate() + duration + free);

        const actualPrice = price - (price * (discount / 100));

        // Create new subscription
        const subscription = new Subscription({
            user: userId,
            subscribed: true,
            subscriptionPlan,
            duration,
            price,
            discount,
            actualPrice,
            free,
            subscribedDate,
            endDate,
            status: 'active'
        });
        await subscription.save();

        res.status(200).json({ message: 'Subscription updated successfully', subscription });
    } catch (error) {
        res.status(500).json({ message: 'Error updating subscription', error: error.message });
    }
};

// Get subscription status for the logged-in user
exports.getSubscriptionStatus = async (req, res) => {
    try {
        const subscription = await Subscription.findOne({ user: req.user._id, status: 'active' }).sort({ subscribedDate: -1 });
        const now = new Date();

        if (subscription && subscription.subscribed && subscription.endDate >= now) {
            res.status(200).json({
                subscribed: true,
                subscriptionPlan: subscription.subscriptionPlan,
                subscribedDate: subscription.subscribedDate,
                endDate: subscription.endDate,
                free: subscription.free,
                actualPrice: subscription.actualPrice,
                paymentMethod: subscription.paymentMethod || 'razorpay',
            });
        } else {
            // Auto-expire stale active records so the DB reflects reality
            if (subscription && subscription.status === 'active') {
                Subscription.findByIdAndUpdate(subscription._id, { $set: { status: 'expired' } }).catch(() => {});
            }
            res.status(200).json({ subscribed: false });
        }
    } catch (error) {
        console.error('Error fetching subscription status:', error);
        res.status(500).json({ message: 'Error fetching subscription status', error: error.message });
    }
};

// Get subscription history for the logged-in user
exports.getSubscriptionHistory = async (req, res) => {
    try {
        const subscriptions = await Subscription.find({ user: req.user._id }).sort({ subscribedDate: -1 });
        res.status(200).json(subscriptions);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription history', error: error.message });
    }
};

// Get all active subscription plans
exports.getSubscriptionPlans = async (req, res) => {
    try {
        const plans = await SubscriptionPlan.find({ isAvailable: true });
        res.status(200).json(plans);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching subscription plans', error: error.message });
    }
};

// Get all premium benefits
exports.getPremiumBenefits = async (req, res) => {
    try {
        const benefits = await PremiumBenefit.find();
        res.status(200).json(benefits);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching premium benefits', error: error.message });
    }
};

// Get all FAQs
exports.getFaqs = async (req, res) => {
    try {
        const faqs = await Faq.find();
        res.status(200).json(faqs);
    } catch (error) {
        res.status(500).json({ message: 'Error fetching FAQs', error: error.message });
    }
};
