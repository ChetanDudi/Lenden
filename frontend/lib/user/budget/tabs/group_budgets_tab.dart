import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';
import '../../../widgets/app_colors.dart';

class GroupBudgetsTab extends StatefulWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? budget;
  final String Function(num?) ca;
  final Future<void> Function(String groupId, double? limit) onSaveGroupLimit;

  const GroupBudgetsTab({
    super.key,
    required this.status,
    required this.budget,
    required this.ca,
    required this.onSaveGroupLimit,
  });

  @override
  State<GroupBudgetsTab> createState() => _GroupBudgetsTabState();
}

class _GroupBudgetsTabState extends State<GroupBudgetsTab> {
  // groupId → TextEditingController while editing
  final Map<String, TextEditingController> _editing = {};
  final Map<String, String?> _errors = {};
  final Map<String, bool> _saving = {};

  @override
  void dispose() {
    for (final c in _editing.values) {
      c.dispose();
    }
    super.dispose();
  }

  double get _overallGroupLimit =>
      (widget.budget?['limits']?['group'] as num?)?.toDouble() ?? 0;

  double _otherLimitsSum(String excludeId, List<Map<String, dynamic>> groups) {
    return groups.fold<double>(0, (sum, g) {
      if ((g['id'] as String?) == excludeId) return sum;
      return sum + ((g['budget'] as num?)?.toDouble() ?? 0);
    });
  }

  void _startEdit(String groupId, double currentLimit) {
    setState(() {
      _editing[groupId] = TextEditingController(
        text: currentLimit > 0 ? currentLimit.toStringAsFixed(0) : '',
      );
      _errors[groupId] = null;
    });
  }

  void _cancelEdit(String groupId) {
    setState(() {
      _editing[groupId]?.dispose();
      _editing.remove(groupId);
      _errors.remove(groupId);
    });
  }

  Future<void> _saveEdit(
      String groupId, List<Map<String, dynamic>> groups) async {
    final text = _editing[groupId]?.text.trim() ?? '';
    final parsed = text.isEmpty ? null : double.tryParse(text);

    if (text.isNotEmpty && parsed == null) {
      setState(() => _errors[groupId] = 'Enter a valid number');
      return;
    }
    if (parsed != null && parsed < 0) {
      setState(() => _errors[groupId] = 'Limit must be positive');
      return;
    }

    // Validate against overall group limit
    if (parsed != null && _overallGroupLimit > 0) {
      final others = _otherLimitsSum(groupId, groups);
      if (others + parsed > _overallGroupLimit) {
        final remaining = (_overallGroupLimit - others).clamp(0, double.infinity);
        setState(() => _errors[groupId] =
            'Exceeds overall group limit. Max available: ${widget.ca(remaining)}');
        return;
      }
    }

    setState(() {
      _saving[groupId] = true;
      _errors[groupId] = null;
    });

    try {
      await widget.onSaveGroupLimit(groupId, parsed);
      if (mounted) {
        _editing[groupId]?.dispose();
        setState(() {
          _editing.remove(groupId);
          _saving.remove(groupId);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errors[groupId] = e.toString().replaceFirst('Exception: ', '');
          _saving[groupId] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('budget_planning')) {
      return const PremiumTabGate(
        featureName: 'Group Budgets',
        description:
            'Track spending limits across all your groups and get alerted before you overspend.',
        icon: Icons.group_outlined,
        accentColor: Colors.deepPurple,
      );
    }

    final groups =
        (widget.status?['groupSpending'] as List? ?? []).cast<Map<String, dynamic>>();
    final overallGroupLimit =
        (widget.status?['limits']?['group'] as num?)?.toDouble();
    final totalGroupSpent =
        (widget.status?['spent']?['group'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildHeader(context, groups, totalGroupSpent, overallGroupLimit),
        const SizedBox(height: 14),
        if (groups.isEmpty)
          _buildEmptyState(context)
        else ...[
          for (final g in groups) ...[
            _buildGroupCard(context, g, groups),
            const SizedBox(height: 12),
          ],
        ],
        const SizedBox(height: 16),
        if (overallGroupLimit == null) _buildSetBudgetPrompt(context),
        const SizedBox(height: 12),
        _buildInfoCard(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildHeader(BuildContext context, List<Map<String, dynamic>> groups,
      double totalSpent, double? limit) {
    if (groups.isEmpty) {
      return Text('Group Budgets',
          style: TextStyle(
              fontSize: context.sp(17),
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context)));
    }
    final totalBudget = limit ??
        groups.fold<double>(
            0, (s, g) => s + ((g['budget'] as num?)?.toDouble() ?? 0));
    final overallPct =
        totalBudget > 0 ? (totalSpent / totalBudget).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withValues(alpha: 0.12),
            Colors.indigo.withValues(alpha: 0.07)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: Colors.deepPurple.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: limit != null ? overallPct : null,
                strokeWidth: 6,
                backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  limit != null && overallPct >= 1.0
                      ? Colors.red
                      : limit != null && overallPct >= 0.85
                          ? Colors.orange
                          : Colors.deepPurple,
                ),
              ),
              Icon(Icons.group_outlined,
                  size: 22,
                  color: limit != null && overallPct >= 1.0
                      ? Colors.red
                      : Colors.deepPurple),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Group Spending',
                style: TextStyle(
                    fontSize: context.sp(13),
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 3),
            Text(
              limit != null
                  ? '${widget.ca(totalSpent)} of ${widget.ca(limit)} across ${groups.length} group${groups.length > 1 ? 's' : ''}'
                  : '${widget.ca(totalSpent)} total across ${groups.length} group${groups.length > 1 ? 's' : ''}',
              style: TextStyle(
                  fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context)),
            ),
            if (limit != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: overallPct,
                  minHeight: 6,
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overallPct >= 1.0
                        ? Colors.red
                        : overallPct >= 0.85
                            ? Colors.orange
                            : Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                  '${(overallPct * 100).toStringAsFixed(0)}% of overall group budget used',
                  style: TextStyle(
                      fontSize: context.sp(10),
                      color: AppThemeColors.secondaryText(context))),
            ],
          ])),
        ]),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            _statChip(
                context, '${groups.length}', 'Groups', Colors.deepPurple),
            const SizedBox(width: 8),
            _statChip(context, widget.ca(totalSpent), 'Your share',
                Colors.indigo),
            const SizedBox(width: 8),
            _statChip(
                context,
                '${groups.where((g) => (g['expenseCount'] as int? ?? 0) > 0).length}',
                'Active',
                Colors.teal),
          ]),
        ],
      ]),
    );
  }

  Widget _statChip(
          BuildContext context, String value, String label, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: context.sp(12),
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: context.sp(9),
                  color: AppThemeColors.secondaryText(context))),
        ]),
      );

  Color _colorFromHex(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.deepPurple;
    }
  }

  Widget _buildGroupCard(BuildContext context, Map<String, dynamic> g,
      List<Map<String, dynamic>> allGroups) {
    final groupId = g['id'] as String? ?? '';
    final name = g['name'] as String? ?? 'Group';
    final colorHex = g['color'] as String? ?? '#2196F3';
    final budget = (g['budget'] as num?)?.toDouble() ?? 0;
    final spent = (g['spent'] as num?)?.toDouble() ?? 0;
    final members = (g['memberCount'] as num?)?.toInt() ?? 0;
    final expCount = (g['expenseCount'] as num?)?.toInt() ?? 0;
    final color = _colorFromHex(colorHex);
    final pct = budget > 0 ? (spent / budget).clamp(0.0, 1.1) : 0.0;
    final hasLimit = budget > 0;
    final isEditing = _editing.containsKey(groupId);
    final isSaving = _saving[groupId] == true;
    final errorText = _errors[groupId];

    Color progressColor() {
      if (pct >= 1.0) return Colors.red;
      if (pct >= 0.85) return Colors.orange;
      return color;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: hasLimit && pct >= 1.0
                ? Colors.red.withValues(alpha: 0.35)
                : color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                style: TextStyle(
                    fontSize: context.sp(17),
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                style: TextStyle(
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            Text(
                '$members member${members != 1 ? 's' : ''} · $expCount expense${expCount != 1 ? 's' : ''} this month',
                style: TextStyle(
                    fontSize: context.sp(10),
                    color: AppThemeColors.secondaryText(context))),
          ])),
          if (!isEditing) ...[
            if (hasLimit && pct >= 1.0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Over budget',
                    style: TextStyle(
                        fontSize: context.sp(10),
                        color: Colors.red,
                        fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 6),
            // Edit button
            if (groupId.isNotEmpty)
              InkWell(
                onTap: () => _startEdit(groupId, budget),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.edit_outlined, size: 12, color: color),
                    const SizedBox(width: 4),
                    Text('Limit',
                        style: TextStyle(
                            fontSize: context.sp(10),
                            color: color,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ],
        ]),

        const SizedBox(height: 12),

        // Spending / progress
        if (!isEditing) ...[
          if (hasLimit) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.ca(spent),
                  style: TextStyle(
                      fontSize: context.sp(14),
                      fontWeight: FontWeight.bold,
                      color: progressColor())),
              Text('of ${widget.ca(budget)}',
                  style: TextStyle(
                      fontSize: context.sp(11),
                      color: AppThemeColors.secondaryText(context))),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: AppThemeColors.border(context),
                valueColor:
                    AlwaysStoppedAnimation<Color>(progressColor()),
              ),
            ),
            const SizedBox(height: 4),
            Text('${(pct * 100).toStringAsFixed(1)}% of group budget used',
                style: TextStyle(
                    fontSize: context.sp(10),
                    color: AppThemeColors.secondaryText(context))),
          ] else ...[
            Row(children: [
              Icon(Icons.bar_chart_rounded, size: 14, color: color),
              const SizedBox(width: 5),
              Text('Your share: ${widget.ca(spent)}  ·  No limit set',
                  style: TextStyle(
                      fontSize: context.sp(11),
                      color: AppThemeColors.secondaryText(context))),
            ]),
          ],
        ] else ...[
          // Inline edit UI
          _buildEditSection(context, groupId, color, allGroups, isSaving, errorText),
        ],
      ]),
    );
  }

  Widget _buildEditSection(
    BuildContext context,
    String groupId,
    Color color,
    List<Map<String, dynamic>> allGroups,
    bool isSaving,
    String? errorText,
  ) {
    final overallLimit = _overallGroupLimit;
    final others = _otherLimitsSum(groupId, allGroups);
    final remaining = overallLimit > 0 ? (overallLimit - others) : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (remaining != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Overall group limit: ${widget.ca(overallLimit)}  ·  Available for this group: ${widget.ca(remaining.clamp(0, double.infinity))}',
            style: TextStyle(
                fontSize: context.sp(10),
                color: AppColors.cyan,
                fontWeight: FontWeight.w500),
          ),
        ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _editing[groupId],
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
            ],
            style: TextStyle(
                fontSize: context.sp(14),
                color: AppThemeColors.primaryText(context)),
            decoration: InputDecoration(
              prefixText: '₹ ',
              prefixStyle: TextStyle(
                  fontSize: context.sp(14),
                  color: AppThemeColors.secondaryText(context)),
              hintText: 'Enter limit (leave blank to remove)',
              hintStyle: TextStyle(
                  fontSize: context.sp(12),
                  color: AppThemeColors.secondaryText(context)),
              errorText: errorText,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: color.withValues(alpha: 0.4))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: color, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        isSaving
            ? SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color))
            : IconButton(
                onPressed: () => _saveEdit(groupId, allGroups),
                icon: const Icon(Icons.check_rounded),
                color: Colors.teal,
                style: IconButton.styleFrom(
                    backgroundColor: Colors.teal.withValues(alpha: 0.1)),
              ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: () => _cancelEdit(groupId),
          icon: const Icon(Icons.close_rounded),
          color: Colors.red,
          style: IconButton.styleFrom(
              backgroundColor: Colors.red.withValues(alpha: 0.08)),
        ),
      ]),
    ]);
  }

  Widget _buildSetBudgetPrompt(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
        ),
        child:
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline_rounded,
              size: 16, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text('Set a group budget',
                style: TextStyle(
                    fontSize: context.sp(12),
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple)),
            const SizedBox(height: 3),
            Text(
                'Go to Monthly tab → Group Budget to set an overall spending limit for all group expenses. Then you can set individual limits per group here.',
                style: TextStyle(
                    fontSize: context.sp(11),
                    color: AppThemeColors.secondaryText(context),
                    height: 1.4)),
          ])),
        ]),
      );

  Widget _buildEmptyState(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(children: [
          const Text('👥', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 10),
          Text('No group activity this month',
              style: TextStyle(
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 4),
          Text('Join or create groups, then add expenses to track your share',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context))),
        ]),
      );

  Widget _buildInfoCard(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
        ),
        child:
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.tips_and_updates_outlined,
              size: 16, color: Colors.deepPurple),
          const SizedBox(width: 8),
          Expanded(
              child: Text(
            'Only your share of each group expense is counted here. '
            'Tap "Limit" on any group to set a per-group budget. '
            'The sum of all per-group limits cannot exceed the overall group budget.',
            style: TextStyle(
                fontSize: context.sp(11),
                color: AppThemeColors.secondaryText(context),
                height: 1.5),
          )),
        ]),
      );
}
