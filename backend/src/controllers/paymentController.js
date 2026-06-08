const crypto = require('crypto');
const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');

const getRazorpay = () => {
  const Razorpay = require('razorpay');
  if (!process.env.RAZORPAY_KEY_ID || !process.env.RAZORPAY_KEY_SECRET) {
    throw new Error('Razorpay keys not configured. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in .env');
  }
  return new Razorpay({
    key_id: process.env.RAZORPAY_KEY_ID,
    key_secret: process.env.RAZORPAY_KEY_SECRET,
  });
};

// Create a Razorpay order for a subscription plan
exports.createOrder = async (req, res) => {
  const { planId } = req.body;

  if (!planId) return res.status(400).json({ error: 'planId is required' });

  try {
    const plan = await SubscriptionPlan.findById(planId);
    if (!plan || !plan.isAvailable) {
      return res.status(404).json({ error: 'Plan not found or unavailable' });
    }

    const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
    const amountInPaise = Math.round(actualPrice * 100);

    if (amountInPaise < 100) {
      return res.status(400).json({ error: 'Minimum payment amount is ₹1' });
    }

    const razorpay = getRazorpay();
    const order = await razorpay.orders.create({
      amount: amountInPaise,
      currency: 'INR',
      receipt: `lenden_${Date.now()}`,
      notes: {
        planId: plan._id.toString(),
        userId: req.user._id.toString(),
        planName: plan.name,
      },
    });

    res.json({
      orderId: order.id,
      amount: order.amount,
      currency: order.currency,
      keyId: process.env.RAZORPAY_KEY_ID,
      plan: {
        id: plan._id.toString(),
        name: plan.name,
        duration: plan.duration,
        free: plan.free || 0,
        price: plan.price,
        discount: plan.discount || 0,
        actualPrice,
      },
    });
  } catch (error) {
    console.error('Error creating Razorpay order:', error);
    res.status(500).json({ error: 'Failed to create payment order', details: error.message });
  }
};

// Verify Razorpay payment signature and activate subscription
exports.verifyPayment = async (req, res) => {
  const { razorpayOrderId, razorpayPaymentId, razorpaySignature, planId } = req.body;
  const userId = req.user._id;

  if (!razorpayOrderId || !razorpayPaymentId || !razorpaySignature || !planId) {
    return res.status(400).json({ error: 'Missing required payment verification fields' });
  }

  if (!process.env.RAZORPAY_KEY_SECRET) {
    return res.status(500).json({ error: 'Payment verification not configured' });
  }

  // Verify HMAC-SHA256 signature
  const body = `${razorpayOrderId}|${razorpayPaymentId}`;
  const expectedSignature = crypto
    .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
    .update(body)
    .digest('hex');

  if (expectedSignature !== razorpaySignature) {
    return res.status(400).json({ error: 'Payment verification failed: signature mismatch' });
  }

  try {
    const plan = await SubscriptionPlan.findById(planId);
    if (!plan) return res.status(404).json({ error: 'Plan not found' });

    // Prevent replay: reject if this payment ID was already used
    const alreadyUsed = await Subscription.findOne({ razorpayPaymentId });
    if (alreadyUsed) {
      return res.status(409).json({ error: 'This payment has already been applied to a subscription' });
    }

    // Expire all current active subscriptions
    await Subscription.updateMany({ user: userId, status: 'active' }, { $set: { status: 'expired' } });

    const subscribedDate = new Date();
    const endDate = new Date(subscribedDate);
    endDate.setDate(endDate.getDate() + plan.duration + (plan.free || 0));

    const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));

    const subscription = new Subscription({
      user: userId,
      subscribed: true,
      subscriptionPlan: plan.name,
      duration: plan.duration,
      price: plan.price,
      discount: plan.discount || 0,
      actualPrice,
      free: plan.free || 0,
      subscribedDate,
      endDate,
      status: 'active',
      razorpayOrderId,
      razorpayPaymentId,
    });
    await subscription.save();

    res.json({
      message: 'Payment verified and subscription activated',
      subscription: {
        subscriptionPlan: subscription.subscriptionPlan,
        subscribedDate: subscription.subscribedDate,
        endDate: subscription.endDate,
        duration: subscription.duration,
        free: subscription.free,
      },
    });
  } catch (error) {
    console.error('Error verifying payment:', error);
    res.status(500).json({ error: 'Failed to activate subscription', details: error.message });
  }
};

// Razorpay webhook endpoint — for server-side reliability (payment captured, failed, etc.)
exports.razorpayWebhook = async (req, res) => {
  // req.body is a raw Buffer here (express.raw middleware is applied in app.js before express.json)
  const rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.from(JSON.stringify(req.body));
  const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET;

  if (webhookSecret) {
    const signature = req.headers['x-razorpay-signature'];
    if (!signature) {
      return res.status(400).json({ error: 'Missing x-razorpay-signature header' });
    }
    const expectedSignature = crypto
      .createHmac('sha256', webhookSecret)
      .update(rawBody)
      .digest('hex');

    if (signature !== expectedSignature) {
      return res.status(400).json({ error: 'Invalid webhook signature' });
    }
  }

  let event;
  try {
    event = JSON.parse(rawBody.toString('utf8'));
  } catch (_) {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  // Handle payment.captured — fallback if app-side verify call was lost
  if (event.event === 'payment.captured') {
    const payment = event.payload?.payment?.entity;
    if (payment) {
      const { order_id, id: paymentId } = payment;
      const notes = payment.notes || {};
      const { planId, userId } = notes;

      if (planId && userId && !(await Subscription.findOne({ razorpayPaymentId: paymentId }))) {
        try {
          const plan = await SubscriptionPlan.findById(planId);
          if (plan) {
            await Subscription.updateMany({ user: userId, status: 'active' }, { $set: { status: 'expired' } });
            const subscribedDate = new Date();
            const endDate = new Date(subscribedDate);
            endDate.setDate(endDate.getDate() + plan.duration + (plan.free || 0));
            const actualPrice = plan.price - (plan.price * ((plan.discount || 0) / 100));
            await new Subscription({
              user: userId,
              subscribed: true,
              subscriptionPlan: plan.name,
              duration: plan.duration,
              price: plan.price,
              discount: plan.discount || 0,
              actualPrice,
              free: plan.free || 0,
              subscribedDate,
              endDate,
              status: 'active',
              razorpayOrderId: order_id,
              razorpayPaymentId: paymentId,
            }).save();
          }
        } catch (e) {
          console.error('[Webhook] Failed to activate subscription via webhook:', e);
        }
      }
    }
  }

  res.json({ status: 'ok' });
};
