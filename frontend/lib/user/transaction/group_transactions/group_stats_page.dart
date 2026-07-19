import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class GroupStatsPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;

  const GroupStatsPage({super.key, required this.groupId, required this.groupTitle});

  @override
  State<GroupStatsPage> createState() => _GroupStatsPageState();
}

class _GroupStatsPageState extends State<GroupStatsPage> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/group-transactions/${widget.groupId}/stats');
      if (res.statusCode == 200) {
        if (mounted) setState(() => _stats = jsonDecode(res.body) as Map<String, dynamic>);
      } else {
        if (mounted) setState(() => _error = (jsonDecode(res.body)['error'] ?? 'Failed to load stats').toString());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _categoryColors = <String, Color>{
    'food': Color(0xFFFF7043),
    'transport': Color(0xFF42A5F5),
    'entertainment': Color(0xFFAB47BC),
    'shopping': Color(0xFFFFCA28),
    'healthcare': Color(0xFF26A69A),
    'education': Color(0xFF5C6BC0),
    'utilities': Color(0xFF78909C),
    'rent': Color(0xFF8D6E63),
    'business': Color(0xFF29B6F6),
    'travel': Color(0xFF66BB6A),
    'personal': Color(0xFFEC407A),
    'other': Color(0xFFBDBDBD),
  };

  Color _catColor(String cat) => _categoryColors[cat] ?? const Color(0xFFBDBDBD);

  String _fmtAmount(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0;
    if (n >= 100000) return '₹${(n / 100000).toStringAsFixed(1)}L';
    if (n >= 1000) return '₹${(n / 1000).toStringAsFixed(1)}K';
    return '₹${n.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(4, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('group_stats_title'),
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text(widget.groupTitle,
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    onPressed: _load,
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline, size: 48, color: AppThemeColors.mutedText(context)),
                              const SizedBox(height: 12),
                              Text(_error!, style: TextStyle(color: AppThemeColors.secondaryText(context))),
                              const SizedBox(height: 12),
                              TextButton(onPressed: _load, child: Text(t('retry'))),
                            ],
                          ),
                        )
                      : _buildContent(context, t, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, String Function(String) t, bool isDark) {
    final s = _stats!;
    final totalExpenses = (s['totalExpenses'] as num?)?.toDouble() ?? 0;
    final settledExpenses = (s['settledExpenses'] as num?)?.toDouble() ?? 0;
    final pendingExpenses = (s['pendingExpenses'] as num?)?.toDouble() ?? 0;
    final totalCount = (s['totalExpenseCount'] as num?)?.toInt() ?? 0;
    final categories = List<Map<String, dynamic>>.from(s['categoryBreakdown'] ?? []);
    final monthlyAmounts = List<double>.from(
      (s['monthlyAmounts'] as List? ?? []).map((v) => (v as num).toDouble()),
    );
    final months = List<String>.from(s['months'] ?? []);
    final memberBalances = List<Map<String, dynamic>>.from(s['memberBalances'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              _statCard(context, t('total_expenses_label'), _fmtAmount(totalExpenses),
                  Icons.receipt_long_rounded, const Color(0xFF1565C0), '$totalCount ${t('expenses_label')}'),
              const SizedBox(width: 10),
              _statCard(context, t('settled_label'), _fmtAmount(settledExpenses),
                  Icons.check_circle_outline_rounded, Colors.green, ''),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _statCard(context, t('pending'), _fmtAmount(pendingExpenses),
                  Icons.pending_outlined, Colors.orange, ''),
              const SizedBox(width: 10),
              _statCard(context, t('members_label'), '${memberBalances.length}',
                  Icons.people_alt_rounded, AppColors.cyan, ''),
            ],
          ),
          const SizedBox(height: 24),

          // Category breakdown
          if (categories.isNotEmpty) ...[
            Text(t('category_breakdown_label'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: PieChart(
                      PieChartData(
                        sections: categories.map((c) {
                          final cat = c['category']?.toString() ?? 'other';
                          final amt = (c['amount'] as num?)?.toDouble() ?? 0;
                          final pct = totalExpenses > 0 ? amt / totalExpenses * 100 : 0;
                          return PieChartSectionData(
                            value: amt,
                            color: _catColor(cat),
                            title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '',
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            radius: 70,
                          );
                        }).toList(),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: categories.map((c) {
                      final cat = c['category']?.toString() ?? 'other';
                      final amt = (c['amount'] as num?)?.toDouble() ?? 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(cat), shape: BoxShape.circle)),
                          const SizedBox(width: 4),
                          Text('${cat[0].toUpperCase()}${cat.substring(1)}: ${_fmtAmount(amt)}',
                              style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Monthly trend
          if (monthlyAmounts.any((v) => v > 0)) ...[
            Text(t('monthly_trend_label'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    barGroups: List.generate(monthlyAmounts.length, (i) => BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: monthlyAmounts[i],
                          color: const Color(0xFF1565C0),
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    )),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= months.length) return const SizedBox();
                            final label = months[idx].substring(0, 3);
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(label, style: TextStyle(fontSize: 9, color: AppThemeColors.mutedText(context))),
                            );
                          },
                          reservedSize: 22,
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) => Text(_fmtAmount(v),
                              style: TextStyle(fontSize: 9, color: AppThemeColors.mutedText(context))),
                          reservedSize: 38,
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      getDrawingHorizontalLine: (_) => FlLine(color: AppThemeColors.divider(context), strokeWidth: 0.5),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Member balances
          if (memberBalances.isNotEmpty) ...[
            Text(t('member_balances_label'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Column(
                children: memberBalances.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  final bal = (m['balance'] as num?)?.toDouble() ?? 0;
                  final name = m['name']?.toString() ?? m['email']?.toString() ?? '-';
                  final isLast = idx == memberBalances.length - 1;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                      color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text(m['email']?.toString() ?? '', style: TextStyle(fontSize: 11,
                                      color: AppThemeColors.mutedText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: bal > 0 ? Colors.green.withValues(alpha: 0.1)
                                    : bal < 0 ? Colors.red.withValues(alpha: 0.1)
                                    : AppThemeColors.surfaceBg(context),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                bal > 0 ? '+${_fmtAmount(bal)}' : _fmtAmount(bal),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: bal > 0 ? Colors.green : bal < 0 ? Colors.red : AppThemeColors.mutedText(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast) Divider(height: 1, color: AppThemeColors.divider(context)),
                    ],
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _statCard(BuildContext context, String label, String value, IconData icon, Color color, String sub) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
            ],
          ],
        ),
      ),
    );
  }
}
