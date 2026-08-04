const Subscription = require('../models/subscription');
const SubscriptionPlan = require('../models/subscriptionPlan');

// Canonical feature keys an admin can grant per subscription plan. Keep this
// list in sync with the checkbox options shown in the admin Add/Edit Plan
// dialog (frontend/lib/admin/digitise/subscription_plans_tab.dart) and the
// labels shown on plan cards (frontend/lib/user/digitise/subscriptions_page.dart).
const FEATURES = {
  QUICK_TRANSACTIONS: 'quick_transactions',
  SECURE_TRANSACTIONS: 'secure_transactions',
  GROUP_CREATION: 'group_creation',
  GROUP_EXPENSES: 'group_expenses',
  PRIVATE_CHAT: 'private_chat',
  GROUP_CHAT: 'group_chat',
  DISCOVER: 'discover',
  VIEW_RANKINGS: 'view_rankings',
  REPORTS: 'reports',
  BUDGET_PLANNING: 'budget_planning',
  SMART_INSIGHTS: 'smart_insights',
};

const ALL_FEATURE_KEYS = Object.values(FEATURES);

// Returns the user's currently active Subscription document, or null.
async function getActiveSubscription(userId) {
  const subscription = await Subscription.findOne({ user: userId, status: 'active' });
  if (subscription && subscription.subscribed && subscription.endDate >= new Date()) {
    return subscription;
  }
  return null;
}

// Returns the Set of feature keys unlocked for this user right now.
// - Not subscribed -> empty set (free-tier daily limits apply everywhere).
// - Subscribed but the plan can't be resolved, or the plan predates this
//   field (allowedFeatures left empty by the admin) -> every feature, so
//   existing subscribers don't silently lose access on deploy.
// - Subscribed to a plan with allowedFeatures set -> exactly those.
async function getUnlockedFeatures(userId) {
  const subscription = await getActiveSubscription(userId);
  if (!subscription) return new Set();
  if (!subscription.subscriptionPlan) return new Set(ALL_FEATURE_KEYS);
  const plan = await SubscriptionPlan.findOne({ name: subscription.subscriptionPlan });
  if (!plan || !plan.allowedFeatures || plan.allowedFeatures.length === 0) {
    return new Set(ALL_FEATURE_KEYS);
  }
  return new Set(plan.allowedFeatures);
}

async function hasFeature(userId, featureKey) {
  const unlocked = await getUnlockedFeatures(userId);
  return unlocked.has(featureKey);
}

module.exports = {
  FEATURES,
  ALL_FEATURE_KEYS,
  getActiveSubscription,
  getUnlockedFeatures,
  hasFeature,
};
