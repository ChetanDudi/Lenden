import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class MonthlyBudgetTab extends StatefulWidget {
  final Map<String, dynamic>? budget;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? recommendations;
  final Map<String, dynamic>? rolloverPreview;
  final Map<String, dynamic>? streak;
  final DateTime now;
  final String Function(num?) ca;
  final Future<void> Function(String type, String value) onSaveBudget;
  final VoidCallback onShowPresets;
  final Future<void> Function() onApplyRollover;

  const MonthlyBudgetTab({
    super.key,
    required this.budget,
    required this.status,
    required this.recommendations,
    this.rolloverPreview,
    this.streak,
    required this.now,
    required this.ca,
    required this.onSaveBudget,
    required this.onShowPresets,
    required this.onApplyRollover,
  });

  @override
  State<MonthlyBudgetTab> createState() => _MonthlyBudgetTabState();
}

class _MonthlyBudgetTabState extends State<MonthlyBudgetTab> {
  bool _saving = false;
  double? _simTarget; // simulation slider value
  final _controllers = <String, TextEditingController>{
    'quick': TextEditingController(),
    'secure': TextEditingController(),
    'group': TextEditingController(),
    'overall': TextEditingController(),
  };
  final _editing = <String, bool>{
    'quick': false, 'secure': false, 'group': false, 'overall': false,
  };

  @override
  void dispose() {
    for (final c in _controllers.values) { c.dispose(); }
    super.dispose();
  }

  double _limitFor(String type) {
    final limits = widget.budget?['limits'] as Map?;
    return (limits?[type] as num? ?? 0).toDouble();
  }
  double _spentFor(String type) =>
      (widget.status?['spent']?[type] as num? ?? 0).toDouble();
  int _countFor(String type) =>
      (widget.status?['counts']?[type] as num? ?? 0).toInt();

  int get _daysInMonth => DateUtils.getDaysInMonth(widget.now.year, widget.now.month);
  int get _daysElapsed => widget.now.day;
  int get _daysRemaining => _daysInMonth - _daysElapsed;
  double get _monthProgress => _daysElapsed / _daysInMonth;

  double _projectedSpend(String type) {
    final spent = _spentFor(type);
    if (_daysElapsed == 0) return 0;
    return spent / _daysElapsed * _daysInMonth;
  }

  Color _progressColor(double pct) {
    if (pct >= 1.0)  return Colors.red;
    if (pct >= 0.85) return Colors.orange;
    return Colors.teal;
  }

  String _statusLabel(double pct) {
    if (pct >= 1.0)  return 'Exceeded';
    if (pct >= 0.85) return 'At Risk';
    return 'On Track';
  }

  Future<void> _save(String type) async {
    final newVal = double.tryParse(_controllers[type]!.text.trim()) ?? 0;

    if (type == 'overall' && newVal > 0) {
      final sumOfParts = _limitFor('quick') + _limitFor('secure') + _limitFor('group');
      if (newVal < sumOfParts) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Overall cap (₹${newVal.toStringAsFixed(0)}) cannot be less than '
            'the sum of Quick + Secure + Group limits '
            '(₹${sumOfParts.toStringAsFixed(0)}).',
          ),
          duration: const Duration(seconds: 4),
        ));
        return;
      }
    }

    // If setting a sub-limit, warn if the new sum would exceed the overall cap
    if (type != 'overall' && newVal > 0) {
      final overall = _limitFor('overall');
      if (overall > 0) {
        final others = ['quick', 'secure', 'group']
            .where((t) => t != type)
            .fold(0.0, (s, t) => s + _limitFor(t));
        final newSum = others + newVal;
        if (newSum > overall) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            content: Text(
              '${type[0].toUpperCase()}${type.substring(1)} limit (₹${newVal.toStringAsFixed(0)}) '
              'would push the total to ₹${newSum.toStringAsFixed(0)}, '
              'exceeding your Overall Cap of ₹${overall.toStringAsFixed(0)}.',
            ),
            duration: const Duration(seconds: 4),
          ));
          return;
        }
      }
    }

    setState(() => _saving = true);
    await widget.onSaveBudget(type, _controllers[type]!.text);
    if (mounted) setState(() { _saving = false; _editing[type] = false; });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildStreakBanner(context),
        _buildMonthProgressCard(context),
        const SizedBox(height: 14),
        _buildOverallRing(context),
        const SizedBox(height: 14),
        _buildRolloverCard(context),
        _buildComparisonCard(context),
        const SizedBox(height: 14),
        _buildBudgetVsActualChart(context),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Text('Monthly Limits',
                style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onShowPresets,
              icon: const Icon(Icons.auto_fix_high_rounded, size: 14, color: AppColors.cyan),
              label: Text('Presets', style: TextStyle(fontSize: context.sp(11), color: AppColors.cyan)),
            ),
          ]),
        ),
        _buildBudgetCard(context, 'quick',   Icons.flash_on_outlined,   Colors.amber,      'Quick'),
        const SizedBox(height: 10),
        _buildBudgetCard(context, 'secure',  Icons.shield_outlined,     Colors.teal,       'Secure'),
        const SizedBox(height: 10),
        _buildBudgetCard(context, 'group',   Icons.group_outlined,      Colors.deepPurple, 'Group'),
        const SizedBox(height: 10),
        _buildBudgetCard(context, 'overall', Icons.account_balance_wallet_outlined, AppColors.cyan, 'Overall Cap'),
        _buildAllocationStrip(context),
        const SizedBox(height: 14),
        _buildTipsRow(context),
        const SizedBox(height: 14),
        _buildSimulationCard(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildStreakBanner(BuildContext context) {
    final s = widget.streak;
    final current = (s?['streak'] as num?)?.toInt() ?? 0;
    if (current == 0) return const SizedBox.shrink();
    final longest = (s?['longestStreak'] as num?)?.toInt() ?? 0;
    final isRecord = current >= longest && longest > 0;
    final (icon, label, color) = current >= 6
        ? ('🔥', '$current-month streak!', Colors.orange)
        : current >= 3
            ? ('⚡', '$current months on budget', Colors.amber)
            : ('✅', '$current month on budget', Colors.teal);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.06)],
          begin: Alignment.centerLeft, end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.sp(13), color: color)),
          if (isRecord)
            Text('Personal best!',
                style: TextStyle(fontSize: context.sp(10), color: color.withValues(alpha: 0.8))),
          if (!isRecord && longest > current)
            Text('Best: $longest months — keep going!',
                style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ])),
        if (isRecord)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text('🏆 Record', style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }

  Widget _buildRolloverCard(BuildContext context) {
    final r = widget.rolloverPreview;
    if (r == null) return const SizedBox.shrink();
    final surplus = (r['surplus'] as num?)?.toDouble() ?? 0;
    final alreadyApplied = r['alreadyApplied'] as bool? ?? false;
    if (surplus <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.withValues(alpha: 0.12), Colors.green.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.savings_outlined, color: Colors.teal, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Last Month Surplus', style: TextStyle(fontSize: context.sp(13),
                fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            Text('You saved ${widget.ca(surplus)} under budget',
                style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          ])),
          Text(widget.ca(surplus),
              style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: Colors.teal)),
        ]),
        const SizedBox(height: 12),
        alreadyApplied
            ? Row(children: [
                const Icon(Icons.check_circle_outline, color: Colors.teal, size: 16),
                const SizedBox(width: 6),
                Text('Rolled over to this month\'s budget',
                    style: TextStyle(fontSize: context.sp(12), color: Colors.teal, fontWeight: FontWeight.w600)),
              ])
            : Row(children: [
                Expanded(
                  child: Text('Add this surplus to this month\'s overall limit?',
                      style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
                ),
                const SizedBox(width: 12),
                _saving
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.teal, strokeWidth: 2))
                    : ElevatedButton(
                        onPressed: () async {
                          setState(() => _saving = true);
                          await widget.onApplyRollover();
                          if (mounted) setState(() => _saving = false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal, foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Apply Rollover'),
                      ),
              ]),
      ]),
    );
  }

  Widget _buildMonthProgressCard(BuildContext context) {
    final pct = _monthProgress;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.cyan.withValues(alpha: 0.12), Colors.deepPurple.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Month Progress', style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            Text('Day $_daysElapsed of $_daysInMonth', style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_bottom_rounded, size: 14, color: AppColors.cyan),
              const SizedBox(width: 4),
              Text('$_daysRemaining days left',
                  style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: AppColors.cyan)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Stack(children: [
          Container(height: 8, decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(4))),
          FractionallySizedBox(
            widthFactor: pct,
            child: Container(height: 8, decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.cyan, Colors.deepPurple.shade300]),
              borderRadius: BorderRadius.circular(4),
            )),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Text('${(pct * 100).toStringAsFixed(0)}% of month elapsed',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const Spacer(),
          Text('${_countFor('quick') + _countFor('secure') + _countFor('group')} transactions',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    );
  }

  Widget _buildOverallRing(BuildContext context) {
    final totalSpent = _spentFor('overall') > 0
        ? _spentFor('overall')
        : _spentFor('quick') + _spentFor('secure') + _spentFor('group');
    final totalLimit = _limitFor('overall') > 0
        ? _limitFor('overall')
        : _limitFor('quick') + _limitFor('secure') + _limitFor('group');
    final hasLimit = totalLimit > 0;
    final pct      = hasLimit ? (totalSpent / totalLimit).clamp(0.0, 1.0) : 0.0;
    final color    = _progressColor(pct);
    final projected = _projectedSpend('overall') > 0
        ? _projectedSpend('overall')
        : _projectedSpend('quick') + _projectedSpend('secure') + _projectedSpend('group');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBox(context),
      child: Row(children: [
        SizedBox(width: 90, height: 90,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 90, height: 90,
              child: CircularProgressIndicator(
                value: pct, strokeWidth: 9,
                backgroundColor: AppThemeColors.border(context),
                valueColor: AlwaysStoppedAnimation(color),
                strokeCap: StrokeCap.round,
              )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: context.sp(18), fontWeight: FontWeight.bold, color: color)),
              Text('used', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total Budget', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 8),
          _statRow(context, 'Spent', widget.ca(totalSpent), color),
          const SizedBox(height: 4),
          _statRow(context, 'Limit', hasLimit ? widget.ca(totalLimit) : 'Not set', AppThemeColors.secondaryText(context)),
          const SizedBox(height: 4),
          if (hasLimit) _statRow(context, 'Projected', widget.ca(projected), projected > totalLimit ? Colors.red : Colors.teal),
          if (hasLimit && projected > totalLimit) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Text('⚠ On track to exceed limit',
                  style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: Colors.red)),
            ),
          ],
        ])),
      ]),
    );
  }

  Widget _statRow(BuildContext context, String label, String value, Color c) => Row(children: [
    Text('$label:', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
    const SizedBox(width: 6),
    Text(value, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w600, color: c)),
  ]);

  Widget _buildBudgetVsActualChart(BuildContext context) {
    const types  = ['quick', 'secure', 'group'];
    const labels = ['Quick', 'Secure', 'Group'];
    final anyLimit = types.any((t) => _limitFor(t) > 0);
    if (!anyLimit) return const SizedBox.shrink();
    final maxVal = types.map((t) => max(_limitFor(t), _spentFor(t))).reduce(max);
    if (maxVal == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardBox(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Budget vs Actual',
              style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const Spacer(),
          _legend2(context, Colors.grey.shade400, 'Limit'),
          const SizedBox(width: 10),
          _legend2(context, AppColors.cyan, 'Spent'),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: BarChart(BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal * 1.25,
            barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppThemeColors.cardBg(context),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final type = types[groupIndex];
                final v   = rodIndex == 0 ? _limitFor(type) : _spentFor(type);
                final lbl = rodIndex == 0 ? 'Limit' : 'Spent';
                return BarTooltipItem('$lbl\n${widget.ca(v)}',
                    TextStyle(fontSize: context.sp(11), color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold));
              },
            )),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(labels[idx], style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))));
              })),
              leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.divider(context), strokeWidth: 0.5)),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(types.length, (i) => BarChartGroupData(
              x: i, barsSpace: 4,
              barRods: [
                BarChartRodData(toY: _limitFor(types[i]), color: Colors.grey.withValues(alpha: 0.35), width: 14, borderRadius: BorderRadius.circular(4)),
                BarChartRodData(
                  toY: _spentFor(types[i]),
                  color: _progressColor(_limitFor(types[i]) > 0 ? _spentFor(types[i]) / _limitFor(types[i]) : 0),
                  width: 14, borderRadius: BorderRadius.circular(4),
                ),
              ],
            )),
          )),
        ),
      ]),
    );
  }

  Widget _buildBudgetCard(BuildContext context, String type, IconData icon, Color color, String label) {
    final limit      = _limitFor(type);
    final spent      = _spentFor(type);
    final count      = _countFor(type);
    final hasLimit   = limit > 0;
    final pct        = hasLimit ? (spent / limit).clamp(0.0, 1.1) : 0.0;
    final remaining  = hasLimit ? (limit - spent).clamp(0.0, double.infinity) : 0.0;
    final projected  = _projectedSpend(type);
    final isEditing  = _editing[type] ?? false;
    final willExceed = hasLimit && projected > limit;

    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
        border: hasLimit && pct >= 1.0 ? Border.all(color: Colors.red.withValues(alpha: 0.4), width: 1.5) : null,
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                Text(count > 0 ? '$count transaction${count > 1 ? 's' : ''} this month' : 'No transactions yet',
                    style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
              ])),
              if (!isEditing)
                TextButton.icon(
                  onPressed: () {
                    _controllers[type]!.text = hasLimit ? limit.toStringAsFixed(0) : '';
                    setState(() => _editing[type] = true);
                  },
                  icon: Icon(Icons.edit_outlined, size: 14, color: color),
                  label: Text('Edit', style: TextStyle(fontSize: context.sp(11), color: color)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
            ]),
            if (isEditing) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: _controllers[type],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  autofocus: true,
                  style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    hintText: 'Enter limit', prefixText: '₹ ',
                    prefixStyle: TextStyle(fontSize: context.sp(14), color: color, fontWeight: FontWeight.bold),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true, fillColor: color.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color.withValues(alpha: 0.4))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 2)),
                  ),
                )),
                const SizedBox(width: 8),
                _saving
                    ? const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
                    : Row(children: [
                        _iconBtn(context, Icons.check, color, () => _save(type)),
                        const SizedBox(width: 6),
                        _iconBtn(context, Icons.close, AppThemeColors.border(context), () => setState(() => _editing[type] = false)),
                        if (hasLimit) ...[
                          const SizedBox(width: 6),
                          _iconBtn(context, Icons.delete_outline, Colors.red.withValues(alpha: 0.15), () => _save(type), iconColor: Colors.red),
                        ],
                      ]),
              ]),
            ],
            if (hasLimit && !isEditing) ...[
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${widget.ca(spent)} spent',   style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: _progressColor(pct))),
                Text('${widget.ca(remaining)} left', style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w600, color: Colors.teal)),
              ]),
              const SizedBox(height: 6),
              _progressBar(context, pct),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _chip(context, _statusLabel(pct), _progressColor(pct)),
                Text('${(pct * 100).toStringAsFixed(0)}% of ${widget.ca(limit)}',
                    style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
              ]),
              if (count > 0) ...[
                const SizedBox(height: 10),
                Divider(color: AppThemeColors.divider(context), height: 1),
                const SizedBox(height: 10),
                Row(children: [
                  Icon(willExceed ? Icons.warning_amber_rounded : Icons.trending_up_rounded,
                      size: 14, color: willExceed ? Colors.orange : Colors.teal),
                  const SizedBox(width: 6),
                  Text(
                    willExceed
                        ? 'Projected ${widget.ca(projected)} — will exceed!'
                        : 'Projected ${widget.ca(projected)} by month-end',
                    style: TextStyle(fontSize: context.sp(11), color: willExceed ? Colors.orange : AppThemeColors.secondaryText(context)),
                  ),
                ]),
              ],
            ],
            if (!hasLimit && !isEditing) ...[
              const SizedBox(height: 10),
              Builder(builder: (context) {
                final overallCap  = _limitFor('overall');
                final otherTypes  = ['quick', 'secure', 'group'].where((t) => t != type);
                final otherSumSet = otherTypes.fold(0.0, (sum, t) => sum + _limitFor(t));
                final available   = overallCap > 0 ? (overallCap - otherSumSet) : 0.0;
                final showCap     = type != 'overall' && overallCap > 0;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('No limit set — tap Edit to set one',
                      style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
                  if (showCap) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.25)),
                      ),
                      child: Row(children: [
                        Icon(Icons.account_balance_wallet_outlined, size: 13, color: color),
                        const SizedBox(width: 6),
                        Expanded(child: Text(
                          available > 0
                              ? '${widget.ca(available)} available from Overall Cap'
                              : 'No headroom left in Overall Cap',
                          style: TextStyle(
                            fontSize: context.sp(11),
                            color: available > 0 ? color : Colors.red.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        )),
                      ]),
                    ),
                  ],
                ]);
              }),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _buildComparisonCard(BuildContext context) {
    final rec      = widget.recommendations;
    final prev     = rec?['prevMonth']     as Map<String, dynamic>?;
    final avg3     = rec?['threeMonthAvg'] as Map<String, dynamic>?;
    if (prev == null && avg3 == null) return const SizedBox.shrink();

    final prevQuick  = (prev?['quick']  as num?)?.toDouble() ?? 0;
    final prevSecure = (prev?['secure'] as num?)?.toDouble() ?? 0;
    final prevTotal  = prevQuick + prevSecure;
    final curQuick   = _spentFor('quick');
    final curSecure  = _spentFor('secure');
    final curTotal   = curQuick + curSecure;
    final avg3Quick  = (avg3?['quick']  as num?)?.toDouble() ?? 0;
    final avg3Secure = (avg3?['secure'] as num?)?.toDouble() ?? 0;
    final avg3Total  = avg3Quick + avg3Secure;

    if (prevTotal == 0 && avg3Total == 0) return const SizedBox.shrink();

    final delta    = curTotal - prevTotal;
    final deltaPct = prevTotal > 0 ? (delta / prevTotal * 100) : 0.0;
    final better   = delta <= 0;

    Widget _cmpRow(String label, double cur, double last, Color color) {
      final d    = cur - last;
      final dpct = last > 0 ? (d / last * 100) : 0.0;
      final up   = d > 0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context))),
          const Spacer(),
          Text(widget.ca(cur), style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          if (last > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: (up ? Colors.red : Colors.teal).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  size: 10, color: up ? Colors.red : Colors.teal),
              Text('${dpct.abs().toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: context.sp(9), color: up ? Colors.red : Colors.teal, fontWeight: FontWeight.bold)),
            ]),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardBox(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('vs Last Month', style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (better ? Colors.teal : Colors.orange).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(better ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  size: 13, color: better ? Colors.teal : Colors.orange),
              const SizedBox(width: 3),
              Text(
                prevTotal > 0
                    ? '${deltaPct.abs().toStringAsFixed(0)}% ${better ? 'less' : 'more'}'
                    : 'New data',
                style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold,
                    color: better ? Colors.teal : Colors.orange),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (prevQuick > 0 || curQuick > 0)
          _cmpRow('Quick', curQuick, prevQuick, Colors.amber),
        if (prevSecure > 0 || curSecure > 0)
          _cmpRow('Secure', curSecure, prevSecure, Colors.teal),
        const Divider(height: 16),
        _cmpRow('Total (excl. group)', curTotal, prevTotal, AppColors.cyan),
        if (avg3Total > 0) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.history_rounded, size: 12, color: Colors.grey),
            const SizedBox(width: 4),
            Text('3-month avg: ${widget.ca(avg3Total)}',
                style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
            const Spacer(),
            if (curTotal > 0 && avg3Total > 0)
              Text(
                curTotal <= avg3Total ? 'Below avg ✓' : 'Above avg',
                style: TextStyle(fontSize: context.sp(10),
                    color: curTotal <= avg3Total ? Colors.teal : Colors.orange,
                    fontWeight: FontWeight.w600),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _buildSimulationCard(BuildContext context) {
    final overall    = _limitFor('overall');
    final totalSpent = _spentFor('overall') > 0
        ? _spentFor('overall')
        : _spentFor('quick') + _spentFor('secure') + _spentFor('group');
    final dailyRate  = _daysElapsed > 0 ? totalSpent / _daysElapsed : 0.0;

    if (overall <= 0 && totalSpent <= 0) return const SizedBox.shrink();

    final baseLimit = overall > 0 ? overall : totalSpent * 1.5;
    final minSim    = baseLimit * 0.4;
    final maxSim    = baseLimit * 1.3;

    _simTarget ??= baseLimit;
    final target    = _simTarget!.clamp(minSim, maxSim);
    final simMonthlySpend = dailyRate * _daysInMonth * (target / baseLimit).clamp(0.1, 1.3);
    final saving    = baseLimit - target;
    final yearlySaving = saving * 12;
    final dailyAllowance = target / _daysInMonth;
    final isReducing = target < baseLimit;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.tune_rounded, color: Colors.deepPurple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Budget Simulator',
                style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            Text('What if you changed your overall limit?',
                style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
          ])),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Text('Target: ', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
          Text(widget.ca(target),
              style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: Colors.deepPurple)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (isReducing ? Colors.teal : Colors.orange).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isReducing
                  ? '${((1 - target / baseLimit) * 100).toStringAsFixed(0)}% less'
                  : '${((target / baseLimit - 1) * 100).toStringAsFixed(0)}% more',
              style: TextStyle(
                  fontSize: context.sp(10), fontWeight: FontWeight.bold,
                  color: isReducing ? Colors.teal : Colors.orange),
            ),
          ),
        ]),
        Slider(
          value: target,
          min: minSim,
          max: maxSim,
          divisions: 50,
          activeColor: Colors.deepPurple,
          inactiveColor: Colors.deepPurple.withValues(alpha: 0.15),
          onChanged: (v) => setState(() => _simTarget = v),
        ),
        Row(children: [
          Text(widget.ca(minSim), style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
          const Spacer(),
          Text(widget.ca(maxSim), style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            _simRow(context, Icons.calendar_month_outlined, 'Daily allowance', widget.ca(dailyAllowance), Colors.deepPurple),
            const SizedBox(height: 8),
            _simRow(context, Icons.trending_up_rounded, 'Projected monthly spend', widget.ca(simMonthlySpend),
                simMonthlySpend > target ? Colors.red : Colors.teal),
            if (isReducing) ...[
              const SizedBox(height: 8),
              _simRow(context, Icons.savings_outlined, 'Monthly saving vs now', widget.ca(saving.abs()), Colors.teal),
              const SizedBox(height: 8),
              _simRow(context, Icons.auto_awesome_rounded, 'Yearly saving', widget.ca(yearlySaving.abs()), Colors.green),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _simRow(BuildContext context, IconData icon, String label, String value, Color color) => Row(children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 8),
    Text(label, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
    const Spacer(),
    Text(value, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: color)),
  ]);

  Widget _buildAllocationStrip(BuildContext context) {
    final overall = _limitFor('overall');
    if (overall <= 0) return const SizedBox.shrink();

    final quick   = _limitFor('quick');
    final secure  = _limitFor('secure');
    final group   = _limitFor('group');
    final alloc   = quick + secure + group;
    final unalloc = (overall - alloc).clamp(0.0, overall);
    final anySet  = alloc > 0;

    final segments = <(String, double, Color)>[
      ('Quick',   quick,   Colors.amber.shade700),
      ('Secure',  secure,  Colors.teal),
      ('Group',   group,   Colors.deepPurple),
      ('Free',    unalloc, AppThemeColors.border(context)),
    ].where((s) => s.$2 > 0).toList();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pie_chart_outline_rounded, size: 14, color: AppColors.cyan),
          const SizedBox(width: 6),
          Text('Overall Cap Allocation',
              style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const Spacer(),
          Text(anySet
              ? '₹${alloc.toStringAsFixed(0)} / ₹${overall.toStringAsFixed(0)}'
              : 'Nothing allocated yet',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Row(
            children: segments.map((s) => Expanded(
              flex: (s.$2 * 1000 ~/ overall).clamp(1, 1000),
              child: Container(
                height: 10,
                color: s.$1 == 'Free' ? AppThemeColors.border(context) : s.$3,
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 4, children: segments.map((s) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 9, height: 9,
                decoration: BoxDecoration(
                    color: s.$1 == 'Free' ? AppThemeColors.border(context) : s.$3,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text('${s.$1}: ₹${s.$2.toStringAsFixed(0)}',
                style: TextStyle(fontSize: context.sp(10),
                    color: s.$1 == 'Free'
                        ? AppThemeColors.secondaryText(context)
                        : AppThemeColors.primaryText(context))),
          ],
        )).toList()),
      ]),
    );
  }

  Widget _buildTipsRow(BuildContext context) {
    final tips = [
      (Icons.rocket_launch_outlined,    Colors.teal,       'Start Small',        'Set a modest limit first. Adjust it after seeing your actual spend.'),
      (Icons.event_repeat_rounded,      Colors.deepPurple, 'Review Weekly',      'Spending 10 min weekly reviewing your budget saves money long-term.'),
      (Icons.account_balance_outlined,  AppColors.cyan,    'Use Overall Cap',    'The Overall cap protects you even if individual limits are unset.'),
      (Icons.trending_down_rounded,     Colors.orange,     'Lower Gradually',    'Reduce limits by 5-10% each month to curb spending without shock.'),
    ];
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final tip = tips[i];
          return Container(
            width: 180,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tip.$2.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tip.$2.withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(tip.$1, color: tip.$2, size: 20),
              const SizedBox(height: 6),
              Text(tip.$3, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 4),
              Text(tip.$4, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context), height: 1.3)),
            ]),
          );
        },
      ),
    );
  }

  Widget _progressBar(BuildContext context, double pct) => Stack(children: [
    Container(height: 8, decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(4))),
    FractionallySizedBox(
      widthFactor: pct.clamp(0.0, 1.0),
      child: Container(height: 8, decoration: BoxDecoration(
        gradient: LinearGradient(colors: [_progressColor(pct).withValues(alpha: 0.7), _progressColor(pct)]),
        borderRadius: BorderRadius.circular(4),
      )),
    ),
  ]);

  Widget _chip(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold, color: color)),
  );

  Widget _iconBtn(BuildContext context, IconData icon, Color bg, VoidCallback onTap, {Color? iconColor}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: iconColor ?? bg),
        ),
      );

  Widget _legend2(BuildContext context, Color color, String label) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
  ]);

  BoxDecoration _cardBox(BuildContext context) => BoxDecoration(
    color: AppThemeColors.cardBg(context),
    borderRadius: BorderRadius.circular(20),
    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
  );
}
