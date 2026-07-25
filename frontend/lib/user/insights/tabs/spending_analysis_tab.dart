import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/calendar_heatmap.dart';
import '../../../l10n/app_localizations.dart';

class SpendingAnalysisTab extends StatefulWidget {
  final Map<String, dynamic>? insights;
  final String Function(num?) ca;
  final Map<String, dynamic> dailySpending;

  const SpendingAnalysisTab({
    super.key,
    required this.insights,
    required this.ca,
    this.dailySpending = const {},
  });

  @override
  State<SpendingAnalysisTab> createState() => _SpendingAnalysisTabState();
}

class _SpendingAnalysisTabState extends State<SpendingAnalysisTab> {
  String _filter = 'all';

  static const _filters = [
    ('all', 'All'),
    ('quick', 'Quick'),
    ('group', 'Group'),
    ('cat', 'Category'),
  ];

  static const _catIcons = {
    'food': Icons.restaurant_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'entertainment': Icons.movie_outlined,
    'fuel': Icons.local_gas_station_outlined,
    'travel': Icons.flight_outlined,
    'medical': Icons.medical_services_outlined,
    'education': Icons.school_outlined,
    'other': Icons.category_outlined,
  };

  static final _catColors = [
    Colors.orange, Colors.pink, Colors.deepPurple, Colors.blueGrey,
    Colors.teal, Colors.red, Colors.indigo, AppColors.cyan,
  ];

  Map<String, double> _toDoubleMap(dynamic raw) =>
      (raw as Map?)?.map((k, v) => MapEntry(k as String, (v as num? ?? 0).toDouble()))
      ?? <String, double>{};

  @override
  Widget build(BuildContext context) {
    final ins      = widget.insights;
    final spending = ins?['spendingAnalysis'] as Map<String, dynamic>? ?? {};

    // Select totals and category breakdowns based on active filter
    final double totalSpent;
    final double lastTotal;
    final Map<String, double> catSpent;
    final Map<String, double> lastCatSpent;

    switch (_filter) {
      case 'quick':
        totalSpent   = (spending['totalQuick']    as num?)?.toDouble() ?? 0;
        lastTotal    = (spending['lastMonthQuick'] as num?)?.toDouble() ?? 0;
        catSpent     = _toDoubleMap(spending['categoryBreakdownQuick']);
        lastCatSpent = <String, double>{};
      case 'group':
        totalSpent   = (spending['totalGroup']    as num?)?.toDouble() ?? 0;
        lastTotal    = (spending['lastMonthGroup'] as num?)?.toDouble() ?? 0;
        catSpent     = _toDoubleMap(spending['groupBreakdown']);
        lastCatSpent = <String, double>{};
      default: // 'all' and 'cat'
        totalSpent   = (spending['total']          as num?)?.toDouble() ?? 0;
        lastTotal    = (spending['lastMonthTotal'] as num?)?.toDouble() ?? 0;
        catSpent     = _toDoubleMap(spending['categoryBreakdown']);
        lastCatSpent = _toDoubleMap(spending['lastMonthBreakdown']);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildFilterChips(context),
        const SizedBox(height: 14),
        _buildSummaryCard(context, spending, totalSpent, lastTotal, _filter),
        const SizedBox(height: 16),
        if (lastTotal > 0 && totalSpent > 0) ...[
          _buildComparisonBar(context, totalSpent, lastTotal),
          const SizedBox(height: 16),
        ],
        if (catSpent.isNotEmpty) ...[
          _buildCategoryDonut(context, catSpent, totalSpent),
          const SizedBox(height: 16),
          _buildCategoryList(context, catSpent, lastCatSpent, totalSpent),
          const SizedBox(height: 16),
        ],
        _buildHighlights(context, spending),
        if (widget.dailySpending.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(AppLocalizations.of(context).t('spending_heatmap_title'),
              style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context).t('heatmap_subtitle'),
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppThemeColors.border(context)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: CalendarHeatmap(
                dailySpending: widget.dailySpending,
                formatAmount: widget.ca,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _filters.map((f) {
          final selected = _filter == f.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = f.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? AppColors.cyan : AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(f.$2,
                    style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.cyan)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, Map<String, dynamic> spending, double total, double lastTotal, String filter) {
    final avgDaily  = (spending['avgDailySpend']  as num?)?.toDouble() ?? 0;
    final largest   = (spending['largestExpense'] as num?)?.toDouble() ?? 0;
    final txCount   = (spending['transactionCount'] as num?)?.toInt() ?? 0;
    final delta     = lastTotal > 0 ? total - lastTotal : 0.0;
    final deltaPct  = lastTotal > 0 ? (delta / lastTotal * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(filter == 'quick' ? 'Quick This Month' : filter == 'group' ? 'Group This Month' : 'This Month',
              style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.secondaryText(context))),
          const Spacer(),
          if (lastTotal > 0) _deltaChip(context, delta, deltaPct),
        ]),
        const SizedBox(height: 4),
        Text(widget.ca(total), style: TextStyle(fontSize: context.sp(24), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        if (lastTotal > 0) ...[
          const SizedBox(height: 2),
          Text('vs ${widget.ca(lastTotal)} last month',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _statCell(context, 'Daily Avg', widget.ca(avgDaily), AppColors.cyan),
          _divider(context),
          _statCell(context, 'Largest', widget.ca(largest), Colors.orange),
          _divider(context),
          _statCell(context, 'Transactions', '$txCount', Colors.deepPurple),
        ]),
      ]),
    );
  }

  Widget _buildComparisonBar(BuildContext context, double current, double last) {
    final maxVal  = current > last ? current : last;
    final curPct  = maxVal > 0 ? (current / maxVal).clamp(0.0, 1.0) : 0.0;
    final lastPct = maxVal > 0 ? (last    / maxVal).clamp(0.0, 1.0) : 0.0;
    final better  = current <= last;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Month Comparison', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        _compBar(context, 'This Month', current, curPct, better ? Colors.teal : Colors.orange),
        const SizedBox(height: 8),
        _compBar(context, 'Last Month', last, lastPct, AppThemeColors.secondaryText(context)),
      ]),
    );
  }

  Widget _compBar(BuildContext context, String label, double val, double pct, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        const Spacer(),
        Text(widget.ca(val), style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct, minHeight: 7,
          backgroundColor: AppThemeColors.border(context),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ],
  );

  Widget _deltaChip(BuildContext context, double delta, double pct) {
    final isUp  = delta > 0;
    final color = isUp ? Colors.red : Colors.teal;
    final icon  = isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 2),
        Text('${pct.abs().toStringAsFixed(0)}%',
            style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _statCell(BuildContext context, String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
    ]),
  );

  Widget _divider(BuildContext context) => Container(width: 1, height: 30, color: AppThemeColors.border(context));

  Widget _buildCategoryDonut(BuildContext context, Map<String, double> cat, double total) {
    final entries = cat.entries.where((e) => e.value > 0).toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    final sections = entries.indexed.map((ie) {
      final i = ie.$1; final e = ie.$2;
      final pct = total > 0 ? e.value / total : 0.0;
      return PieChartSectionData(
        value: e.value,
        color: _catColors[i % _catColors.length],
        radius: 46,
        showTitle: pct > 0.08,
        title: '${(pct * 100).toStringAsFixed(0)}%',
        titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_filter == 'group' ? 'Group Breakdown' : 'Category Breakdown',
            style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: Row(children: [
            SizedBox(
              width: 150,
              child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 30)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Wrap(
              spacing: 8, runSpacing: 6,
              children: entries.indexed.map((ie) {
                final i = ie.$1; final e = ie.$2;
                final color = _catColors[i % _catColors.length];
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${e.key[0].toUpperCase()}${e.key.substring(1)}',
                      style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
                ]);
              }).toList(),
            )),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCategoryList(BuildContext context, Map<String, double> cat, Map<String, double> lastCat, double total) {
    final sorted = cat.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final allKeys = cat.keys.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_filter == 'group' ? 'By Group' : 'By Category',
          style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      for (final e in sorted) ...[
        _catRow(context, e.key, e.value, lastCat[e.key] ?? 0, total, allKeys.indexOf(e.key)),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _catRow(BuildContext context, String key, double val, double lastVal, double total, int idx) {
    final pct   = total > 0 ? val / total : 0.0;
    final color = _catColors[idx % _catColors.length];
    final icon  = _catIcons[key] ?? Icons.category_outlined;
    final delta = lastVal > 0 ? val - lastVal : 0.0;
    final deltaPct = lastVal > 0 ? (delta / lastVal * 100) : 0.0;

    return Row(children: [
      Container(width: 32, height: 32,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: color)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${key[0].toUpperCase()}${key.substring(1)}',
              style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
          const Spacer(),
          Text(widget.ca(val), style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: color)),
          if (lastVal > 0) ...[
            const SizedBox(width: 6),
            _trendChip(context, delta, deltaPct),
          ],
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct, minHeight: 4,
            backgroundColor: AppThemeColors.border(context),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        if (lastVal > 0) ...[
          const SizedBox(height: 2),
          Text('Last month: ${widget.ca(lastVal)}',
              style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
        ],
      ])),
    ]);
  }

  Widget _trendChip(BuildContext context, double delta, double pct) {
    final isUp  = delta > 0;
    final color = isUp ? Colors.red : Colors.teal;
    final icon  = isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 1),
      Text('${pct.abs().toStringAsFixed(0)}%',
          style: TextStyle(fontSize: context.sp(9), color: color, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildHighlights(BuildContext context, Map<String, dynamic> spending) {
    final highlights = (spending['highlights'] as List? ?? []).map((e) => e.toString()).toList();
    if (highlights.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Highlights', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: highlights.map((h) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('•  ', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
              Expanded(child: Text(h, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context), height: 1.4))),
            ]),
          )).toList(),
        ),
      ),
    ]);
  }
}
