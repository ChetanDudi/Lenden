import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class SubscriptionAnalyticsTab extends StatefulWidget {
  @override
  _SubscriptionAnalyticsTabState createState() => _SubscriptionAnalyticsTabState();
}

class _SubscriptionAnalyticsTabState extends State<SubscriptionAnalyticsTab> {
  Map<String, dynamic>? _analytics;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  Future<void> _fetchAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/admin/subscriptions/analytics');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() {
          _analytics = json.decode(response.body) as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body = response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() {
          _error = (body?['message'] ?? t('failed_to_load_analytics')).toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() {
        _error = '${t('error_prefix')} $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.divider(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppThemeColors.isDark(context) ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11.5, color: AppThemeColors.secondaryText(context))),
        ],
      ),
    );
  }

  Widget _buildBreakdownSection({
    required String title,
    required IconData icon,
    required List<dynamic> items,
    required String Function(dynamic item) labelOf,
    required int Function(dynamic item) countOf,
    String? Function(dynamic item)? subLabelOf,
  }) {
    final t = AppLocalizations.of(context).t;
    if (items.isEmpty) return const SizedBox.shrink();
    final maxCount = items.fold<int>(0, (max, item) => countOf(item) > max ? countOf(item) : max);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.divider(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: AppThemeColors.isDark(context) ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.cyan, size: 18),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
          ]),
          const SizedBox(height: 16),
          ...items.map((item) {
            final count = countOf(item);
            final fraction = maxCount > 0 ? count / maxCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(labelOf(item),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppThemeColors.primaryText(context))),
                      ),
                      Text(
                        subLabelOf != null && subLabelOf(item) != null
                            ? '$count  •  ${subLabelOf(item)}'
                            : '$count ${t('subscriptions_count_label')}',
                        style: TextStyle(
                            fontSize: 11.5, color: AppThemeColors.secondaryText(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppThemeColors.surfaceBg(context),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 46, color: Colors.red[300]),
                      const SizedBox(height: 12),
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _fetchAnalytics,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(t('retry')),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchAnalytics,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildStatCard(
                                Icons.people_alt_rounded,
                                '${_analytics?['activeSubscribers'] ?? 0}',
                                t('active_subscribers_label'),
                                Colors.green),
                            _buildStatCard(
                                Icons.subscriptions_rounded,
                                '${_analytics?['totalSubscriptions'] ?? 0}',
                                t('total_subscriptions_label'),
                                AppColors.cyan),
                            _buildStatCard(
                                Icons.payments_rounded,
                                '₹${(_analytics?['totalRevenue'] ?? 0).toStringAsFixed(0)}',
                                t('total_revenue_label'),
                                Colors.deepPurple),
                            _buildStatCard(
                                Icons.trending_up_rounded,
                                '${_analytics?['newSubscriptionsLast30Days'] ?? 0}',
                                t('new_last_30_days_label'),
                                Colors.orange),
                            _buildStatCard(
                                Icons.hourglass_bottom_rounded,
                                '${_analytics?['expiringNext7Days'] ?? 0}',
                                t('expiring_next_7_days_label'),
                                Colors.redAccent),
                          ],
                        ),
                        _buildBreakdownSection(
                          title: t('plan_popularity_label'),
                          icon: Icons.card_membership_rounded,
                          items: (_analytics?['planBreakdown'] as List?) ?? const [],
                          labelOf: (item) => (item['plan'] ?? '').toString(),
                          countOf: (item) => ((item['count'] ?? 0) as num).toInt(),
                          subLabelOf: (item) => '₹${((item['revenue'] ?? 0) as num).toStringAsFixed(0)}',
                        ),
                        _buildBreakdownSection(
                          title: t('payment_method_breakdown_label'),
                          icon: Icons.account_balance_wallet_rounded,
                          items: (_analytics?['paymentMethodBreakdown'] as List?) ?? const [],
                          labelOf: (item) => (item['method'] ?? '').toString(),
                          countOf: (item) => ((item['count'] ?? 0) as num).toInt(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
    );
  }
}
