import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class PredictionsTab extends StatelessWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;

  const PredictionsTab({super.key, required this.insights, required this.ca});

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Spending Predictions',
        description: 'AI-powered forecasts for your end-of-month spending based on your habits.',
        icon: Icons.auto_graph_rounded,
        accentColor: Colors.deepPurple,
      );
    }

    final pred = insights?['predictions'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildForecastCard(context, pred),
        const SizedBox(height: 16),
        _buildTrendChart(context, pred),
        const SizedBox(height: 16),
        _buildCategoryForecasts(context, pred),
        const SizedBox(height: 16),
        _buildConfidenceNote(context, pred),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildForecastCard(BuildContext context, Map<String, dynamic> pred) {
    final projected = (pred['projectedTotal'] as num?)?.toDouble() ?? 0;
    final current   = (pred['currentSpend']  as num?)?.toDouble() ?? 0;
    final budget    = (pred['budget']        as num?)?.toDouble() ?? 0;
    final daysLeft  = pred['daysRemainingInMonth'] as int? ?? 0;
    final onTrack   = budget <= 0 || projected <= budget;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: onTrack
              ? [Colors.teal.withValues(alpha: 0.12), Colors.teal.withValues(alpha: 0.05)]
              : [Colors.red.withValues(alpha: 0.12), Colors.orange.withValues(alpha: 0.05)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (onTrack ? Colors.teal : Colors.red).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(onTrack ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
              color: onTrack ? Colors.teal : Colors.red, size: 18),
          const SizedBox(width: 8),
          Text(onTrack ? 'On Track' : 'Overspend Risk',
              style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
                  color: onTrack ? Colors.teal : Colors.red)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('$daysLeft days left', style: TextStyle(fontSize: context.sp(10), color: Colors.deepPurple)),
          ),
        ]),
        const SizedBox(height: 12),
        Text('Projected End-of-Month', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 2),
        Text(ca(projected), style: TextStyle(fontSize: context.sp(26), fontWeight: FontWeight.bold,
            color: onTrack ? Colors.teal : Colors.red)),
        const SizedBox(height: 8),
        Row(children: [
          _miniStat(context, 'Spent so far', ca(current), AppColors.cyan),
          const SizedBox(width: 16),
          if (budget > 0) _miniStat(context, 'Budget', ca(budget), Colors.deepPurple),
        ]),
      ]),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
      Text(value, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: color)),
    ],
  );

  Widget _buildTrendChart(BuildContext context, Map<String, dynamic> pred) {
    final daily = (pred['dailyProjection'] as List? ?? []).cast<Map<String, dynamic>>();
    if (daily.isEmpty) return _buildDailyRateCard(context, pred);

    final spots = daily.asMap().entries.map((e) {
      final v = (e.value['amount'] as num?)?.toDouble() ?? 0;
      return FlSpot(e.key.toDouble(), v);
    }).toList();

    final actualCount = pred['actualDays'] as int? ?? spots.length;
    final actualSpots    = spots.take(actualCount).toList();
    final projectedSpots = spots.skip(actualCount - 1).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Spending Projection', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 4),
        Row(children: [
          _legend(context, AppColors.cyan, 'Actual'),
          const SizedBox(width: 12),
          _legend(context, Colors.deepPurple.withValues(alpha: 0.6), 'Projected'),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 140,
          child: LineChart(LineChartData(
            gridData: FlGridData(
              show: true,
              getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.border(context), strokeWidth: 0.5),
              drawVerticalLine: false,
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true, reservedSize: 18,
                getTitlesWidget: (v, _) {
                  if (v.toInt() % 5 != 0) return const SizedBox.shrink();
                  return Text('${v.toInt()}', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context)));
                },
              )),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: actualSpots, color: AppColors.cyan, barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: true, color: AppColors.cyan.withValues(alpha: 0.08)),
              ),
              if (projectedSpots.length > 1)
                LineChartBarData(
                  spots: projectedSpots, color: Colors.deepPurple.withValues(alpha: 0.6), barWidth: 2,
                  dashArray: [5, 4],
                  dotData: const FlDotData(show: false),
                ),
            ],
          )),
        ),
      ]),
    );
  }

  Widget _buildDailyRateCard(BuildContext context, Map<String, dynamic> pred) {
    final rate        = (pred['dailyRate']    as num?)?.toDouble() ?? 0;
    final current     = (pred['currentSpend'] as num?)?.toDouble() ?? 0;
    final daysElapsed = (pred['daysElapsed']  as num?)?.toInt() ?? 0;
    final daysTotal   = (pred['daysTotal']    as num?)?.toInt() ?? 30;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Month Progress', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        Row(children: [
          _miniStat(context, 'Daily Rate', ca(rate), AppColors.cyan),
          const SizedBox(width: 16),
          _miniStat(context, 'Spent So Far', ca(current), Colors.deepPurple),
          const SizedBox(width: 16),
          _miniStat(context, 'Day', '$daysElapsed/$daysTotal', Colors.orange),
        ]),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Days elapsed', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          Text('$daysElapsed of $daysTotal days', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: daysTotal > 0 ? daysElapsed / daysTotal : 0,
            minHeight: 8,
            backgroundColor: AppThemeColors.border(context),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.cyan),
          ),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: Colors.deepPurple),
          const SizedBox(width: 6),
          Expanded(child: Text(
            'Day-by-day projection will appear once more spending data is available for this month.',
            style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4),
          )),
        ]),
      ]),
    );
  }

  Widget _legend(BuildContext context, Color color, String label) => Row(children: [
    Container(width: 16, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
  ]);

  Widget _buildCategoryForecasts(BuildContext context, Map<String, dynamic> pred) {
    final cats = (pred['categoryForecasts'] as Map?)?.cast<String, dynamic>() ?? {};
    if (cats.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Category Forecasts', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          children: cats.entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(child: Text('${e.key[0].toUpperCase()}${e.key.substring(1)}',
                  style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context)))),
              Text(ca(e.value as num), style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppColors.cyan)),
            ]),
          )).toList(),
        ),
      ),
    ]);
  }

  Widget _buildConfidenceNote(BuildContext context, Map<String, dynamic> pred) {
    final confidence = (pred['confidence'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        const Icon(Icons.auto_awesome_outlined, size: 15, color: Colors.deepPurple),
        const SizedBox(width: 8),
        Expanded(child: Text(
          'AI prediction confidence: ${confidence.toStringAsFixed(0)}%. '
          'Based on your last 90 days of spending patterns.',
          style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.4),
        )),
      ]),
    );
  }
}
