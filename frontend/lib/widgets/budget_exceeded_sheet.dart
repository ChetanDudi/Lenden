import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/theme_helper.dart';
import '../utils/responsive.dart';

/// Parses an HTTP error body and checks whether it is a budget-exceeded response.
/// Returns the parsed map if it is, null otherwise.
Map<String, dynamic>? parseBudgetExceeded(String body) {
  try {
    final data = json.decode(body) as Map<String, dynamic>;
    if (data['budgetExceeded'] == true) return data;
  } catch (_) {}
  return null;
}

/// Shows a stylish bottom sheet asking the user whether to proceed despite
/// exceeding the budget. Returns true if they choose to continue.
Future<bool> showBudgetExceededSheet(
  BuildContext context,
  Map<String, dynamic> data,
) async {
  final type    = (data['type'] as String? ?? 'overall');
  final limit   = (data['limit'] as num?)?.toDouble() ?? 0;
  final spent   = (data['spent'] as num?)?.toDouble() ?? 0;
  final over    = (spent - limit).clamp(0.0, double.infinity);

  final typeLabel = {
    'quick':   'Quick',
    'secure':  'Secure',
    'group':   'Group',
    'overall': 'Overall',
  }[type] ?? type[0].toUpperCase() + type.substring(1);

  final typeIcon = {
    'quick':   Icons.flash_on_rounded,
    'secure':  Icons.shield_rounded,
    'group':   Icons.group_rounded,
    'overall': Icons.account_balance_wallet_rounded,
  }[type] ?? Icons.warning_amber_rounded;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _BudgetExceededSheet(
      typeLabel: typeLabel,
      typeIcon: typeIcon,
      limit: limit,
      spent: spent,
      over: over,
    ),
  );
  return result == true;
}

class _BudgetExceededSheet extends StatelessWidget {
  final String   typeLabel;
  final IconData typeIcon;
  final double   limit;
  final double   spent;
  final double   over;

  const _BudgetExceededSheet({
    required this.typeLabel,
    required this.typeIcon,
    required this.limit,
    required this.spent,
    required this.over,
  });

  @override
  Widget build(BuildContext context) {
    final pct = limit > 0 ? (spent / limit).clamp(0.0, 2.0) : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: AppThemeColors.border(context),
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(height: 24),

        // Icon badge
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle),
          child: Icon(typeIcon, color: Colors.orange.shade700, size: 30),
        ),
        const SizedBox(height: 16),

        Text('$typeLabel Budget Exceeded',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: context.sp(18),
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade700)),
        const SizedBox(height: 6),
        Text(
          'This transaction will put you ₹${over.toStringAsFixed(0)} over your $typeLabel monthly budget.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: context.sp(13),
              color: AppThemeColors.secondaryText(context),
              height: 1.4),
        ),
        const SizedBox(height: 20),

        // Stats row
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
          ),
          child: Column(children: [
            Row(children: [
              _stat(context, 'Monthly Limit', '₹${limit.toStringAsFixed(0)}', Colors.teal),
              _divider(context),
              _stat(context, 'Spent So Far', '₹${spent.toStringAsFixed(0)}', Colors.orange),
              _divider(context),
              _stat(context, 'Over By', '₹${over.toStringAsFixed(0)}', Colors.red),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: Colors.orange.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(pct * 100).toStringAsFixed(0)}% of $typeLabel budget used',
              style: TextStyle(
                  fontSize: context.sp(10),
                  color: AppThemeColors.secondaryText(context)),
            ),
          ]),
        ),
        const SizedBox(height: 24),

        // Action buttons
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: AppThemeColors.border(context)),
              ),
              child: Text('Cancel',
                  style: TextStyle(
                      fontSize: context.sp(14),
                      color: AppThemeColors.secondaryText(context),
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Continue Anyway',
                  style: TextStyle(
                      fontSize: context.sp(14),
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, String value, Color color) =>
      Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: context.sp(9),
                  color: AppThemeColors.secondaryText(context))),
        ]),
      );

  Widget _divider(BuildContext context) => Container(
      width: 1, height: 36,
      color: AppThemeColors.border(context));
}
