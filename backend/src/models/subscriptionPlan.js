const mongoose = require('mongoose');

const subscriptionPlanSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true,
        trim: true
    },
    price: {
        type: Number,
        required: true
    },
    duration: {
        type: Number, // Duration in days
        required: true
    },
    features: {
        type: [String],
        required: true
    },
    allowedFeatures: {
        type: [String],
        default: []
    },
    discount: {
        type: Number,
        default: 0
    },
    free: {
        type: Number, // Free days
        default: 0
    },
    isAvailable: {
        type: Boolean,
        default: true
    }
}, { timestamps: true });

module.exports = mongoose.model('SubscriptionPlan', subscriptionPlanSchema);
