import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class HistoryTab extends StatelessWidget {
  final Map<String, dynamic>? budget;
  final String Function(num?) ca;

  const HistoryTab({super.key, required this.budget, required this.ca});

  static final _monthFmt = DateFormat('MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('budget_planning')) {
      return const PremiumTabGate(
        featureName: 'Budget History',
        description: 'View past months\' budgets, adherence scores, and spending trends over time.',
        icon: Icons.history_rounded,
        accentColor: AppColors.cyan,
      );
    }

    final history  = (budget?['history']  as List? ?? []).cast<Map<String, dynamic>>();
    final insights = budget?['insights'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (insights != null) ...[
          _buildInsights(context, insights),
          const SizedBox(height: 18),
        ],
        Text('Monthly History',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 10),
        if (history.isEmpty)
          _buildEmptyState(context)
        else
          for (final h in history) ...[
            _buildHistoryCard(context, h),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildInsights(BuildContext context, Map<String, dynamic> ins) {
    final avgAdherence = (ins['avgAdherence'] as num?)?.toDouble() ?? 0;
    final bestMonth    = ins['bestMonth']  as String?;
    final worstMonth   = ins['worstMonth'] as String?;
    final trend        = ins['trend']      as String? ?? 'stable';

    Color trendColor;
    IconData trendIcon;
    switch (trend) {
      case 'improving': trendColor = Colors.teal;    trendIcon = Icons.trending_up;   break;
      case 'worsening': trendColor = Colors.red;     trendIcon = Icons.trending_down; break;
      default:          trendColor = AppColors.cyan; trendIcon = Icons.trending_flat; break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cyan.withValues(alpha: 0.1), Colors.deepPurple.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Budget Insights', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        Row(children: [
          _insightStat(context, 'Avg. Adherence', '${avgAdherence.toStringAsFixed(0)}%',
              avgAdherence >= 80 ? Colors.teal : avgAdherence >= 60 ? Colors.orange : Colors.red),
          const SizedBox(width: 12),
          _insightStat(context, 'Trend', trend[0].toUpperCase() + trend.substring(1), trendColor,
              icon: trendIcon),
        ]),
        if (bestMonth != null || worstMonth != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 6, children: [
            if (bestMonth != null) _pill(context, '🏆 Best: $bestMonth', Colors.teal),
            if (worstMonth != null) _pill(context, '⚠ Worst: $worstMonth', Colors.orange),
          ]),
        ],
      ]),
    );
  }

  Widget _insightStat(BuildContext context, String label, String value, Color color, {IconData? icon}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 4),
        Row(children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(value, style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold, color: color)),
        ]),
      ]),
    ));
  }

  Widget _pill(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(fontSize: context.sp(11), color: color, fontWeight: FontWeight.w500)),
  );

  Widget _buildHistoryCard(BuildContext context, Map<String, dynamic> h) {
    final monthStr  = h['month']     as String? ?? '';
    final budgetAmt = (h['budget']   as num?)?.toDouble() ?? 0;
    final spentAmt  = (h['spent']    as num?)?.toDouble() ?? 0;
    final adherence = (h['adherence'] as num?)?.toDouble() ?? 0;
    final pct       = budgetAmt > 0 ? (spentAmt / budgetAmt).clamp(0.0, 1.1) : 0.0;

    String label = monthStr;
    try {
      final d = DateTime.parse('$monthStr-01');
      label = _monthFmt.format(d);
    } catch (_) {}

    Color progressColor() {
      if (pct >= 1.0)  return Colors.red;
      if (pct >= 0.85) return Colors.orange;
      return Colors.teal;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: progressColor().withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(child: Text('${adherence.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: progressColor()))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 2),
          Text('${ca(spentAmt)} of ${ca(budgetAmt)}',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppThemeColors.border(context),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor()),
            ),
          ),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Icon(
            pct >= 1.0 ? Icons.warning_amber_rounded : pct < 0.75 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            size: 16, color: progressColor(),
          ),
          const SizedBox(height: 2),
          Text('${(pct * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: context.sp(10), color: progressColor(), fontWeight: FontWeight.w600)),
        ]),
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
      const Text('📅', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 10),
      Text('No history yet', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Past month budgets will appear here', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
    ]),
  );
}
