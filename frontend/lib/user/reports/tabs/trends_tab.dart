import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class TrendsTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const TrendsTab({super.key, required this.report, required this.ca});

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('reports')) {
      return const PremiumTabGate(
        featureName: 'Spending Trends',
        description: 'Monthly trend analysis, weekly comparison charts, and AI-driven spending insights.',
        icon: Icons.trending_up_rounded,
        accentColor: AppColors.cyan,
      );
    }
    if (report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildSpendingTrends(context),
        const SizedBox(height: 14),
        _buildMonthlyTrend(context),
        const SizedBox(height: 14),
        _buildWeeklyComparison(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildSpendingTrends(BuildContext context) {
    final cmp  = report!['comparison']  as Map<String, dynamic>? ?? {};
    final adv  = report!['advanced']    as Map<String, dynamic>? ?? {};
    final ov   = report!['overview']    as Map<String, dynamic>? ?? {};
    final cats = (report!['categories'] as List? ?? []).cast<Map<String, dynamic>>();

    final items = <_TrendItem>[];
    final lentChg = cmp['lentChange'] as int?;
    if (lentChg != null) items.add(_TrendItem(
      icon: lentChg >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      color: lentChg >= 0 ? Colors.teal : Colors.orange,
      text: 'Lending ${lentChg >= 0 ? 'increased' : 'decreased'} by ${lentChg.abs()}% vs last period',
    ));
    final borChg = cmp['borrowedChange'] as int?;
    if (borChg != null) items.add(_TrendItem(
      icon: borChg >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
      color: borChg > 0 ? Colors.red.shade400 : Colors.teal,
      text: 'Borrowing ${borChg >= 0 ? 'increased' : 'decreased'} by ${borChg.abs()}% vs last period',
    ));
    final txnChg = cmp['txnCountChange'] as int?;
    if (txnChg != null) items.add(_TrendItem(
      icon: Icons.swap_horiz_rounded, color: AppColors.cyan,
      text: 'Transaction count ${txnChg >= 0 ? 'up' : 'down'} ${txnChg.abs()}% vs last period',
    ));
    final rising  = cats.where((c) => (c['trend'] as int? ?? 0) > 10).toList()
      ..sort((a, b) => ((b['trend'] as int?) ?? 0).compareTo((a['trend'] as int?) ?? 0));
    final falling = cats.where((c) => (c['trend'] as int? ?? 0) < -10).toList()
      ..sort((a, b) => ((a['trend'] as int?) ?? 0).compareTo((b['trend'] as int?) ?? 0));
    if (rising.isNotEmpty) {
      final c = rising.first;
      items.add(_TrendItem(icon: Icons.arrow_upward_rounded, color: Colors.red.shade400,
          text: '${_cap(c['category'] as String? ?? '')} spending up ${c['trend']}% this period'));
    }
    if (falling.isNotEmpty) {
      final c = falling.first;
      items.add(_TrendItem(icon: Icons.arrow_downward_rounded, color: Colors.teal,
          text: '${_cap(c['category'] as String? ?? '')} spending down ${(c['trend'] as int).abs()}% this period'));
    }
    final pendingAmt = (ov['pendingAmount'] as num? ?? 0).toDouble();
    if (pendingAmt > 0) items.add(_TrendItem(icon: Icons.pending_actions_rounded, color: Colors.orange,
        text: '${ca(pendingAmt)} still pending settlement across ${ov['pendingCount']} transactions'));
    final avgDaily = (adv['avgDailySpend'] as num? ?? 0).toDouble();
    if (avgDaily > 0) items.add(_TrendItem(icon: Icons.today_rounded, color: Colors.indigo,
        text: 'Average daily transaction volume: ${ca(avgDaily)}'));

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'Spending Trends'),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: item.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(item.icon, color: item.color, size: 16)),
            const SizedBox(width: 12),
            Expanded(child: Text(item.text,
                style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context)))),
          ]),
        )),
      ]),
    );
  }

  Widget _buildMonthlyTrend(BuildContext context) {
    final trend = (report!['monthlyTrend'] as List? ?? []).cast<Map<String, dynamic>>();
    if (trend.isEmpty) return const SizedBox.shrink();
    final maxVal = trend.map((m) => max<double>(
        (m['lent'] as num? ?? 0).toDouble(), (m['borrowed'] as num? ?? 0).toDouble())).reduce(max);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'Monthly Trend'),
        SizedBox(
          height: 180,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal == 0 ? 100 : maxVal * 1.2,
            barTouchData: BarTouchData(enabled: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= trend.length) return const SizedBox.shrink();
                final label = (trend[idx]['label'] ?? '').toString().split("'")[0].trim();
                return Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(label, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))));
              })),
              leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, horizontalInterval: maxVal == 0 ? 50 : maxVal / 4,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.divider(context), strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(trend.length, (i) => BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: (trend[i]['lent']     as num? ?? 0).toDouble(), color: Colors.teal,       width: 8, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: (trend[i]['borrowed'] as num? ?? 0).toDouble(), color: Colors.orange,     width: 8, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: (trend[i]['group']    as num? ?? 0).toDouble(), color: Colors.deepPurple.withValues(alpha: 0.7), width: 8, borderRadius: BorderRadius.circular(4)),
            ])),
          )),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend(context, Colors.teal,       'Lent'),
          const SizedBox(width: 16),
          _legend(context, Colors.orange,     'Borrowed'),
          const SizedBox(width: 16),
          _legend(context, Colors.deepPurple, 'Group'),
        ]),
      ]),
    );
  }

  Widget _buildWeeklyComparison(BuildContext context) {
    final weeks = (report!['weeklyBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    if (weeks.isEmpty || weeks.every((w) => (w['count'] as int? ?? 0) == 0)) return const SizedBox.shrink();
    final maxAmt = weeks.map((w) =>
        ((w['lent'] as num? ?? 0) + (w['borrowed'] as num? ?? 0)).toDouble()).reduce(max);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'Weekly Comparison'),
        SizedBox(
          height: 160,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxAmt == 0 ? 100 : maxAmt * 1.2,
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIdx, rod, rodIdx) {
                final w = weeks[groupIdx];
                final lbl = rodIdx == 0 ? 'Lent' : 'Borrowed';
                final v   = rodIdx == 0 ? (w['lent'] as num? ?? 0) : (w['borrowed'] as num? ?? 0);
                return BarTooltipItem('$lbl\n${ca(v)}',
                    TextStyle(fontSize: context.sp(11), color: Colors.white, fontWeight: FontWeight.bold));
              },
            )),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= weeks.length) return const SizedBox.shrink();
                final end   = weeks[i]['weekEnd'] as String? ?? '';
                final parts = end.split('-');
                final label = parts.length == 3 ? '${parts[2]}/${parts[1]}' : end;
                return Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(label, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))));
              })),
              leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.divider(context), strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(weeks.length, (i) => BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: (weeks[i]['lent']     as num? ?? 0).toDouble(), color: Colors.teal,   width: 12, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: (weeks[i]['borrowed'] as num? ?? 0).toDouble(), color: Colors.orange, width: 12, borderRadius: BorderRadius.circular(4)),
            ])),
          )),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend(context, Colors.teal,   'Lent'),
          const SizedBox(width: 16),
          _legend(context, Colors.orange, 'Borrowed'),
        ]),
      ]),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      ]);

  BoxDecoration _card(BuildContext context) => BoxDecoration(
    color: AppThemeColors.cardBg(context),
    borderRadius: BorderRadius.circular(20),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
  );

  Widget _title(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text, style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
  );

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _TrendItem {
  final IconData icon;
  final Color color;
  final String text;
  const _TrendItem({required this.icon, required this.color, required this.text});
}
