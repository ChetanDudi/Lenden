import 'dart:math';
import 'package:flutter/material.dart';
import '../../../utils/theme_helper.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/currency_display.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';

class RepaymentSchedulePage extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final DisplayCurrencyData? displayCurrencyData;
  final String selectedDisplayCurrency;
  final double remainingAmount;

  const RepaymentSchedulePage({
    Key? key,
    required this.transaction,
    required this.displayCurrencyData,
    required this.selectedDisplayCurrency,
    required this.remainingAmount,
  }) : super(key: key);

  String _formatDisplayAmount(num amount, String? originalCurrency) {
    final src = (originalCurrency ?? 'INR').toUpperCase();
    final tgt = selectedDisplayCurrency.toUpperCase();
    final canConvert =
        displayCurrencyData?.canConvert(src, tgt) ?? (src == tgt);
    if (!canConvert) {
      final sym = displayCurrencyData?.symbolFor(src) ?? src;
      return '$sym${amount.toStringAsFixed(2)} $src';
    }
    final converted =
        displayCurrencyData?.convert(amount.toDouble(), src, tgt) ??
            amount.toDouble();
    final sym = displayCurrencyData?.symbolFor(tgt) ?? tgt;
    return '$sym${converted.toStringAsFixed(2)} $tgt';
  }

  double _amountAt(int days) {
    final rate = (transaction['interestRate'] as num).toDouble();
    final type = transaction['interestType']?.toString() ?? '';
    if (type == 'simple') {
      return remainingAmount + (remainingAmount * rate * days / 36500);
    } else {
      final n = (transaction['compoundingFrequency'] as num?)?.toInt() ?? 1;
      return remainingAmount *
          pow(1 + (rate / 100) / n, n * (days / 365.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final currency = t['currency']?.toString();
    final rate = (t['interestRate'] as num?)?.toDouble() ?? 0.0;
    final interestType = t['interestType']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Repayment Schedule',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.brown, Color(0xFF5D4037)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: context.sh(90)),
            child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF9933), Color(0xFF138808)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.table_chart,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text('Repayment Schedule',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
            ]),
            const SizedBox(height: 16),

            // Summary card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.info_outline,
                          color: AppColors.cyan, size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text('Summary',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                  const SizedBox(height: 12),
                  _summaryRow(context, 'Interest Type',
                      interestType == 'simple' ? 'Simple' : 'Compound'),
                  const SizedBox(height: 6),
                  _summaryRow(context, 'Interest Rate', '$rate%'),
                  const SizedBox(height: 6),
                  _summaryRow(context, 'Current Remaining',
                      _formatDisplayAmount(remainingAmount, currency)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Amount owed grows over time if not cleared.',
                style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),

            // Day projection cards
            ...[30, 60, 90, 180].map((days) {
              final amt = _amountAt(days);
              final isEarly = days <= 30;
              final isMid = days <= 60;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isEarly
                      ? AppThemeColors.tinted(context, light: Colors.green.shade50, dark: const Color(0xFF0D2B0D))
                      : isMid
                          ? AppThemeColors.tinted(context, light: Colors.orange.shade50, dark: const Color(0xFF2B1A00))
                          : AppThemeColors.tinted(context, light: Colors.red.shade50, dark: const Color(0xFF2B0A0A)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isEarly
                          ? Colors.green.shade200
                          : isMid
                              ? Colors.orange.shade200
                              : Colors.red.shade200),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(
                          isEarly
                              ? Icons.check_circle_outline
                              : isMid
                                  ? Icons.warning_amber_outlined
                                  : Icons.error_outline,
                          color: isEarly
                              ? Colors.green[600]
                              : isMid
                                  ? Colors.orange[600]
                                  : Colors.red[600],
                          size: 20),
                      const SizedBox(width: 10),
                      Text('In $days days',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                    ]),
                    Text(
                        _formatDisplayAmount(amt, currency),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isEarly
                                ? Colors.green[700]
                                : isMid
                                    ? Colors.orange[700]
                                    : Colors.red[700])),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context))),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
