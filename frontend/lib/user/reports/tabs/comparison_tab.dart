import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class ComparisonTab extends StatefulWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const ComparisonTab({super.key, required this.report, required this.ca});

  @override
  State<ComparisonTab> createState() => _ComparisonTabState();
}

class _ComparisonTabState extends State<ComparisonTab> {
  bool _showCurrent = true;

  @override
  Widget build(BuildContext context) {
    final comparison     = widget.report?['comparison'] as Map<String, dynamic>?;
    final current        = (comparison?['current']  as Map<String, dynamic>?) ?? (widget.report?['overview'] as Map<String, dynamic>?) ?? {};
    final previous       = (comparison?['previous'] as Map<String, dynamic>?) ?? {};
    final currentLabel   = comparison?['currentLabel']  as String? ?? 'This Period';
    final previousLabel  = comparison?['previousLabel'] as String? ?? 'Previous Period';

    final hasPrevious = previous.values.any((v) => (v as num? ?? 0) != 0);

    final active   = _showCurrent ? current   : previous;
    final inactive = _showCurrent ? previous  : current;
    final activeLabel   = _showCurrent ? currentLabel  : previousLabel;
    final inactiveLabel = _showCurrent ? previousLabel : currentLabel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildPeriodToggle(context, currentLabel, previousLabel, hasPrevious),
        const SizedBox(height: 16),
        _buildKeyMetrics(context, active, inactive, activeLabel, inactiveLabel),
        const SizedBox(height: 16),
        _buildCategoryComparison(context, comparison),
        const SizedBox(height: 16),
        _buildSummaryInsight(context, current, previous),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildPeriodToggle(BuildContext context, String cur, String prev, bool hasPrev) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeColors.border(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        _toggleChip(context, cur,  _showCurrent,  () => setState(() => _showCurrent = true),
            Icons.calendar_today_outlined, AppColors.cyan),
        const SizedBox(width: 5),
        _toggleChip(context, prev, !_showCurrent,
            hasPrev ? () => setState(() => _showCurrent = false) : null,
            Icons.history_rounded,
            hasPrev ? AppThemeColors.secondaryText(context) : AppThemeColors.border(context)),
      ]),
    );
  }

  Widget _toggleChip(BuildContext context, String label, bool selected, VoidCallback? onTap,
      IconData icon, Color color) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.cyan.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: selected ? Border.all(color: AppColors.cyan.withValues(alpha: 0.4)) : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16,
                color: selected ? AppColors.cyan : color),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: context.sp(11),
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? AppColors.cyan : color)),
          ]),
        ),
      ),
    );
  }

  Widget _buildKeyMetrics(BuildContext context, Map active, Map inactive,
      String activeLabel, String inactiveLabel) {
    final metrics = [
      ('Net Balance',    active['netBalance'],           inactive['netBalance'],           Icons.account_balance_wallet_outlined, Colors.teal),
      ('Total Lent',     active['totalAmountLent'],      inactive['totalAmountLent'],      Icons.arrow_upward_rounded,             Colors.green),
      ('Total Borrowed', active['totalAmountBorrowed'],  inactive['totalAmountBorrowed'],  Icons.arrow_downward_rounded,           Colors.red),
      ('Transactions',   active['totalTransactions'],    inactive['totalTransactions'],    Icons.receipt_long_outlined,            AppColors.cyan),
      ('Group Expenses', active['groupExpenseTotal'],    inactive['groupExpenseTotal'],    Icons.group_outlined,                   Colors.purple),
      ('Your Share',     active['groupUserShare'],       inactive['groupUserShare'],       Icons.person_outlined,                  Colors.deepPurple),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Key Metrics',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context)))),
        _periodBadge(context, activeLabel,   AppColors.cyan),
        const SizedBox(width: 8),
        _periodBadge(context, inactiveLabel, AppThemeColors.secondaryText(context)),
      ]),
      const SizedBox(height: 10),
      for (final m in metrics) ...[
        _metricRow(context, m.$1, m.$2, m.$3, m.$4, m.$5),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _metricRow(BuildContext context, String label, dynamic cur, dynamic prev,
      IconData icon, Color color) {
    final curVal  = (cur  as num?)?.toDouble() ?? 0;
    final prevVal = (prev as num?)?.toDouble() ?? 0;
    final delta   = curVal - prevVal;
    final pct     = prevVal != 0 ? (delta / prevVal * 100) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 15, color: color)),
        const SizedBox(width: 10),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context)))),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(widget.ca(curVal),
              style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: color)),
          if (prevVal > 0)
            Text(widget.ca(prevVal),
                style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(width: 10),
        if (prevVal > 0) _deltaChip(context, delta, pct),
      ]),
    );
  }

  Widget _deltaChip(BuildContext context, double delta, double pct) {
    final isUp  = delta > 0;
    final color = isUp ? Colors.red : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 10, color: color),
        const SizedBox(width: 2),
        Text('${pct.abs().toStringAsFixed(0)}%',
            style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _periodBadge(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: context.sp(9), color: color, fontWeight: FontWeight.w600)),
  );

  Widget _buildCategoryComparison(BuildContext context, Map<String, dynamic>? comparison) {
    final catCurrent  = (comparison?['categoryBreakdown']         as Map?)?.cast<String, dynamic>() ?? {};
    final catPrevious = (comparison?['previousCategoryBreakdown'] as Map?)?.cast<String, dynamic>() ?? {};
    if (catCurrent.isEmpty && catPrevious.isEmpty) return const SizedBox.shrink();

    // Show selected period as primary, other as comparison
    final catPrimary   = _showCurrent ? catCurrent  : catPrevious;
    final catSecondary = _showCurrent ? catPrevious : catCurrent;

    final allKeys = {...catPrimary.keys, ...catSecondary.keys}.toList()
      ..sort((a, b) {
        final av = (catPrimary[a] as num? ?? 0).toDouble();
        final bv = (catPrimary[b] as num? ?? 0).toDouble();
        return bv.compareTo(av);
      });

    const catColors = [Colors.orange, Colors.pink, Colors.deepPurple, Colors.blueGrey,
      Colors.teal, Colors.red, Colors.indigo, AppColors.cyan];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Category Breakdown',
          style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(children: allKeys.take(8).indexed.map((ik) {
          final i     = ik.$1; final key = ik.$2;
          final cur   = (catPrimary[key]   as num?)?.toDouble() ?? 0;
          final prev  = (catSecondary[key] as num?)?.toDouble() ?? 0;
          final color = catColors[i % catColors.length];
          final maxV  = cur > prev ? cur : prev;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('${key[0].toUpperCase()}${key.substring(1)}',
                    style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.w600,
                        color: AppThemeColors.primaryText(context))),
                const Spacer(),
                Text(widget.ca(cur),
                    style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color)),
                const SizedBox(width: 6),
                if (prev > 0) _deltaChip(context, cur - prev, prev != 0 ? (cur - prev) / prev * 100 : 0),
              ]),
              const SizedBox(height: 4),
              Stack(children: [
                Container(height: 6, decoration: BoxDecoration(
                    color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(3))),
                if (maxV > 0)
                  FractionallySizedBox(
                    widthFactor: (cur / maxV).clamp(0.0, 1.0),
                    child: Container(height: 6, decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3))),
                  ),
              ]),
              if (prev > 0) ...[
                const SizedBox(height: 3),
                Row(children: [
                  Icon(Icons.history_rounded, size: 10, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text('Other period: ${widget.ca(prev)}',
                      style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
                  if (maxV > 0) ...[
                    const SizedBox(width: 4),
                    Expanded(child: Stack(children: [
                      Container(height: 3, decoration: BoxDecoration(
                          color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(2))),
                      FractionallySizedBox(
                        widthFactor: (prev / maxV).clamp(0.0, 1.0),
                        child: Container(height: 3, decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
                      ),
                    ])),
                  ],
                ]),
              ],
            ]),
          );
        }).toList()),
      ),
    ]);
  }

  Widget _buildSummaryInsight(BuildContext context, Map current, Map previous) {
    final curNet   = (current['netBalance']       as num?)?.toDouble() ?? 0;
    final prevNet  = (previous['netBalance']      as num?)?.toDouble() ?? 0;
    final curLent  = (current['totalAmountLent']  as num?)?.toDouble() ?? 0;
    final prevLent = (previous['totalAmountLent'] as num?)?.toDouble() ?? 0;
    final hasPrev  = prevNet != 0 || prevLent != 0;
    final improved = curNet >= prevNet;
    final lendingUp = curLent > prevLent;

    final messages = <String>[];
    if (hasPrev) {
      messages.add(improved
          ? 'Net balance improved by ${widget.ca((curNet - prevNet).abs())} vs the previous period.'
          : 'Net balance dropped by ${widget.ca((prevNet - curNet).abs())} vs the previous period.');
      messages.add(lendingUp
          ? 'Lending activity increased — ${widget.ca(curLent - prevLent)} more than before.'
          : 'Lending activity decreased by ${widget.ca((prevLent - curLent).abs())}.');
    } else {
      messages.add('No previous period data available yet.');
      messages.add('Tap the period buttons above to toggle between periods.');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (hasPrev && improved ? Colors.teal : Colors.orange).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (hasPrev && improved ? Colors.teal : Colors.orange).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(hasPrev && improved ? Icons.thumb_up_outlined : Icons.thumb_down_outlined,
              color: hasPrev && improved ? Colors.teal : Colors.orange, size: 16),
          const SizedBox(width: 8),
          Text('Period Summary', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
              color: hasPrev && improved ? Colors.teal : Colors.orange)),
        ]),
        const SizedBox(height: 10),
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('• ', style: TextStyle(color: AppThemeColors.secondaryText(context))),
              Expanded(child: Text(m, style: TextStyle(fontSize: context.sp(12),
                  color: AppThemeColors.primaryText(context), height: 1.4))),
            ]),
          ),
      ]),
    );
  }
}
