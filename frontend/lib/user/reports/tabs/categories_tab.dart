import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../l10n/app_localizations.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class CategoriesTab extends StatefulWidget {
  final Map<String, dynamic>? report;
  final String Function(num?) ca;

  const CategoriesTab({super.key, required this.report, required this.ca});

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  final Set<String> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Category Analytics',
        description: 'See how you spend across every category with detailed drill-downs and trends.',
        icon: Icons.category_outlined,
        accentColor: AppColors.cyan,
      );
    }
    if (widget.report == null) {
      return Center(child: Text('No data for this period',
          style: TextStyle(color: AppThemeColors.secondaryText(context))));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: _buildCategoryBreakdown(context),
    );
  }

  Widget _buildCategoryBreakdown(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final cats       = (widget.report!['categories'] as List? ?? []).cast<Map<String, dynamic>>();
    final subCatMap  = (widget.report!['subCategories'] as Map?) ?? {};

    if (cats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No category data for this period',
              style: TextStyle(color: AppThemeColors.secondaryText(context))),
        ),
      );
    }
    final maxAmt = (cats.first['amount'] as num? ?? 1).toDouble();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(t('category_breakdown_title'),
              style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
        ),
        Text('Tap any category to see subcategories',
            style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 12),
        for (int i = 0; i < cats.length; i++) ...[
          _catRow(context, cats[i], i, maxAmt, subCatMap),
          if (i < cats.length - 1) const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _catRow(BuildContext context, Map<String, dynamic> cat, int idx,
      double maxAmt, Map subCatMap) {
    final catKey      = (cat['category'] ?? 'other') as String;
    final amt         = (cat['amount'] as num? ?? 0).toDouble();
    final pct         = maxAmt > 0 ? amt / maxAmt : 0.0;
    final pctOfTotal  = cat['percentage'] as int? ?? 0;
    final trend       = cat['trend'] as int?;
    final name        = catKey.capitalize();
    final color       = _catColor(idx);
    final isExpanded  = _expanded.contains(catKey);

    // Subcategories from backend subCategories map
    final rawSubs = subCatMap[catKey];
    List<Map<String, dynamic>> subs = [];
    if (rawSubs is Map) {
      subs = rawSubs.entries
          .where((e) => (e.value as num? ?? 0) > 0)
          .map((e) => {'name': e.key as String, 'amount': e.value})
          .toList()
        ..sort((a, b) => ((b['amount'] as num)).compareTo((a['amount'] as num)));
    }
    final hasSubs = subs.isNotEmpty;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Main category row — tappable
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: hasSubs
            ? () => setState(() => isExpanded ? _expanded.remove(catKey) : _expanded.add(catKey))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(_catIcon(catKey), color: color, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(name, style: TextStyle(fontSize: context.sp(12),
                    fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context))),
                if (hasSubs) ...[
                  const SizedBox(width: 4),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 14, color: AppThemeColors.secondaryText(context)),
                ],
              ]),
              Text('$pctOfTotal% of total · ${cat['count']} txns',
                  style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(widget.ca(amt), style: TextStyle(fontSize: context.sp(12),
                  fontWeight: FontWeight.bold, color: color)),
              if (trend != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(trend > 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 10, color: trend > 0 ? Colors.red : Colors.teal),
                  Text('${trend.abs()}%', style: TextStyle(fontSize: context.sp(9),
                      color: trend > 0 ? Colors.red : Colors.teal, fontWeight: FontWeight.w600)),
                ]),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct.clamp(0.0, 1.0),
          minHeight: 5,
          backgroundColor: AppThemeColors.border(context),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
      // Subcategory expansion
      if (hasSubs && isExpanded)
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, left: 10),
            child: Column(children: subs.map((s) {
              final sAmt   = (s['amount'] as num? ?? 0).toDouble();
              final sPct   = amt > 0 ? (sAmt / amt).clamp(0.0, 1.0) : 0.0;
              final sColor = color.withValues(alpha: 0.65);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    width: 3, height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(s['name'] as String,
                          style: TextStyle(fontSize: context.sp(11),
                              color: AppThemeColors.primaryText(context)))),
                      Text(widget.ca(sAmt), style: TextStyle(
                          fontSize: context.sp(11), fontWeight: FontWeight.w600, color: sColor)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: sPct,
                        minHeight: 3,
                        backgroundColor: AppThemeColors.border(context),
                        valueColor: AlwaysStoppedAnimation(sColor),
                      ),
                    ),
                  ])),
                ]),
              );
            }).toList()),
          ),
        ),
    ]);
  }

  Color _catColor(int idx) {
    const colors = [
      AppColors.cyan, Colors.orange, Colors.teal, Colors.deepPurple,
      Colors.red, Colors.indigo, Colors.green, Colors.pink, Colors.brown,
    ];
    return colors[idx % colors.length];
  }

  IconData _catIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'food':          return Icons.restaurant_outlined;
      case 'transport':     return Icons.directions_car_outlined;
      case 'accommodation': return Icons.hotel_outlined;
      case 'entertainment': return Icons.movie_outlined;
      case 'shopping':      return Icons.shopping_bag_outlined;
      case 'utilities':     return Icons.bolt_outlined;
      case 'medical':       return Icons.medical_services_outlined;
      case 'education':     return Icons.school_outlined;
      default:              return Icons.category_outlined;
    }
  }
}

extension _CapExt on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
