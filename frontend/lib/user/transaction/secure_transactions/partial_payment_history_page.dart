import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../utils/display_currency_helper.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';

class PartialPaymentHistoryPage extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final DisplayCurrencyData? displayCurrencyData;
  final String selectedDisplayCurrency;

  const PartialPaymentHistoryPage({
    Key? key,
    required this.transaction,
    required this.displayCurrencyData,
    required this.selectedDisplayCurrency,
  }) : super(key: key);

  String _getPaidByEmail(Map payment, Map transaction) {
    final paidBy = (payment['paidBy'] ?? '').toString();
    final role = (transaction['role'] ?? '').toString();
    // userEmail is always the creator; counterpartyEmail is the other party.
    // role is the creator's role. Derive lender/borrower emails accordingly.
    final lenderEmail = role == 'lender'
        ? transaction['userEmail']
        : transaction['counterpartyEmail'];
    final borrowerEmail = role == 'lender'
        ? transaction['counterpartyEmail']
        : transaction['userEmail'];
    if (paidBy == 'lender') return (lenderEmail ?? 'Lender').toString();
    if (paidBy == 'borrower') return (borrowerEmail ?? 'Borrower').toString();
    return paidBy;
  }

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

  @override
  Widget build(BuildContext context) {
    final partialPayments =
        transaction['partialPayments'] as List? ?? [];
    final currency = transaction['currency'] ?? '';

    double totalPaid = partialPayments.fold<double>(
        0, (s, p) => s + ((p['amount'] as num?) ?? 0).toDouble());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Payment History',
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
                    colors: [Colors.purple, Color(0xFF7B1FA2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: context.sh(90)),
            child: partialPayments.isEmpty
          ? const Center(
              child: Text('No payments yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 16)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Summary card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade400, Colors.purple.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 3))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Payment Summary',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(_formatDisplayAmount(totalPaid, currency),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${partialPayments.length} payment(s) made',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                // Payment cards
                ...List.generate(partialPayments.length, (i) {
                  final p = partialPayments[i] as Map;
                  final amount = (p['amount'] as num?) ?? 0;
                  final rawDate = p['paidAt']?.toString().isNotEmpty == true
                      ? p['paidAt'].toString()
                      : p['date']?.toString() ?? '';
                  final desc = p['description']?.toString() ?? '';
                  final paidByEmail = _getPaidByEmail(p, transaction);
                  final parsedDate =
                      rawDate.isNotEmpty ? DateTime.tryParse(rawDate) : null;
                  final method = p['paymentMethod']?.toString() ?? '';
                  final isPayNow = desc.toLowerCase().contains('pay now') ||
                      method == 'wallet' ||
                      method == 'razorpay';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF9933),
                          Colors.white,
                          Color(0xFF138808)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(
                              isPayNow
                                  ? Icons.flash_on
                                  : Icons.payments,
                              color: isPayNow
                                  ? Colors.indigo
                                  : Colors.purple,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                                _formatDisplayAmount(amount, currency),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPayNow
                                        ? Colors.indigo[700]
                                        : Colors.purple[700],
                                    fontSize: 15)),
                            const Spacer(),
                            // Payment type badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isPayNow
                                    ? Colors.indigo.withValues(alpha: 0.1)
                                    : Colors.purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isPayNow ? 'Pay Now' : 'Partial',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isPayNow
                                        ? Colors.indigo[700]
                                        : Colors.purple[700]),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 6),
                          if (parsedDate != null)
                            Text(
                              DateFormat('MMM d, yyyy  hh:mm a')
                                  .format(parsedDate.toLocal()),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[500]),
                            ),
                          if (paidByEmail.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Paid by: $paidByEmail',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700])),
                          ],
                          if (method.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(
                                method == 'wallet'
                                    ? Icons.account_balance_wallet
                                    : method == 'razorpay'
                                        ? Icons.credit_card
                                        : Icons.receipt_long,
                                size: 12,
                                color: Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                method == 'wallet'
                                    ? 'LenDen Wallet'
                                    : method == 'razorpay'
                                        ? 'Razorpay / UPI'
                                        : method,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500]),
                              ),
                            ]),
                          ],
                          if (desc.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text('Note: $desc',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600])),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
