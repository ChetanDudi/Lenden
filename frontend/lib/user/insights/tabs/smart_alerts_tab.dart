import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class SmartAlertsTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const SmartAlertsTab({super.key, required this.insights, required this.ca});

  @override
  Widget build(BuildContext context) {
    final alerts        = (insights?['smartAlerts']       as List? ?? []).cast<Map<String, dynamic>>();
    final unusual       = (insights?['unusualExpenses']    as List? ?? []).cast<Map<String, dynamic>>();
    final habits        = (insights?['spendingHabits']    as List? ?? []).cast<Map<String, dynamic>>();
    final habitsSummary = insights?['spendingHabitsSummary'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildActiveAlerts(context, alerts),
        const SizedBox(height: 16),
        _buildUnusualExpenses(context, unusual),
        const SizedBox(height: 16),
        _buildSpendingHabits(context, habits),
        const SizedBox(height: 16),
        _buildDowBreakdown(context, habitsSummary),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildActiveAlerts(BuildContext context, List<Map<String, dynamic>> alerts) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Active Alerts', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(width: 8),
        if (alerts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Text('${alerts.length}', style: TextStyle(fontSize: context.sp(11), color: Colors.red, fontWeight: FontWeight.bold)),
          ),
      ]),
      const SizedBox(height: 10),
      if (alerts.isEmpty)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded, color: Colors.teal, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('No active alerts — everything looks normal.',
                style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context)))),
          ]),
        )
      else
        for (final a in alerts) ...[
          _buildAlertCard(context, a),
          const SizedBox(height: 8),
        ],
    ]);
  }

  Widget _buildAlertCard(BuildContext context, Map<String, dynamic> a) {
    final type     = a['type']     as String? ?? 'info';
    final title    = a['title']   as String? ?? '';
    final message  = a['message'] as String? ?? '';

    Color color;
    IconData icon;
    switch (type) {
      case 'critical': color = Colors.red;    icon = Icons.error_outline_rounded;          break;
      case 'warning':  color = Colors.orange; icon = Icons.warning_amber_rounded;           break;
      case 'positive': color = Colors.teal;   icon = Icons.thumb_up_outlined;              break;
      default:         color = AppColors.cyan; icon = Icons.notifications_outlined;          break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title.isNotEmpty)
            Text(title, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          if (message.isNotEmpty)
            Text(message, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _buildUnusualExpenses(BuildContext context, List<Map<String, dynamic>> unusual) {
    if (unusual.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Unusual Expenses', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Transactions significantly above your average', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
        ),
        child: Column(children: unusual.map((u) {
          final desc    = u['description'] as String? ?? u['note'] as String? ?? 'Transaction';
          final amount  = (u['amount'] as num?)?.toDouble() ?? 0;
          final avgAmt  = (u['categoryAvg'] as num?)?.toDouble();
          final pctOver = avgAmt != null && avgAmt > 0 ? ((amount - avgAmt) / avgAmt * 100).round() : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              const Icon(Icons.trending_up_rounded, size: 16, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(desc, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
                if (pctOver != null)
                  Text('${pctOver > 0 ? '+' : ''}$pctOver% vs your usual',
                      style: TextStyle(fontSize: context.sp(10), color: Colors.orange)),
              ])),
              Text(ca(amount), style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: Colors.orange)),
            ]),
          );
        }).toList()),
      ),
    ]);
  }

  Widget _buildSpendingHabits(BuildContext context, List<Map<String, dynamic>> habits) {
    if (habits.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Spending Habits', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      for (final h in habits) ...[
        _buildHabitCard(context, h),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _buildDowBreakdown(BuildContext context, Map<String, dynamic>? habits) {
    final dow = (habits?['dowBreakdown'] as Map?)
        ?.map((k, v) => MapEntry(k as String, (v as num? ?? 0).toDouble()));
    if (dow == null || dow.isEmpty) return const SizedBox.shrink();

    const order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final sorted = order
        .where((d) => dow.containsKey(d))
        .map((d) => MapEntry(d, dow[d]!))
        .toList();
    final maxVal = sorted.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Spending by Day of Week', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Where your money goes across the week this month', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          children: sorted.map((e) {
            final pct = maxVal > 0 ? e.value / maxVal : 0.0;
            final isHighest = e.value == maxVal && maxVal > 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 32, child: Text(e.key,
                  style: TextStyle(fontSize: context.sp(11),
                    color: isHighest ? Colors.orange : AppThemeColors.secondaryText(context),
                    fontWeight: isHighest ? FontWeight.bold : FontWeight.normal))),
                const SizedBox(width: 8),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 8,
                    backgroundColor: AppThemeColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(isHighest ? Colors.orange : AppColors.cyan),
                  ),
                )),
                const SizedBox(width: 8),
                SizedBox(width: 72, child: Text(ca(e.value),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold,
                    color: isHighest ? Colors.orange : AppThemeColors.primaryText(context)))),
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildHabitCard(BuildContext context, Map<String, dynamic> h) {
    final title  = h['title']  as String? ?? '';
    final detail = h['detail'] as String? ?? '';
    final kind   = h['kind']   as String? ?? 'neutral';

    Color color;
    IconData icon;
    switch (kind) {
      case 'good':    color = Colors.teal;    icon = Icons.star_outline_rounded;   break;
      case 'warning': color = Colors.orange;  icon = Icons.report_outlined;         break;
      case 'bad':     color = Colors.red;     icon = Icons.thumb_down_outlined;     break;
      default:        color = AppColors.cyan; icon = Icons.info_outline_rounded;    break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 34, height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 16, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(detail, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4)),
          ],
        ])),
      ]),
    );
  }
}
