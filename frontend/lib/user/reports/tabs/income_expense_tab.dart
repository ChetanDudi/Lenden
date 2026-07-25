import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../l10n/app_localizations.dart';

class IncomeExpenseTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const IncomeExpenseTab({super.key, required this.report, required this.ca});

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildTypeBreakdown(context),
        const SizedBox(height: 14),
        _buildClearedVsUncleared(context),
        const SizedBox(height: 14),
        _buildNetBalanceLine(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildTypeBreakdown(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final byType = report!['byType'] as Map<String, dynamic>? ?? {};
    final quick  = byType['quick']  as Map<String, dynamic>? ?? {};
    final secure = byType['secure'] as Map<String, dynamic>? ?? {};
    final group  = byType['group']  as Map<String, dynamic>? ?? {};

    final qAmt = (quick['amountLent']  as num? ?? 0) + (quick['amountBorrowed']  as num? ?? 0);
    final sAmt = (secure['amountLent'] as num? ?? 0) + (secure['amountBorrowed'] as num? ?? 0);
    final gAmt = (group['totalExpenses'] as num? ?? 0).toDouble();
    final total = qAmt + sAmt + gAmt;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, t('type_breakdown_title')),
        if (total > 0) SizedBox(
          height: 160,
          child: PieChart(PieChartData(
            sections: [
              if (qAmt > 0) PieChartSectionData(value: qAmt.toDouble(), color: Colors.amber, title: '${((qAmt / total) * 100).toStringAsFixed(0)}%', radius: 56, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              if (sAmt > 0) PieChartSectionData(value: sAmt.toDouble(), color: Colors.teal,  title: '${((sAmt / total) * 100).toStringAsFixed(0)}%', radius: 56, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
              if (gAmt > 0) PieChartSectionData(value: gAmt,           color: Colors.deepPurple, title: '${((gAmt / total) * 100).toStringAsFixed(0)}%', radius: 56, titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
            sectionsSpace: 3, centerSpaceRadius: 40,
          )),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _legend(context, Colors.amber,       t('quick_type_label'),  quick['count']  ?? 0),
          _legend(context, Colors.teal,        t('secure_type_label'), secure['count'] ?? 0),
          _legend(context, Colors.deepPurple,  t('group_type_label'),  group['count']  ?? 0),
        ]),
      ]),
    );
  }

  Widget _buildClearedVsUncleared(BuildContext context) {
    final ov       = report!['overview'] as Map<String, dynamic>? ?? {};
    final cleared   = (ov['clearedTransactions']   as num? ?? 0).toDouble();
    final uncleared = (ov['unclearedTransactions']  as num? ?? 0).toDouble();
    final total     = cleared + uncleared;
    if (total == 0) return const SizedBox.shrink();
    final pct = (cleared / total * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Row(children: [
        SizedBox(
          width: 110, height: 110,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              sectionsSpace: 3, centerSpaceRadius: 36,
              sections: [
                PieChartSectionData(value: cleared,   color: Colors.teal,                              radius: 22, title: '', showTitle: false),
                PieChartSectionData(value: uncleared, color: Colors.orange.withValues(alpha: 0.7),     radius: 22, title: '', showTitle: false),
              ],
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$pct%', style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold, color: Colors.teal)),
              Text('cleared', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Settlement Status', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 12),
          _settleRow(context, Colors.teal,   'Cleared',  cleared.toInt()),
          const SizedBox(height: 8),
          _settleRow(context, Colors.orange, 'Pending',  uncleared.toInt()),
          const SizedBox(height: 8),
          _settleRow(context, AppThemeColors.secondaryText(context), 'Total', total.toInt()),
        ])),
      ]),
    );
  }

  Widget _buildNetBalanceLine(BuildContext context) {
    final trend = (report!['monthlyTrend'] as List? ?? []).cast<Map<String, dynamic>>();
    if (trend.length < 2) return const SizedBox.shrink();

    final spots = <FlSpot>[];
    for (int i = 0; i < trend.length; i++) {
      final l = (trend[i]['lent']     as num? ?? 0).toDouble();
      final b = (trend[i]['borrowed'] as num? ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), l - b));
    }
    final vals = spots.map((s) => s.y).toList();
    final minY = vals.reduce(min);
    final maxY = vals.reduce(max);
    final pad  = max((maxY - minY) * 0.2, 500.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title(context, 'Net Balance Trend'),
        SizedBox(
          height: 160,
          child: LineChart(LineChartData(
            minY: minY - pad, maxY: maxY + pad,
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.divider(context), strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                final label = (trend[i]['label'] ?? '').toString().split("'")[0].trim();
                return Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(label, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))));
              })),
              leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [LineChartBarData(
              spots: spots, isCurved: true, color: AppColors.cyan, barWidth: 3,
              dotData: FlDotData(show: true, getDotPainter: (spot, _, __, ___) =>
                  FlDotCirclePainter(radius: 4, color: spot.y >= 0 ? Colors.teal : Colors.orange, strokeWidth: 0, strokeColor: Colors.transparent)),
              belowBarData: BarAreaData(show: true, gradient: LinearGradient(
                  colors: [AppColors.cyan.withValues(alpha: 0.18), AppColors.cyan.withValues(alpha: 0.0)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter)),
            )],
            extraLinesData: ExtraLinesData(horizontalLines: [
              HorizontalLine(y: 0, color: AppThemeColors.divider(context), strokeWidth: 1.5, dashArray: [6, 4],
                  label: HorizontalLineLabel(show: true, labelResolver: (_) => '  ₹0',
                      style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context)))),
            ]),
          )),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Positive (owed to you)', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
          const SizedBox(width: 12),
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('Negative (you owe)', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    );
  }

  Widget _legend(BuildContext context, Color color, String label, int count) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text('$label ($count)', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      ]);

  Widget _settleRow(BuildContext context, Color color, String label, int count) =>
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
        const Spacer(),
        Text('$count', style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
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
}
