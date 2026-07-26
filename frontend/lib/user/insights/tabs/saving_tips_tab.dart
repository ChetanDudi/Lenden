import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';

class SavingTipsTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const SavingTipsTab({super.key, required this.insights, required this.ca});

  static const _categoryTipIcons = {
    'food': Icons.restaurant_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'entertainment': Icons.movie_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'travel': Icons.flight_outlined,
    'medical': Icons.medical_services_outlined,
    'education': Icons.school_outlined,
    'other': Icons.category_outlined,
    'general': Icons.lightbulb_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final tips     = (insights?['savingTips'] as List? ?? []).cast<Map<String, dynamic>>();
    final freeTips = tips.where((t) => !(t['premium'] as bool? ?? false)).toList();
    final premTips = tips.where((t) => t['premium'] as bool? ?? false).toList();

    final session = Provider.of<SessionProvider>(context, listen: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildIntroCard(context),
        const SizedBox(height: 16),
        if (freeTips.isNotEmpty) ...[
          Text('Your Personalised Tips',
              style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 10),
          for (final t in freeTips) ...[
            _buildTipCard(context, t, premium: false),
            const SizedBox(height: 10),
          ],
        ],
        if (premTips.isNotEmpty) ...[
          const SizedBox(height: 6),
          if (!session.hasFeature('smart_insights'))
            _buildPremiumTipsTeaser(context, premTips.length)
          else ...[
            Text('Advanced Tips',
                style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 10),
            for (final t in premTips) ...[
              _buildTipCard(context, t, premium: true),
              const SizedBox(height: 10),
            ],
          ],
        ],
        if (tips.isEmpty) _buildEmptyState(context),
        const SizedBox(height: 16),
        _buildFinancialPrinciples(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cyan.withValues(alpha: 0.12), Colors.teal.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.lightbulb_rounded, color: AppColors.cyan, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI-Powered Saving Tips', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 2),
          Text('Tailored to your actual spending habits', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ])),
      ]),
    );
  }

  Widget _buildTipCard(BuildContext context, Map<String, dynamic> tip, {required bool premium}) {
    final title    = tip['title']    as String? ?? '';
    final body     = tip['body']     as String? ?? '';
    final category = tip['category'] as String? ?? 'general';
    final saving   = (tip['potentialSaving'] as num?)?.toDouble();
    final impact   = tip['impact']   as String? ?? 'medium';
    final icon     = _categoryTipIcons[category] ?? Icons.lightbulb_outline_rounded;

    Color impactColor() {
      switch (impact) {
        case 'high':   return Colors.teal;
        case 'medium': return Colors.orange;
        default:       return AppThemeColors.border(context);
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: premium ? Colors.amber.withValues(alpha: 0.3) : AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: AppColors.cyan),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
          if (premium) const _PremiumBadge(),
        ]),
        const SizedBox(height: 8),
        Text(body, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context), height: 1.5)),
        if (saving != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.savings_outlined, size: 12, color: Colors.teal),
              const SizedBox(width: 4),
              Text('Save up to ${ca(saving)}/month', style: TextStyle(fontSize: context.sp(11), color: Colors.teal, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: impactColor().withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text('${impact[0].toUpperCase()}${impact.substring(1)} impact',
                style: TextStyle(fontSize: context.sp(9), color: impactColor(), fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }

  Widget _buildPremiumTipsTeaser(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline_rounded, color: Colors.amber, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$count more premium tips available', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          Text('Upgrade to Premium to unlock advanced saving strategies', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ])),
      ]),
    );
  }

  Widget _buildEmptyState(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 32),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppThemeColors.border(context)),
    ),
    child: Column(children: [
      const Text('💡', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 10),
      Text('No tips yet', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Refresh insights to generate personalised tips', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
    ]),
  );
}

  Widget _buildFinancialPrinciples(BuildContext context) {
    const principles = [
      (Icons.savings_outlined,        Colors.teal,        '50/30/20 Rule',
        'Allocate 50% to needs, 30% to wants, and 20% to savings & debt. A simple framework for balanced budgeting.'),
      (Icons.trending_up_rounded,     Colors.deepPurple,  'Pay Yourself First',
        'Transfer a fixed amount to savings immediately when income arrives — before spending on anything else.'),
      (Icons.notifications_outlined,  Colors.orange,      'Track Every Rupee',
        'Small daily expenses add up fast. Even a ₹50 chai every day is ₹1,500/month — ₹18,000/year.'),
      (Icons.refresh_rounded,         AppColors.cyan,     'Review Monthly',
        'Spend 10 minutes at month-end comparing budgeted vs actual. Awareness is the first step to improvement.'),
      (Icons.emergency_outlined,      Colors.red,         'Build an Emergency Fund',
        'Aim for 3–6 months of expenses in a liquid account. This prevents using credit in a crisis.'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Financial Principles', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Time-tested rules that always apply', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 10),
      for (final p in principles) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppThemeColors.border(context)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: p.$2.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(p.$1, size: 18, color: p.$2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.$3, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 4),
              Text(p.$4, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.5)),
            ])),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
    child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber)),
  );
}
