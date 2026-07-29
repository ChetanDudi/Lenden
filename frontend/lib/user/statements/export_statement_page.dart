import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../utils/share_utils.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/theme_helper.dart';

class ExportStatementPage extends StatefulWidget {
  const ExportStatementPage({super.key});

  @override
  State<ExportStatementPage> createState() => _ExportStatementPageState();
}

class _ExportStatementPageState extends State<ExportStatementPage> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 90));
  DateTime _toDate = DateTime.now();
  String _type = 'all';
  bool _exporting = false;

  static const _typeOptions = [
    {'value': 'all', 'label': 'All Transactions', 'icon': '📋'},
    {'value': 'secure', 'label': 'Secure Transactions', 'icon': '🔒'},
    {'value': 'quick', 'label': 'Quick Transactions', 'icon': '⚡'},
    {'value': 'group', 'label': 'Group Expenses', 'icon': '👥'},
  ];

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: AppColors.cyan),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _export() async {
    if (_fromDate.isAfter(_toDate)) {
      showSnack(context, 'Start date must be before end date.', isError: true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final from = DateFormat('yyyy-MM-dd').format(_fromDate);
      final to = DateFormat('yyyy-MM-dd').format(_toDate);
      final res = await ApiClient.get('/api/statements/export?from=$from&to=$to&type=$_type');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final ok = await shareTextFile(
          content: res.body,
          filename: 'lenden-statement-$from-to-$to.csv',
          subject: 'LenDen Transaction Statement',
        );
        if (!ok && mounted) {
          showSnack(context, 'Could not share the statement file.', isError: true);
        }
      } else {
        showSnack(context, 'Failed to generate statement.', isError: true);
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM dd, yyyy');
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: 'Export Statement'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ─────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan.withValues(alpha: 0.15), AppColors.blue.withValues(alpha: 0.08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: AppColors.cyan, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Transaction Statement',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context))),
                        const SizedBox(height: 4),
                        Text('Download a CSV file of your transactions for any date range.',
                            style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Date range ───────────────────────────────────────────────────
            _sectionLabel(context, Icons.date_range_rounded, 'Date Range'),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(child: _dateCard(context, label: 'From', date: _fromDate, onTap: () => _pickDate(true))),
                const SizedBox(width: 10),
                Icon(Icons.arrow_forward_rounded, size: 18, color: AppThemeColors.mutedText(context)),
                const SizedBox(width: 10),
                Expanded(child: _dateCard(context, label: 'To', date: _toDate, onTap: () => _pickDate(false))),
              ],
            ),

            if (_fromDate.isAfter(_toDate))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text('Start date is after end date.',
                      style: const TextStyle(fontSize: 12, color: Colors.orange)),
                ]),
              ),

            const SizedBox(height: 24),

            // ── Transaction type ─────────────────────────────────────────────
            _sectionLabel(context, Icons.filter_list_rounded, 'Transaction Type'),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _typeOptions.map((opt) {
                final selected = _type == opt['value'];
                return GestureDetector(
                  onTap: () => setState(() => _type = opt['value']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.cyan.withValues(alpha: 0.12)
                          : AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppColors.cyan : AppThemeColors.divider(context),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(opt['icon']!, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Text(
                          opt['label']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                            color: selected ? AppColors.cyan : AppThemeColors.primaryText(context),
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.cyan),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // ── Summary preview ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${_typeOptions.firstWhere((o) => o['value'] == _type)['label']} ',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.cyan),
                        ),
                        TextSpan(
                          text: 'from ${fmt.format(_fromDate)} to ${fmt.format(_toDate)}',
                          style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Export button ────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _exporting ? null : _export,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  disabledBackgroundColor: AppThemeColors.divider(context),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _exporting
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                label: Text(
                  _exporting ? 'Generating…' : 'Export & Share CSV',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.cyan),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
      ],
    );
  }

  Widget _dateCard(BuildContext context,
      {required String label, required DateTime date, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeColors.divider(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context),
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(date),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                ),
                const Icon(Icons.edit_calendar_rounded, size: 16, color: AppColors.cyan),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
