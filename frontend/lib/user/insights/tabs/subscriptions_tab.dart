import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class SubscriptionsTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const SubscriptionsTab({super.key, required this.insights, required this.ca});

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Subscription Tracker',
        description: 'AI detects recurring payments and shows your total subscription spend.',
        icon: Icons.subscriptions_outlined,
        accentColor: Colors.purple,
      );
    }

    final subs     = (insights?['subscriptions']        as List? ?? []).cast<Map<String, dynamic>>();
    final detected = (insights?['detectedRecurring']    as List? ?? []).cast<Map<String, dynamic>>();
    final totalSub = subs.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSummaryBanner(context, totalSub, subs.length),
        const SizedBox(height: 16),
        _buildKnownSubscriptions(context, subs),
        const SizedBox(height: 16),
        _buildDetectedRecurring(context, detected),
        const SizedBox(height: 16),
        _buildInsightTip(context, totalSub),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildSummaryBanner(BuildContext context, double total, int count) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.withValues(alpha: 0.12), Colors.deepPurple.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.subscriptions_outlined, color: Colors.purple, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monthly Subscription Spend',
              style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 2),
          Text(ca(total),
              style: TextStyle(fontSize: context.sp(24), fontWeight: FontWeight.bold, color: Colors.purple)),
          Text('$count tracked subscription${count == 1 ? '' : 's'}',
              style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(ca(total * 12),
              style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          Text('per year', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    );
  }

  Widget _buildKnownSubscriptions(BuildContext context, List<Map<String, dynamic>> subs) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tracked Subscriptions',
          style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      if (subs.isEmpty)
        _buildEmptyCard(context, 'No tracked subscriptions yet',
            'Subscriptions you track via the Budget tab will appear here.')
      else
        for (final s in subs) ...[
          _buildSubCard(context, s, isPrimary: true),
          const SizedBox(height: 8),
        ],
    ]);
  }

  Widget _buildDetectedRecurring(BuildContext context, List<Map<String, dynamic>> detected) {
    if (detected.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('AI Detected Recurring',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text('Auto', style: TextStyle(fontSize: context.sp(9), color: Colors.orange, fontWeight: FontWeight.bold)),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Payments that appear regularly in your transaction history',
          style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 10),
      for (final d in detected) ...[
        _buildSubCard(context, d, isPrimary: false),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _buildSubCard(BuildContext context, Map<String, dynamic> s, {required bool isPrimary}) {
    final name       = s['name']        as String? ?? '';
    final amount     = (s['amount']     as num?)?.toDouble() ?? 0;
    final cycle      = s['cycle']       as String? ?? 'monthly';
    final category   = s['category']   as String? ?? '';
    final confidence = (s['confidence'] as num?)?.toDouble();
    final lastSeen   = s['lastSeen']    as String? ?? '';

    final monthlyAmt = cycle == 'yearly'   ? amount / 12
                     : cycle == 'quarterly' ? amount / 3
                     : cycle == 'weekly'    ? amount * 4.33
                     : amount;

    Color cycleColor() {
      switch (cycle) {
        case 'weekly':    return Colors.red;
        case 'monthly':   return Colors.purple;
        case 'quarterly': return Colors.orange;
        case 'yearly':    return Colors.teal;
        default:          return AppColors.cyan;
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPrimary
            ? Colors.purple.withValues(alpha: 0.2)
            : Colors.orange.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: cycleColor().withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(isPrimary ? Icons.subscriptions_outlined : Icons.autorenew_rounded,
                size: 17, color: cycleColor()),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
            if (category.isNotEmpty)
              Text(category, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(ca(amount), style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: cycleColor())),
            Text('/ $cycle', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _chip(context, '~${ca(monthlyAmt)}/mo', Colors.purple),
          const SizedBox(width: 6),
          _chip(context, '~${ca(monthlyAmt * 12)}/yr', Colors.deepPurple),
          if (confidence != null) ...[
            const SizedBox(width: 6),
            _chip(context, '${confidence.toStringAsFixed(0)}% confidence', Colors.orange),
          ],
          if (lastSeen.isNotEmpty) ...[
            const Spacer(),
            Text('Last: $lastSeen',
                style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
          ],
        ]),
      ]),
    );
  }

  Widget _chip(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
    child: Text(text, style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.w500)),
  );

  Widget _buildInsightTip(BuildContext context, double total) {
    final yearTotal = total * 12;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 15, color: Colors.amber),
          const SizedBox(width: 6),
          Text('Subscription Insight', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
        ]),
        const SizedBox(height: 8),
        Text(
          yearTotal > 0
              ? 'You spend approximately ${ca(yearTotal)} per year on subscriptions. '
                'Review unused services quarterly — the average person wastes ₹3,000–₹8,000/year on forgotten subscriptions.'
              : 'Add your subscriptions and recurring payments to track annual costs and find savings opportunities.',
          style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context), height: 1.5),
        ),
      ]),
    );
  }

  Widget _buildEmptyCard(BuildContext context, String title, String subtitle) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppThemeColors.border(context)),
    ),
    child: Column(children: [
      const Text('📱', style: TextStyle(fontSize: 32)),
      const SizedBox(height: 8),
      Text(title, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
          color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text(subtitle, textAlign: TextAlign.center,
          style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
    ]),
  );
}
