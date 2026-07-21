const mongoose = require('mongoose');

const subscriptionSchema = new mongoose.Schema({
    user: {
        type: mongoose.Schema.Types.ObjectId,
        ref: 'User',
        required: true
    },
    status: {
        type: String,
        enum: ['active', 'expired'],
        default: 'active'
    },
    subscribed: {
        type: Boolean,
        default: false
    },
    subscriptionPlan: {
        type: String,
        default: null
    },
    duration: {
        type: Number,
        default: 0
    },
    price: {
        type: Number,
        default: 0
    },
    discount: {
        type: Number,
        default: 0
    },
    actualPrice: {
        type: Number,
        default: 0
    },
    free: {
        type: Number,
        default: 0
    },
    endDate: {
        type: Date
    },
    subscribedDate: {
        type: Date
    },
    razorpayOrderId: {
        type: String,
        default: null
    },
    razorpayPaymentId: {
        type: String,
        default: null
    },
    paymentMethod: {
        type: String,
        enum: ['razorpay', 'razorpay_manual', 'wallet', 'admin'],
        default: 'razorpay'
    },
    autoRenew: {
        type: Boolean,
        default: false
    },
    adminDeactivated: {
        type: Boolean,
        default: false
    },
    deactivatedAt: {
        type: Date,
        default: null
    },
    deactivationReason: {
        type: String,
        default: null
    },
    reactivatedAt: {
        type: Date,
        default: null
    },
    adminEvents: [{
        type: { type: String, enum: ['deactivated', 'reactivated'] },
        at: { type: Date },
        reason: { type: String, default: null }
    }]
}, { timestamps: true });

// Partial unique index: only enforces uniqueness where razorpayPaymentId is an
// actual string, so the many documents with it left as null (wallet/admin
// grants) never collide with each other. This is the real defense against two
// requests racing to redeem the same Razorpay payment ID at once — an
// application-level "does a Subscription with this ID already exist?" check
// inside a transaction does NOT prevent that, because MongoDB's snapshot
// isolation lets two concurrent transactions both read "not found" before
// either commits. With this index, whichever insert loses the race fails with
// a duplicate-key error (code 11000), which the controllers below translate
// into the same 409 "already used" response as the explicit replay check.
subscriptionSchema.index(
    { razorpayPaymentId: 1 },
    { unique: true, partialFilterExpression: { razorpayPaymentId: { $type: 'string' } } }
);
// Subscription feature check: called on every gated request
subscriptionSchema.index({ user: 1, status: 1, endDate: 1 });
// Admin list filtered by status
subscriptionSchema.index({ status: 1, createdAt: -1 });

module.exports = mongoose.model('Subscription', subscriptionSchema);