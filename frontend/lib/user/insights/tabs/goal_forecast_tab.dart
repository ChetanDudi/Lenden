import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class GoalForecastTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const GoalForecastTab({super.key, required this.insights, required this.ca});

  static final _dateFmt = DateFormat('d MMM yyyy');

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('smart_insights')) {
      return const PremiumTabGate(
        featureName: 'Goal Forecast',
        description: 'See projected completion dates for all your savings goals based on current saving rate.',
        icon: Icons.flag_outlined,
        accentColor: Colors.teal,
      );
    }

    final forecasts = (insights?['goalForecasts'] as List? ?? []).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(context, forecasts),
        const SizedBox(height: 14),
        if (forecasts.isEmpty)
          _buildEmptyState(context)
        else
          for (final f in forecasts) ...[
            _buildForecastCard(context, f),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 16),
        _buildGoalTips(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context, List<Map<String, dynamic>> forecasts) {
    if (forecasts.isEmpty) return const SizedBox.shrink();
    final onTrack    = forecasts.where((f) => f['onTrack'] as bool? ?? true).length;
    final offTrack   = forecasts.length - onTrack;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        _pill(context, '✓ $onTrack on track', Colors.teal),
        const SizedBox(width: 10),
        if (offTrack > 0) _pill(context, '⚠ $offTrack behind', Colors.orange),
      ]),
    );
  }

  Widget _pill(BuildContext context, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(fontSize: context.sp(11), color: color, fontWeight: FontWeight.w600)),
  );

  Widget _buildForecastCard(BuildContext context, Map<String, dynamic> f) {
    final name         = f['name']              as String? ?? '';
    final emoji        = f['emoji']             as String? ?? '🎯';
    final target       = (f['targetAmount']     as num?)?.toDouble() ?? 0;
    final saved        = (f['savedAmount']      as num?)?.toDouble() ?? 0;
    final onTrack      = f['onTrack']           as bool? ?? true;
    final projDateStr  = f['projectedCompletion'] as String?;
    final deadlineStr  = f['deadline']          as String?;
    final monthlyNeed  = (f['monthlyRequired']  as num?)?.toDouble();
    final currentRate  = (f['currentMonthlyRate'] as num?)?.toDouble();
    final pct          = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;

    String? projLabel;
    if (projDateStr != null) {
      try { projLabel = _dateFmt.format(DateTime.parse(projDateStr)); } catch (_) {}
    }
    String? deadLabel;
    if (deadlineStr != null) {
      try { deadLabel = _dateFmt.format(DateTime.parse(deadlineStr)); } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: onTrack ? Colors.teal.withValues(alpha: 0.25) : Colors.orange.withValues(alpha: 0.35)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (onTrack ? Colors.teal : Colors.orange).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(onTrack ? 'On Track' : 'Behind',
                style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold,
                    color: onTrack ? Colors.teal : Colors.orange)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Text(ca(saved), style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: onTrack ? Colors.teal : Colors.orange)),
          Text(' of ${ca(target)}', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct, minHeight: 7,
            backgroundColor: AppThemeColors.border(context),
            valueColor: AlwaysStoppedAnimation<Color>(onTrack ? Colors.teal : Colors.orange),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          if (projLabel != null) _infoChip(context, Icons.auto_graph_rounded, 'Projected: $projLabel', Colors.deepPurple),
          if (deadLabel != null) _infoChip(context, Icons.event_outlined, 'Deadline: $deadLabel', AppColors.cyan),
          if (monthlyNeed != null) _infoChip(context, Icons.savings_outlined, 'Need/mo: ${ca(monthlyNeed)}', Colors.orange),
          if (currentRate != null) _infoChip(context, Icons.trending_up, 'Saving/mo: ${ca(currentRate)}', Colors.teal),
        ]),
      ]),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _buildGoalTips(BuildContext context) {
    const tips = [
      (Icons.flag_outlined,           Colors.teal,        'Set SMART Goals',
        'Make goals Specific, Measurable, Achievable, Relevant, and Time-bound. "Save ₹50,000 by December" beats "save more money".'),
      (Icons.auto_awesome_outlined,   Colors.deepPurple,  'Automate Your Savings',
        'Set up an automatic transfer to your savings goal on payday. Remove willpower from the equation.'),
      (Icons.bar_chart_rounded,       Colors.orange,      'Start Small, Scale Up',
        'Begin with a comfortable monthly amount. Increase by ₹500–₹1,000 every 3 months as your income grows.'),
      (Icons.celebration_outlined,    AppColors.cyan,     'Celebrate Milestones',
        'Mark 25%, 50%, and 75% completion. Positive reinforcement keeps you motivated to reach the finish line.'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Goal Setting Tips', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      for (final t in tips) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppThemeColors.border(context)),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(color: t.$2.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(t.$1, size: 17, color: t.$2)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$3, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 4),
              Text(t.$4, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.5)),
            ])),
          ]),
        ),
        const SizedBox(height: 10),
      ],
    ]);
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
      const Text('🎯', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 10),
      Text('No goals to forecast', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Create savings goals in the Budget tab to see forecasts', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
    ]),
  );
}
