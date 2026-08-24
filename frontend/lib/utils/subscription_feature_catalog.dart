import 'package:flutter/material.dart';

/// Canonical list of premium features an admin can grant per subscription
/// plan. Keys must stay in sync with `backend/src/utils/subscriptionFeatures.js`.
class SubscriptionFeature {
  final String key;
  final String labelKey;
  final IconData icon;

  const SubscriptionFeature(this.key, this.labelKey, this.icon);
}

const List<SubscriptionFeature> kSubscriptionFeatures = [
  SubscriptionFeature('quick_transactions', 'feature_quick_transactions_label', Icons.flash_on),
  SubscriptionFeature('secure_transactions', 'feature_secure_transactions_label', Icons.verified_user),
  SubscriptionFeature('group_creation', 'feature_group_creation_label', Icons.groups),
  SubscriptionFeature('group_expenses', 'feature_group_expenses_label', Icons.receipt_long),
  SubscriptionFeature('private_chat', 'feature_private_chat_label', Icons.chat),
  SubscriptionFeature('group_chat', 'feature_group_chat_label', Icons.forum),
  SubscriptionFeature('discover', 'feature_discover_label', Icons.person_search),
  SubscriptionFeature('view_rankings', 'feature_view_rankings_label', Icons.leaderboard),
  SubscriptionFeature('reports', 'feature_reports_label', Icons.bar_chart),
  SubscriptionFeature('budget_planning', 'feature_budget_planning_label', Icons.pie_chart),
  SubscriptionFeature('smart_insights', 'feature_smart_insights_label', Icons.auto_awesome),
  SubscriptionFeature('community_feed', 'feature_community_feed_label', Icons.forum_rounded),
];

List<String> get kAllSubscriptionFeatureKeys =>
    kSubscriptionFeatures.map((f) => f.key).toList(growable: false);
