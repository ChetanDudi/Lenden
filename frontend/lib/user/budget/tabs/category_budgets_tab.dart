import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class CategoryBudgetsTab extends StatefulWidget {
  final Map<String, dynamic>? budget;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? recommendations;
  final String Function(num?) ca;
  final Future<void> Function(String key, String value) onSaveCategoryBudget;

  const CategoryBudgetsTab({
    super.key,
    required this.budget,
    required this.status,
    required this.recommendations,
    required this.ca,
    required this.onSaveCategoryBudget,
  });

  @override
  State<CategoryBudgetsTab> createState() => _CategoryBudgetsTabState();
}

class _CategoryBudgetsTabState extends State<CategoryBudgetsTab> {
  bool _saving = false;

  static const _keys   = ['food', 'shopping', 'entertainment', 'fuel', 'travel', 'medical', 'education', 'other'];
  static const _labels = ['Food', 'Shopping', 'Entertainment', 'Fuel', 'Travel', 'Medical', 'Education', 'Other'];
  static const _icons  = [Icons.restaurant_outlined, Icons.shopping_bag_outlined, Icons.movie_outlined,
    Icons.local_gas_station_outlined, Icons.flight_outlined, Icons.medical_services_outlined,
    Icons.school_outlined, Icons.category_outlined];
  static final _colors = [Colors.orange, Colors.pink, Colors.deepPurple, Colors.blueGrey,
    Colors.teal, Colors.red, Colors.indigo, AppColors.cyan];

  late final Map<String, TextEditingController> _ctrl;
  final Map<String, bool> _editing = {};

  @override
  void initState() {
    super.initState();
    _ctrl = {for (final k in _keys) k: TextEditingController()};
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) { c.dispose(); }
    super.dispose();
  }

  double _limitFor(String key) =>
      (widget.budget?['categoryLimits']?[key] as num? ?? 0).toDouble();
  double _spentFor(String key) =>
      (widget.status?['categorySpent']?[key] as num? ?? 0).toDouble();

  Color _progressColor(double pct) {
    if (pct >= 1.0)  return Colors.red;
    if (pct >= 0.85) return Colors.orange;
    return Colors.teal;
  }

  Future<void> _save(String key) async {
    setState(() => _saving = true);
    await widget.onSaveCategoryBudget(key, _ctrl[key]!.text);
    if (mounted) setState(() { _saving = false; _editing[key] = false; });
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('budget_planning')) {
      return const PremiumTabGate(
        featureName: 'Category Budgets',
        description: 'Set individual spending limits for Food, Shopping, Travel and more.',
        icon: Icons.category_outlined,
        accentColor: Colors.teal,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(children: [
        _buildCategoryGrid(context),
        const SizedBox(height: 12),
        _buildUntrackedSummary(context),
        const SizedBox(height: 16),
        if (widget.recommendations != null) _buildRecommendations(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildCategoryGrid(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('Category Budgets',
            style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const Spacer(),
        Text('tap to set limit', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
      ]),
      const SizedBox(height: 10),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, childAspectRatio: 1.7, crossAxisSpacing: 10, mainAxisSpacing: 10,
        ),
        itemCount: _keys.length,
        itemBuilder: (_, i) => _buildCategoryCard(context, i),
      ),
    ]);
  }

  Widget _buildCategoryCard(BuildContext context, int i) {
    final key      = _keys[i];
    final label    = _labels[i];
    final icon     = _icons[i];
    final color    = _colors[i];
    final limit    = _limitFor(key);
    final spent    = _spentFor(key);
    final hasLimit = limit > 0;
    final pct      = hasLimit ? (spent / limit).clamp(0.0, 1.1) : 0.0;
    final isEditing = _editing[key] ?? false;

    return GestureDetector(
      onTap: () {
        if (!isEditing) {
          _ctrl[key]!.text = hasLimit ? limit.toStringAsFixed(0) : '';
          setState(() => _editing[key] = true);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hasLimit && pct >= 1.0 ? Colors.red.withValues(alpha: 0.5) : color.withValues(alpha: 0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: isEditing
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextField(
                  controller: _ctrl[key],
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  autofocus: true,
                  style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    hintText: 'Limit', prefixText: '₹ ', isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: color, width: 2)),
                  ),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _saving
                      ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
                      : _iconBtn(context, Icons.check, color, () => _save(key)),
                  const SizedBox(width: 6),
                  _iconBtn(context, Icons.close, AppThemeColors.border(context), () => setState(() => _editing[key] = false)),
                ]),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(icon, color: color, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(label, style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
                  if (hasLimit && pct >= 1.0) const Icon(Icons.warning_amber_rounded, size: 12, color: Colors.red),
                ]),
                const SizedBox(height: 6),
                if (hasLimit) ...[
                  Text(widget.ca(spent), style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.w700, color: _progressColor(pct))),
                  const SizedBox(height: 4),
                  Stack(children: [
                    Container(height: 4, decoration: BoxDecoration(color: AppThemeColors.border(context), borderRadius: BorderRadius.circular(2))),
                    FractionallySizedBox(
                      widthFactor: pct.clamp(0.0, 1.0),
                      child: Container(height: 4, decoration: BoxDecoration(color: _progressColor(pct), borderRadius: BorderRadius.circular(2))),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text('of ${widget.ca(limit)}', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
                ] else
                  Text(spent > 0 ? 'Spent: ${widget.ca(spent)}\nTap to set limit' : 'Tap to set limit',
                      style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context), height: 1.4)),
              ]),
      ),
    );
  }

  Widget _buildUntrackedSummary(BuildContext context) {
    // Total category spending across all keys
    final totalCatSpent = _keys.fold(0.0, (s, k) => s + _spentFor(k));
    if (totalCatSpent <= 0) return const SizedBox.shrink();

    // Spending in categories that have NO limit set
    double untrackedSpent = 0;
    final untrackedCats = <String>[];
    for (int i = 0; i < _keys.length; i++) {
      if (_limitFor(_keys[i]) <= 0 && _spentFor(_keys[i]) > 0) {
        untrackedSpent += _spentFor(_keys[i]);
        untrackedCats.add(_labels[i]);
      }
    }
    if (untrackedSpent <= 0) return const SizedBox.shrink();

    final pct = totalCatSpent > 0 ? untrackedSpent / totalCatSpent : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.visibility_off_outlined, size: 16, color: Colors.orange),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Untracked spending: ${widget.ca(untrackedSpent)}',
              style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700)),
          const SizedBox(height: 3),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% of category spending has no limit '
            '(${untrackedCats.join(', ')})',
            style: TextStyle(fontSize: context.sp(10),
                color: AppThemeColors.secondaryText(context)),
          ),
        ])),
      ]),
    );
  }

  Widget _buildRecommendations(BuildContext context) {
    final rec         = widget.recommendations!;
    final recommended = rec['recommended']   as Map? ?? {};
    final avg         = rec['threeMonthAvg'] as Map? ?? {};
    final prev        = rec['prevMonth']     as Map? ?? {};

    final items = [
      ('Quick',  'quick',  prev['quick']  as num?, recommended['quick']  as num?, avg['quick']  as num?),
      ('Secure', 'secure', prev['secure'] as num?, recommended['secure'] as num?, avg['secure'] as num?),
      ('Group',  'group',  prev['group']  as num?, recommended['group']  as num?, avg['group']  as num?),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('AI Recommendations',
            style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text('3-month avg', style: TextStyle(fontSize: context.sp(9), color: AppColors.cyan)),
        ),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
        ),
        child: Column(children: [
          for (final item in items) ...[
            Row(children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(
                    item.$1 == 'Quick'  ? Icons.flash_on_outlined :
                    item.$1 == 'Secure' ? Icons.shield_outlined :
                                          Icons.group_outlined,
                    size: 16, color: Colors.deepPurple)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.$1, style: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                if (item.$3 != null)
                  Text('Last month: ${widget.ca(item.$3)}', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
              ])),
              if (item.$4 != null) Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(widget.ca(item.$4), style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: Colors.teal)),
                Text('suggested', style: TextStyle(fontSize: context.sp(9), color: AppThemeColors.secondaryText(context))),
              ]),
            ]),
            if (item != items.last) Divider(color: AppThemeColors.divider(context), height: 18),
          ],
          if (recommended['overall'] != null) ...[
            Divider(color: AppThemeColors.divider(context), height: 18),
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.cyan),
              const SizedBox(width: 8),
              Expanded(child: Text('Overall recommended', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context)))),
              Text(widget.ca(recommended['overall'] as num), style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppColors.cyan)),
            ]),
          ],
        ]),
      ),
    ]);
  }

  Widget _iconBtn(BuildContext context, IconData icon, Color bg, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: bg),
        ),
      );
}
