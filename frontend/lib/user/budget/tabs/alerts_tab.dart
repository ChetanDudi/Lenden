import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';

class AlertsTab extends StatefulWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? budget;
  final String Function(num?) ca;
  final Future<void> Function(List<int> thresholds)? onSaveThresholds;

  const AlertsTab({
    super.key,
    required this.status,
    required this.ca,
    this.budget,
    this.onSaveThresholds,
  });

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  bool _editingThresholds = false;
  bool _savingThresholds  = false;
  final _t1 = TextEditingController();
  final _t2 = TextEditingController();
  final _t3 = TextEditingController();

  List<int> get _currentThresholds =>
      (widget.budget?['alertThresholds'] as List? ?? [75, 90, 100])
          .map((e) => (e as num).toInt())
          .toList()
        ..sort();

  @override
  void dispose() {
    _t1.dispose();
    _t2.dispose();
    _t3.dispose();
    super.dispose();
  }

  void _startEditing() {
    final t = _currentThresholds;
    _t1.text = t.isNotEmpty ? t[0].toString() : '75';
    _t2.text = t.length > 1 ? t[1].toString() : '90';
    _t3.text = t.length > 2 ? t[2].toString() : '100';
    setState(() => _editingThresholds = true);
  }

  Future<void> _saveThresholds() async {
    final vals = [
      int.tryParse(_t1.text.trim()) ?? 0,
      int.tryParse(_t2.text.trim()) ?? 0,
      int.tryParse(_t3.text.trim()) ?? 0,
    ].where((v) => v > 0 && v <= 100).toSet().toList()..sort();

    if (vals.isEmpty) return;

    // Must have at least one threshold ≤ 100
    setState(() => _savingThresholds = true);
    try {
      await widget.onSaveThresholds?.call(vals);
    } finally {
      if (mounted) setState(() { _savingThresholds = false; _editingThresholds = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final overspent = (widget.status?['overspent'] as List? ?? []).cast<Map<String, dynamic>>();
    final alerts    = (widget.status?['alerts']    as List? ?? []).cast<Map<String, dynamic>>();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildOverspendingSection(context, overspent),
        const SizedBox(height: 16),
        _buildThresholdAlerts(context, alerts),
        const SizedBox(height: 16),
        _buildThresholdEditor(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildOverspendingSection(BuildContext context, List<Map<String, dynamic>> overspent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Overspending Alerts',
          style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      overspent.isEmpty
          ? Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded, color: Colors.teal, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('All budgets on track!',
                      style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  Text("You haven't exceeded any budget limits this month.",
                      style: TextStyle(fontSize: context.sp(11),
                          color: AppThemeColors.secondaryText(context))),
                ])),
              ]),
            )
          : Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text('${overspent.length} budget${overspent.length > 1 ? 's' : ''} exceeded',
                      style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold,
                          color: Colors.red)),
                ]),
                const SizedBox(height: 12),
                for (final o in overspent) ...[
                  _overspentRow(context, o),
                  if (o != overspent.last) const SizedBox(height: 8),
                ],
              ]),
            ),
    ]);
  }

  Widget _overspentRow(BuildContext context, Map<String, dynamic> o) {
    final type  = o['type']  as String? ?? '';
    final limit = (o['limit'] as num?)?.toDouble() ?? 0;
    final spent = (o['spent'] as num?)?.toDouble() ?? 0;
    final over  = spent - limit;
    final label = type.startsWith('cat_')
        ? '${type.substring(4)[0].toUpperCase()}${type.substring(5)} (category)'
        : '${type[0].toUpperCase()}${type.substring(1)}';

    return Row(children: [
      const Icon(Icons.circle, size: 6, color: Colors.red),
      const SizedBox(width: 8),
      Expanded(child: Text('$label: spent ${widget.ca(spent)} vs ${widget.ca(limit)} limit',
          style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.primaryText(context)))),
      Text('+${widget.ca(over)}',
          style: TextStyle(fontSize: context.sp(11), fontWeight: FontWeight.bold, color: Colors.red)),
    ]);
  }

  Widget _buildThresholdAlerts(BuildContext context, List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Threshold Warnings',
          style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 10),
      for (final a in alerts)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_active_outlined, color: Colors.orange, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              '${a['label']} budget at ${a['pct']}% — ${widget.ca(a['spent'])} of ${widget.ca(a['limit'])}',
              style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context)),
            )),
          ]),
        ),
    ]);
  }

  Widget _buildThresholdEditor(BuildContext context) {
    final thresholds = _currentThresholds;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tune_rounded, size: 16, color: AppColors.cyan),
          const SizedBox(width: 8),
          Text('Alert Thresholds',
              style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const Spacer(),
          if (!_editingThresholds)
            GestureDetector(
              onTap: _startEditing,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Edit',
                    style: TextStyle(fontSize: context.sp(11), color: AppColors.cyan,
                        fontWeight: FontWeight.w600)),
              ),
            )
          else ...[
            _savingThresholds
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2))
                : GestureDetector(
                    onTap: _saveThresholds,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('Save',
                          style: TextStyle(fontSize: context.sp(11), color: Colors.teal,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _editingThresholds = false),
              child: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        if (_editingThresholds) ...[
          Text('Set up to 3 alert levels (1–100%):',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 10),
          Row(children: [
            _thresholdField(context, _t1, 'Level 1', Colors.amber),
            const SizedBox(width: 8),
            _thresholdField(context, _t2, 'Level 2', Colors.orange),
            const SizedBox(width: 8),
            _thresholdField(context, _t3, 'Level 3', Colors.red),
          ]),
        ] else ...[
          Text('You are alerted when spending reaches:',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 10),
          Row(children: [
            for (int i = 0; i < thresholds.length; i++) ...[
              _thresholdChip(context, thresholds[i],
                  i == 0 ? Colors.amber : i == 1 ? Colors.orange : Colors.red),
              if (i < thresholds.length - 1) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 10),
          _tip(context, 'Tip',
              'Lower thresholds give earlier warnings. Alerts appear on the Budget → Alerts tab whenever a limit is hit.'),
        ],
      ]),
    );
  }

  Widget _thresholdField(BuildContext context, TextEditingController ctrl,
      String hint, Color color) {
    return Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: color),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context)),
          suffixText: '%',
          suffixStyle: TextStyle(fontSize: context.sp(12), color: color),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          filled: true,
          fillColor: color.withValues(alpha: 0.07),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color.withValues(alpha: 0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: color, width: 2)),
        ),
      ),
    );
  }

  Widget _thresholdChip(BuildContext context, int value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3))),
    child: Text('$value%',
        style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: color)),
  );

  Widget _tip(BuildContext context, String label, String text) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6)),
          child: Text(label,
              style: TextStyle(fontSize: context.sp(10), fontWeight: FontWeight.bold,
                  color: AppColors.cyan)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: context.sp(11),
                color: AppThemeColors.secondaryText(context)))),
      ]);
}
