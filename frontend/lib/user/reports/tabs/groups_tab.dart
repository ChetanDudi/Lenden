import 'package:flutter/material.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class GroupsTab extends StatelessWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const GroupsTab({super.key, required this.report, required this.ca});

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    final groups = (report!['groupBreakdown'] as List? ?? []).cast<Map<String, dynamic>>();
    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.group_outlined, size: 56, color: AppThemeColors.secondaryText(context)),
            const SizedBox(height: 12),
            Text('No group transactions in this period',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: context.sp(14))),
          ]),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: _buildGroupAnalytics(context, groups),
    );
  }

  Widget _buildGroupAnalytics(BuildContext context, List<Map<String, dynamic>> groups) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Group Analytics',
              style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        ),
        ...List.generate(groups.length, (i) {
          final g       = groups[i];
          final total   = (g['totalExpenses']       as num? ?? 0).toDouble();
          final myShare = (g['yourShare']            as num? ?? 0).toDouble();
          final others  = (g['othersContribution']   as num? ?? 0).toDouble();
          final net     = (g['netBalance']           as num? ?? 0).toDouble();
          final myPct   = total > 0 ? (myShare / total * 100).toStringAsFixed(0) : '0';
          final topCats = (g['topCategories']        as List? ?? []).cast<Map<String, dynamic>>();

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (i > 0) Divider(color: AppThemeColors.divider(context), height: 24),
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.purple.withValues(alpha: 0.8), Colors.deepPurple],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text((g['title'] as String? ?? 'G')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g['title'] as String? ?? '',
                    style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                Text('${g['memberCount']} members',
                    style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (net >= 0 ? Colors.teal : Colors.orange).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  net == 0 ? 'Settled' : (net > 0 ? '+${ca(net)}' : ca(net.abs())),
                  style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold,
                      color: net == 0 ? Colors.teal : (net > 0 ? Colors.teal : Colors.orange)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _groupStatCell(context, 'Total',           ca(total),   Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _groupStatCell(context, 'Your Share ($myPct%)', ca(myShare), Colors.teal)),
              const SizedBox(width: 8),
              Expanded(child: _groupStatCell(context, "Others'",         ca(others),  Colors.purple)),
            ]),
            if (topCats.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 4, children: topCats.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppThemeColors.border(context).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_cap(c['category'] as String? ?? 'other')} · ${ca(c['amount'])}',
                  style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context)),
                ),
              )).toList()),
            ],
          ]);
        }),
      ]),
    );
  }

  Widget _groupStatCell(BuildContext context, String label, String value, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context)), textAlign: TextAlign.center),
        ]),
      );

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
