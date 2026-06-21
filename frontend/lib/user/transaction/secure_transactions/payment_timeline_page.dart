import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/display_currency_helper.dart';
import '../../../widgets/wave_widget.dart';

class PaymentTimelinePage extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final DisplayCurrencyData? displayCurrencyData;
  final String selectedDisplayCurrency;
  final bool fullyCleared;

  const PaymentTimelinePage({
    Key? key,
    required this.transaction,
    required this.displayCurrencyData,
    required this.selectedDisplayCurrency,
    required this.fullyCleared,
  }) : super(key: key);

  String _formatDisplayAmount(num? amount, String? originalCurrency) {
    final numericAmount = (amount ?? 0).toDouble();
    final src = (originalCurrency ?? 'INR').toUpperCase();
    final tgt = selectedDisplayCurrency.toUpperCase();
    final canConvert =
        displayCurrencyData?.canConvert(src, tgt) ?? (src == tgt);
    if (!canConvert) {
      final sym = displayCurrencyData?.symbolFor(src) ?? src;
      return '$sym${numericAmount.toStringAsFixed(2)} $src';
    }
    final converted =
        displayCurrencyData?.convert(numericAmount, src, tgt) ?? numericAmount;
    final sym = displayCurrencyData?.symbolFor(tgt) ?? tgt;
    return '$sym${converted.toStringAsFixed(2)} $tgt';
  }

  String _calculateCurrentAmountWithInterest(Map transaction) {
    double original = transaction['amount']?.toDouble() ?? 0.0;
    double result = original;
    if (transaction['interestType'] != null &&
        transaction['interestRate'] != null) {
      final txDate = DateTime.tryParse(transaction['date'] ?? '');
      if (txDate != null) {
        final days = DateTime.now().difference(txDate).inDays;
        if (days > 0) {
          final rate = transaction['interestRate']?.toDouble() ?? 0.0;
          if (transaction['interestType'] == 'simple') {
            result = original + (original * rate * days / 365);
          } else if (transaction['interestType'] == 'compound') {
            final n = transaction['compoundingFrequency']?.toInt() ?? 1;
            result = original *
                pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return result.toStringAsFixed(2);
  }

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String label,
    required String date,
    String? amount,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            if (!isLast)
              Expanded(
                  child: Container(width: 2, color: Colors.grey.shade200)),
          ]),
          const SizedBox(width: 14),
          Expanded(
              child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(date,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
                if (amount != null) ...[
                  const SizedBox(height: 2),
                  Text(amount,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ],
              ],
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final txDate = DateTime.tryParse(t['date']?.toString() ?? '');
    final returnDate =
        DateTime.tryParse(t['expectedReturnDate']?.toString() ?? '');
    final partialPayments = ((t['partialPayments'] as List?) ?? [])
        .map((p) => p as Map)
        .toList();
    partialPayments.sort((a, b) {
      final da = DateTime.tryParse(a['date']?.toString() ?? '');
      final db = DateTime.tryParse(b['date']?.toString() ?? '');
      if (da == null || db == null) return 0;
      return da.compareTo(db);
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(140),
        child: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Payment Timeline',
              style: TextStyle(fontWeight: FontWeight.bold)),
          flexibleSpace: ClipPath(
            clipper: const TopWaveClipper(),
            child: Container(
              height: 140,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.cyan, Color(0xFF00ACC1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.cyan, Color(0xFF0077B6)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Icons.timeline, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('Payment Timeline',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0077B6))),
            ]),
            const SizedBox(height: 24),
            _timelineItem(
                icon: Icons.flag_circle,
                color: Colors.teal,
                label: 'Transaction Created',
                date: txDate != null
                    ? DateFormat('MMM d, yyyy').format(txDate)
                    : '—',
                amount: _formatDisplayAmount(
                    (t['amount'] as num?) ?? 0,
                    t['currency']?.toString()),
                isFirst: true),
            ...partialPayments.map((p) {
              final pDate =
                  DateTime.tryParse(p['date']?.toString() ?? '');
              final pAmount = (p['amount'] as num?) ?? 0;
              final pDesc = p['description']?.toString() ?? '';
              return _timelineItem(
                icon: Icons.payments,
                color: Colors.purple,
                label:
                    'Partial Payment${pDesc.isNotEmpty ? ': $pDesc' : ''}',
                date: pDate != null
                    ? DateFormat('MMM d, yyyy').format(pDate)
                    : '—',
                amount: _formatDisplayAmount(
                    pAmount, t['currency']?.toString()),
              );
            }),
            if (returnDate != null)
              _timelineItem(
                  icon: Icons.event,
                  color: Colors.orange,
                  label: 'Expected Return',
                  date: DateFormat('MMM d, yyyy').format(returnDate),
                  amount: _formatDisplayAmount(
                      double.tryParse(
                              _calculateCurrentAmountWithInterest(t)) ??
                          0,
                      t['currency']?.toString())),
            _timelineItem(
                icon: Icons.check_circle,
                color: fullyCleared ? Colors.green : Colors.grey,
                label:
                    fullyCleared ? 'Fully Cleared' : 'Pending Clearance',
                date: fullyCleared ? 'Done' : 'Awaiting…',
                isLast: true),
          ],
        ),
      ),
    );
  }
}
