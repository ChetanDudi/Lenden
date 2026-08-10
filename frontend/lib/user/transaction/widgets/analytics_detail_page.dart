import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/currency_display.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import './analytics_models.dart';

class AnalyticsDetailPage extends StatelessWidget {
  final String tabTitle;
  final AnalyticsMetric metric;
  final Map<String, dynamic> analytics;
  final List<AnalyticsMetric> allMetrics;
  final String selectedDisplayCurrency;
  final DisplayCurrencyData? displayCurrencyData;
  final bool hasMissingConversion;

  const AnalyticsDetailPage({
    super.key,
    required this.tabTitle,
    required this.metric,
    required this.analytics,
    required this.allMetrics,
    required this.selectedDisplayCurrency,
    required this.displayCurrencyData,
    required this.hasMissingConversion,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final months = List<String>.from(analytics['months'] ?? const []);
    final monthlyCounts =
        (analytics['monthlyCounts'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList();
    final total = ((analytics['total'] as num?) ?? 0).toDouble();
    final cleared = ((analytics['cleared'] as num?) ?? 0).toDouble();
    final pending = ((analytics['uncleared'] as num?) ?? 0).toDouble();
    final ratio = total == 0 ? 0.0 : (cleared / total).clamp(0.0, 1.0);

    final secondaryMetrics =
        allMetrics.where((item) => item.id != metric.id).take(2).toList();

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: metric.title),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: metric.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: metric.colors.first.withValues(alpha: 0.30),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    metric.displayValue,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    metric.subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      hasMissingConversion
                          ? t('showing_inr_values_label')
                          : t('showing_in_currency_message').replaceFirst('{currency}', selectedDisplayCurrency.toUpperCase()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasMissingConversion) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFF6B6B)),
                ),
                child: Text(
                  t('currency_unavailable_showing_inr_message'),
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              t('quick_facts_label'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniInfoCard(
                    title: t('records_label'),
                    value: total.toStringAsFixed(0),
                    color: const Color(0xFF1B58B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniInfoCard(
                    title: t('completion_label'),
                    value: '${(ratio * 100).toStringAsFixed(0)}%',
                    color: AppColors.cyan,
                  ),
                ),
              ],
            ),
            if (secondaryMetrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: secondaryMetrics
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: item == secondaryMetrics.first &&
                                    secondaryMetrics.length > 1
                                ? 12
                                : 0,
                          ),
                          child: _MiniInfoCard(
                            title: item.title,
                            value: item.displayValue,
                            color: item.colors.first,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 22),
            _ChartShell(
              title: t('todays_stats_label'),
              trailing: metric.isTrend
                  ? Text(
                      t('twelve_months_label'),
                      style: const TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendDot(
                            color: const Color(0xFF7C9DFF), label: t('cleared_label')),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: const Color(0xFFFF8B7B), label: t('pending_label')),
                      ],
                    ),
              child: SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 5,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.grey.withValues(alpha: 0.16),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: TextStyle(
                              fontSize: 10,
                              color: AppThemeColors.secondaryText(context),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= months.length) {
                              return const SizedBox.shrink();
                            }
                            final label = months[index];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                label.length >= 7 ? label.substring(5) : label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppThemeColors.secondaryText(context),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      _buildPrimaryLine(monthlyCounts),
                      if (!metric.isTrend)
                        _buildSecondaryLine(cleared, pending, months.length),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ChartShell(
              title: t('needed_info_label'),
              child: Column(
                children: [
                  _InfoRow(
                    label: metric.title,
                    value: metric.displayValue,
                  ),
                  _InfoRow(
                    label: t('total_records_label'),
                    value: total.toStringAsFixed(0),
                  ),
                  _InfoRow(
                    label: t('cleared_label'),
                    value: cleared.toStringAsFixed(0),
                  ),
                  _InfoRow(
                    label: t('pending_label'),
                    value: pending.toStringAsFixed(0),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildPrimaryLine(List<double> monthlyCounts) {
    final points = monthlyCounts.isEmpty
        ? [const FlSpot(0, 0)]
        : monthlyCounts
            .asMap()
            .entries
            .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
            .toList();

    return LineChartBarData(
      spots: points,
      isCurved: true,
      color: const Color(0xFF7C9DFF),
      barWidth: 3,
      isStrokeCapRound: true,
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C9DFF).withValues(alpha: 0.25),
            const Color(0xFF7C9DFF).withValues(alpha: 0.03),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 4,
          color: Colors.white,
          strokeWidth: 2.5,
          strokeColor: const Color(0xFF7C9DFF),
        ),
      ),
    );
  }

  LineChartBarData _buildSecondaryLine(
    double cleared,
    double pending,
    int length,
  ) {
    final count = length <= 0 ? 1 : length;
    final step = count == 1 ? 0.0 : 1.0 / (count - 1);

    final points = List.generate(count, (index) {
      final progress = step * index;
      final value = (cleared * (1 - progress)) + (pending * progress);
      return FlSpot(index.toDouble(), value);
    });

    return LineChartBarData(
      spots: points,
      isCurved: true,
      color: const Color(0xFFFF8B7B),
      barWidth: 2,
      dashArray: const [6, 4],
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8B7B).withValues(alpha: 0.16),
            const Color(0xFFFF8B7B).withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _MiniInfoCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeColors.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _ChartShell({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppThemeColors.secondaryText(context),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : AppThemeColors.border(context),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppThemeColors.secondaryText(context),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppThemeColors.primaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}
