import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';
import '../../../widgets/calendar_heatmap.dart';

class ChartsTab extends StatefulWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const ChartsTab({super.key, required this.report, required this.ca});

  @override
  State<ChartsTab> createState() => _ChartsTabState();
}

class _ChartsTabState extends State<ChartsTab> {
  bool _showAllCashFlow = false;

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('reports')) {
      return const PremiumTabGate(
        featureName: 'Advanced Charts',
        description: 'GitHub-style spending heatmap, cash-flow timeline, and visual drill-downs.',
        icon: Icons.bar_chart_rounded,
        accentColor: AppColors.cyan,
      );
    }
    if (widget.report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildHeatmapCard(context),
        const SizedBox(height: 20),
        _buildCashFlowTimeline(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildHeatmapCard(BuildContext context) {
    final daily = (widget.report!['dailySpending'] as Map?)?.map(
      (k, v) => MapEntry(k as String, v),
    ) ?? <String, dynamic>{};

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Spending Heatmap',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        Text('Last 13 weeks — tap any day for details',
            style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CalendarHeatmap(
            dailySpending: daily,
            formatAmount: widget.ca,
          ),
        ),
      ]),
    );
  }

  Widget _buildCashFlowTimeline(BuildContext context) {
    final cashFlow = (widget.report!['cashFlow'] as List? ?? []);
    if (cashFlow.isEmpty) return const SizedBox.shrink();

    final items = _showAllCashFlow ? cashFlow : cashFlow.take(10).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Cash-Flow Timeline',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        Text('Running balance across your transactions',
            style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 14),
        ...items.asMap().entries.map((entry) {
          final i = entry.key;
          final e = entry.value as Map<String, dynamic>;
          final delta   = (e['delta'] as num?)?.toDouble() ?? 0;
          final balance = (e['balance'] as num?)?.toDouble() ?? 0;
          final isPositive = delta >= 0;
          final color = isPositive ? Colors.green : Colors.red;
          final isLast = i == items.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: color.withValues(alpha: 0.4)),
                        ),
                        child: Icon(isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            size: 14, color: color),
                      ),
                      if (!isLast)
                        Expanded(child: Center(
                          child: Container(width: 2, color: AppThemeColors.border(context)),
                        )),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(e['label'] as String? ?? e['category'] as String? ?? '—',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: context.sp(13),
                                      color: AppThemeColors.primaryText(context)),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                            Text(
                              delta == 0 ? widget.ca(0) : '${isPositive ? '+' : '−'}${widget.ca(delta.abs())}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.sp(13), color: color),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _fmtDate(e['date']?.toString() ?? ''),
                              style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context)),
                            ),
                            const Spacer(),
                            Text(
                              'Balance: ${widget.ca(balance.abs())}',
                              style: TextStyle(fontSize: context.sp(10),
                                  color: balance >= 0 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (cashFlow.length > 10)
          TextButton.icon(
            onPressed: () => setState(() => _showAllCashFlow = !_showAllCashFlow),
            icon: Icon(_showAllCashFlow ? Icons.expand_less : Icons.expand_more, color: AppColors.cyan),
            label: Text(_showAllCashFlow ? 'Show less' : 'Show all ${cashFlow.length} events',
                style: const TextStyle(color: AppColors.cyan)),
          ),
      ]),
    );
  }

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return iso.split('T')[0]; }
  }
}
