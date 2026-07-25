import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../session.dart';
import '../../../widgets/premium_gate.dart';

class RecurringTab extends StatefulWidget {
  final Map<String, dynamic>? budget;
  final Map<String, dynamic>? status;
  final String Function(num?) ca;
  final Future<void> Function(Map<String, dynamic>) onSaveRecurring;
  final Future<void> Function(String id) onDeleteRecurring;

  const RecurringTab({
    super.key,
    required this.budget,
    required this.status,
    required this.ca,
    required this.onSaveRecurring,
    required this.onDeleteRecurring,
  });

  @override
  State<RecurringTab> createState() => _RecurringTabState();
}

class _RecurringTabState extends State<RecurringTab> {
  static const _categories = [
    ('Rent / EMI',        Icons.home_outlined,              Colors.indigo),
    ('Subscription',      Icons.subscriptions_outlined,     Colors.purple),
    ('Insurance',         Icons.security_outlined,          Colors.teal),
    ('Loan Repayment',    Icons.account_balance_outlined,   Colors.red),
    ('Utility Bill',      Icons.bolt_outlined,              Colors.orange),
    ('Investment / SIP',  Icons.trending_up_rounded,        Colors.green),
    ('Other Fixed Cost',  Icons.repeat_rounded,             AppColors.cyan),
  ];

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      return const PremiumTabGate(
        featureName: 'Recurring Expenses',
        description: 'Track fixed monthly costs like rent, EMIs, subscriptions and loan repayments.',
        icon: Icons.repeat_rounded,
        accentColor: Colors.indigo,
      );
    }

    final recurring = (widget.status?['recurring'] as List? ?? []).cast<Map<String, dynamic>>();
    final totalFixed = recurring.fold<double>(0, (s, r) => s + ((r['amount'] as num?)?.toDouble() ?? 0));
    final overallLimit = (widget.budget?['limits']?['overall'] as num?)?.toDouble() ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSummaryCard(context, totalFixed, overallLimit),
        const SizedBox(height: 16),
        _buildRecurringHeader(context),
        const SizedBox(height: 10),
        if (recurring.isEmpty)
          _buildEmptyState(context)
        else
          for (final r in recurring) ...[
            _buildRecurringCard(context, r),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 16),
        _buildDetectedInfo(context),
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _buildSummaryCard(BuildContext context, double totalFixed, double overallLimit) {
    final variable = overallLimit > 0 ? (overallLimit - totalFixed).clamp(0, double.infinity) : 0.0;
    final fixedPct  = overallLimit > 0 ? (totalFixed / overallLimit).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.withValues(alpha: 0.1), Colors.purple.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Monthly Fixed Costs', style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 4),
        Text(widget.ca(totalFixed),
            style: TextStyle(fontSize: context.sp(26), fontWeight: FontWeight.bold, color: Colors.indigo)),
        const SizedBox(height: 12),
        if (overallLimit > 0) ...[
          Row(children: [
            Expanded(child: _miniCard(context, 'Fixed Costs', widget.ca(totalFixed), Colors.indigo)),
            const SizedBox(width: 10),
            Expanded(child: _miniCard(context, 'Variable Left', widget.ca(variable), Colors.teal)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: fixedPct, minHeight: 8,
              backgroundColor: Colors.teal.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.indigo),
            ),
          ),
          const SizedBox(height: 4),
          Text('${(fixedPct * 100).toStringAsFixed(0)}% of overall budget committed to fixed costs',
              style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
        ] else
          Text('Set an overall budget to see variable spending room',
              style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _miniCard(BuildContext context, String label, String value, Color color) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
      Text(value, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  Widget _buildRecurringHeader(BuildContext context) => Row(children: [
    Text('Fixed Expenses',
        style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
    const Spacer(),
    GestureDetector(
      onTap: () => _showAddDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add, size: 14, color: Colors.indigo),
          const SizedBox(width: 4),
          Text('Add', style: TextStyle(fontSize: context.sp(11), color: Colors.indigo, fontWeight: FontWeight.bold)),
        ]),
      ),
    ),
  ]);

  Widget _buildRecurringCard(BuildContext context, Map<String, dynamic> r) {
    final id       = r['_id']      as String? ?? '';
    final name     = r['name']     as String? ?? '';
    final amount   = (r['amount'] as num?)?.toDouble() ?? 0;
    final catKey   = r['category'] as String? ?? 'Other Fixed Cost';
    final dueDay   = r['dueDay']   as int?;
    final catMeta  = _categories.firstWhere((c) => c.$1 == catKey, orElse: () => _categories.last);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: catMeta.$3.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(width: 40, height: 40,
            decoration: BoxDecoration(color: catMeta.$3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(catMeta.$2, size: 18, color: catMeta.$3)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          Row(children: [
            Text(catKey, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
            if (dueDay != null) ...[
              Text(' · due on ${_ordinal(dueDay)}',
                  style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
            ],
          ]),
        ])),
        Text(widget.ca(amount),
            style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: catMeta.$3)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _confirmDelete(context, id, name),
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
          ),
        ),
      ]),
    );
  }

  Widget _buildEmptyState(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 32),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppThemeColors.border(context)),
    ),
    child: Column(children: [
      const Text('🔁', style: TextStyle(fontSize: 36)),
      const SizedBox(height: 10),
      Text('No fixed expenses yet',
          style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      const SizedBox(height: 4),
      Text('Tap "Add" to track rent, EMIs, subscriptions',
          style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
    ]),
  );

  Widget _buildDetectedInfo(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppThemeColors.cardBg(context),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppThemeColors.border(context)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.tips_and_updates_outlined, size: 15, color: Colors.indigo),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Fixed expenses are not counted against your Quick/Secure/Group budgets. '
        'They help you understand how much of your budget is truly available for variable spending.',
        style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context), height: 1.5),
      )),
    ]),
  );

  void _showAddDialog(BuildContext context) {
    final nameCtrl   = TextEditingController();
    final amountCtrl = TextEditingController();
    final dueDayCtrl = TextEditingController();
    String selectedCat = _categories.first.$1;
    String? nameError;
    String? amountError;
    String? dueDayError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final catMeta = _categories.firstWhere((c) => c.$1 == selectedCat);
          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: AppThemeColors.cardBg(context),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.withValues(alpha: 0.13), Colors.purple.withValues(alpha: 0.06)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.repeat_rounded, color: Colors.indigo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Add Fixed Expense',
                        style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context))),
                    Text('Recurring monthly cost', style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
                  ])),
                ]),
              ),

              Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 4), child: Column(children: [
                // Name
                _dialogField(context, nameCtrl, 'Name (e.g. Netflix, Home Loan EMI)',
                    Icons.label_outline_rounded, errorText: nameError),
                const SizedBox(height: 10),
                // Amount
                _dialogField(context, amountCtrl, 'Monthly amount',
                    Icons.currency_rupee_rounded,
                    prefixText: '₹ ',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    errorText: amountError),
                const SizedBox(height: 10),
                // Category dropdown
                DropdownButtonFormField<String>(
                  value: selectedCat,
                  decoration: InputDecoration(
                    prefixIcon: Icon(catMeta.$2, size: 18, color: catMeta.$3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppThemeColors.border(context))),
                  ),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c.$1,
                    child: Row(children: [
                      Icon(c.$2, size: 15, color: c.$3),
                      const SizedBox(width: 8),
                      Text(c.$1, style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.primaryText(context))),
                    ]),
                  )).toList(),
                  onChanged: (v) { if (v != null) setD(() => selectedCat = v); },
                ),
                const SizedBox(height: 10),
                // Due day — simple text field instead of 29-item dropdown
                _dialogField(context, dueDayCtrl, 'Due day of month (1–28, optional)',
                    Icons.event_outlined,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    errorText: dueDayError),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Leave blank if there\'s no fixed due date',
                      style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
                ),
              ])),

              Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 20), child: Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: AppThemeColors.border(context))),
                  child: Text('Cancel', style: TextStyle(color: AppThemeColors.secondaryText(context))),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final amt  = double.tryParse(amountCtrl.text);
                    final dayTxt = dueDayCtrl.text.trim();
                    final day  = dayTxt.isEmpty ? null : int.tryParse(dayTxt);
                    bool valid = true;
                    if (name.isEmpty) { setD(() => nameError = 'Enter a name'); valid = false; }
                    else { setD(() => nameError = null); }
                    if (amt == null || amt <= 0) { setD(() => amountError = 'Enter a valid amount'); valid = false; }
                    else { setD(() => amountError = null); }
                    if (dayTxt.isNotEmpty && (day == null || day < 1 || day > 28)) {
                      setD(() => dueDayError = 'Enter a day between 1 and 28'); valid = false;
                    } else { setD(() => dueDayError = null); }
                    if (!valid) return;
                    Navigator.pop(ctx);
                    widget.onSaveRecurring({
                      'name': name,
                      'amount': amt,
                      'category': selectedCat,
                      if (day != null) 'dueDay': day,
                    });
                  },
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ])),
            ])),
          );
        },
      ),
    );
  }

  Widget _dialogField(
    BuildContext context,
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    String? prefixText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? errorText,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: TextStyle(fontSize: context.sp(13), color: AppThemeColors.primaryText(context)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context)),
          prefixIcon: Icon(icon, size: 18, color: AppThemeColors.secondaryText(context)),
          prefixText: prefixText,
          errorText: errorText,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppThemeColors.border(context))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.indigo, width: 1.5)),
        ),
      );

  void _confirmDelete(BuildContext context, String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppThemeColors.cardBg(context),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Red header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 26),
              ),
              const SizedBox(height: 12),
              Text('Delete expense?',
                  style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 6),
              Text(
                'Remove "$name" from your fixed expenses?\nThis cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context), height: 1.5),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: AppThemeColors.border(context)),
                ),
                child: Text('Cancel',
                    style: TextStyle(color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
              )),
              const SizedBox(width: 12),
              Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); widget.onDeleteRecurring(id); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }
}
