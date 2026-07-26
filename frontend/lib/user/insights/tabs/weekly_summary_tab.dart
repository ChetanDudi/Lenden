import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class WeeklySummaryTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const WeeklySummaryTab({super.key, required this.insights, required this.ca});

  static final _dayFmt = DateFormat('E d');

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('smart_insights')) {
      return const PremiumTabGate(
        featureName: 'Weekly Summary',
        description: 'A detailed breakdown of your spending every week with day-by-day comparison.',
        icon: Icons.calendar_view_week_rounded,
        accentColor: AppColors.cyan,
      );
    }

    final weekly = insights?['weeklySummary'] as Map<String, dynamic>? ?? {};

    final habitsSummary = insights?['spendingHabitsSummary'] as Map<String, dynamic>?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildWeeklySummaryCard(context, weekly),
        const SizedBox(height: 16),
        _buildDayByDayChart(context, weekly),
        const SizedBox(height: 16),
        _buildWeekCategoryBreakdown(context, weekly),
        const SizedBox(height: 16),
        _buildTopSpends(context, weekly),
        const SizedBox(height: 16),
        _buildWeekComparison(context, weekly),
        const SizedBox(height: 16),
        _buildDowPattern(context, habitsSummary),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildWeeklySummaryCard(BuildContext context, Map<String, dynamic> weekly) {
    final thisWeek  = (weekly['thisWeekTotal']  as num?)?.toDouble() ?? 0;
    final lastWeek  = (weekly['lastWeekTotal']  as num?)?.toDouble() ?? 0;
    final txCount   = weekly['transactionCount'] as int? ?? 0;
    final peakDay   = weekly['peakSpendDay']    as String? ?? '';
    final delta     = thisWeek - lastWeek;
    final isUp      = delta > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('This Week', style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 4),
        Text(ca(thisWeek), style: TextStyle(fontSize: context.sp(26), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        Row(children: [
          _chip(context, isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              '${isUp ? '+' : ''}${ca(delta.abs())} vs last week',
              isUp ? Colors.red : Colors.teal),
          const SizedBox(width: 10),
          _chip(context, Icons.receipt_long_outlined, '$txCount transactions', AppColors.cyan),
          if (peakDay.isNotEmpty) ...[
            const SizedBox(width: 10),
            _chip(context, Icons.local_fire_department_outlined, peakDay, Colors.orange),
          ],
        ]),
      ]),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildDayByDayChart(BuildContext context, Map<String, dynamic> weekly) {
    final days = (weekly['dailyBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    if (days.isEmpty) return const SizedBox.shrink();

    final maxVal = days.map((d) => (d['amount'] as num?)?.toDouble() ?? 0).fold(0.0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Day by Day', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: BarChart(BarChartData(
            maxY: maxVal * 1.25,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.border(context), strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 18,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  String dayLabel = '';
                  try {
                    final d = DateTime.parse(days[i]['date'] as String? ?? '');
                    dayLabel = _dayFmt.format(d).split(' ').first;
                  } catch (_) { dayLabel = days[i]['day'] as String? ?? ''; }
                  return Text(dayLabel, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context)));
                },
              )),
            ),
            barGroups: days.indexed.map((id) {
              final i = id.$1; final d = id.$2;
              final v = (d['amount'] as num?)?.toDouble() ?? 0;
              return BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: v,
                  color: v == maxVal ? Colors.orange : AppColors.cyan,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ]);
            }).toList(),
          )),
        ),
      ]),
    );
  }

  Widget _buildTopSpends(BuildContext context, Map<String, dynamic> weekly) {
    final top = (weekly['topTransactions'] as List? ?? []).cast<Map<String, dynamic>>();
    if (top.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Top Spends', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(children: top.take(5).indexed.map((it) {
          final t = it.$2;
          final name   = t['description'] as String? ?? t['note'] as String? ?? 'Transaction';
          final amount = (t['amount'] as num?)?.toDouble() ?? 0;
          final cat    = t['category'] as String? ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 24, height: 24,
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Center(child: Text('${it.$1 + 1}', style: TextStyle(fontSize: context.sp(10), color: AppColors.cyan, fontWeight: FontWeight.bold)))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context))),
                if (cat.isNotEmpty) Text(cat, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
              ])),
              Text(ca(amount), style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: Colors.red)),
            ]),
          );
        }).toList()),
      ),
    ]);
  }

  Widget _buildWeekCategoryBreakdown(BuildContext context, Map<String, dynamic> weekly) {
    final cats = (weekly['categoryBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    if (cats.isEmpty) return const SizedBox.shrink();

    final maxAmt = cats.map((c) => (c['amount'] as num?)?.toDouble() ?? 0).fold(0.0, (a, b) => a > b ? a : b);

    const catColors = [Colors.orange, Colors.pink, Colors.deepPurple, Colors.teal, Colors.red];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('This Week by Category', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          children: cats.take(5).indexed.map((ic) {
            final c = ic.$2;
            final name   = c['category'] as String? ?? 'other';
            final amt    = (c['amount']  as num?)?.toDouble() ?? 0;
            final lastAmt = (c['lastWeek'] as num?)?.toDouble() ?? 0;
            final change  = c['change'] as int?;
            final color  = catColors[ic.$1 % catColors.length];
            final pct    = maxAmt > 0 ? amt / maxAmt : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${name[0].toUpperCase()}${name.substring(1)}',
                    style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(context)))),
                  Text(ca(amt), style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color)),
                  if (change != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: (change > 0 ? Colors.red : Colors.teal).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('${change > 0 ? '+' : ''}$change%',
                        style: TextStyle(fontSize: context.sp(9), color: change > 0 ? Colors.red : Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 5,
                    backgroundColor: AppThemeColors.border(context),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                if (lastAmt > 0) ...[
                  const SizedBox(height: 2),
                  Text('Last week: ${ca(lastAmt)}',
                    style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
                ],
              ]),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildDowPattern(BuildContext context, Map<String, dynamic>? habits) {
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
      Text('Day-of-Week Spending', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Total spent by weekday this month', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
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

  Widget _buildWeekComparison(BuildContext context, Map<String, dynamic> weekly) {
    final weeks = (weekly['last4Weeks'] as List? ?? []).cast<Map<String, dynamic>>();
    if (weeks.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('4-Week Trend', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(children: weeks.indexed.map((iw) {
          final w     = iw.$2;
          final label = w['label'] as String? ?? 'Week ${iw.$1 + 1}';
          final amt   = (w['total'] as num?)?.toDouble() ?? 0;
          final mx    = weeks.map((x) => (x['total'] as num?)?.toDouble() ?? 0).fold(0.0, (a, b) => a > b ? a : b);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              SizedBox(width: 60, child: Text(label, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context)))),
              const SizedBox(width: 8),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: mx > 0 ? amt / mx : 0,
                  minHeight: 8,
                  backgroundColor: AppThemeColors.border(context),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(width: 70, child: Text(ca(amt),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
            ]),
          );
        }).toList()),
      ),
    ]);
  }
}
