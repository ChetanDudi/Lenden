import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../utils/display_currency_helper.dart';
import '../../chats/chat_page.dart';
import '../../../otp_input.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../wallet/lenden_wallet_page.dart';

class SecureTransactionDetailPage extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final bool isLending;
  const SecureTransactionDetailPage({
    super.key,
    required this.transaction,
    required this.isLending,
  });
  @override
  State<SecureTransactionDetailPage> createState() =>
      _SecureTransactionDetailPageState();
}

class _SecureTransactionDetailPageState
    extends State<SecureTransactionDetailPage> {
  late Map<String, dynamic> _t;
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
  DateTime _now = DateTime.now();
  Timer? _countdownTimer;
  bool _needsRefresh = false;

  @override
  void initState() {
    super.initState();
    _t = Map<String, dynamic>.from(widget.transaction);
    if (_t['favourite'] is List) {
      _t['favourite'] = List<dynamic>.from(_t['favourite']);
    } else {
      _t['favourite'] = <dynamic>[];
    }
    _loadDisplayCurrencies();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDisplayCurrencies() async {
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = data;
        if (!data.currencies.any((c) => c['code'] == _selectedDisplayCurrency)) {
          _selectedDisplayCurrency = 'INR';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
      });
    }
  }

  String _formatDisplayAmount(num? amount, String? originalCurrency) {
    final numericAmount = (amount ?? 0).toDouble();
    final src = (originalCurrency ?? 'INR').toUpperCase();
    final tgt = _selectedDisplayCurrency.toUpperCase();
    final canConvert =
        _displayCurrencyData?.canConvert(src, tgt) ?? (src == tgt);
    if (!canConvert) {
      final sym = _displayCurrencyData?.symbolFor(src) ?? src;
      return '$sym${numericAmount.toStringAsFixed(2)} $src';
    }
    final converted =
        _displayCurrencyData?.convert(numericAmount, src, tgt) ?? numericAmount;
    final sym = _displayCurrencyData?.symbolFor(tgt) ?? tgt;
    return '$sym${converted.toStringAsFixed(2)} $tgt';
  }

  bool _hasPartialPayment(Map t) {
    final pp = t['partialPayments'];
    return t['isPartiallyPaid'] == true || (pp is List && pp.isNotEmpty);
  }

  String _remainingTimeLabel(DateTime expectedReturnDate) {
    final diff = expectedReturnDate.difference(_now);
    if (diff.isNegative) {
      return 'Overdue since ${DateFormat('MMM d').format(expectedReturnDate)}';
    }
    if (diff.inDays > 0) return '${diff.inDays} day(s) remaining';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    return '${h}h ${m}m ${s}s remaining';
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
            result = original * pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return result.toStringAsFixed(2);
  }

  String _calculateAmountPaidTillNow(Map transaction) {
    double paid = 0.0;
    if (transaction['userCleared'] == true &&
        transaction['counterpartyCleared'] == true) {
      paid = transaction['amount']?.toDouble() ?? 0.0;
    } else if (transaction['isPartiallyPaid'] == true &&
        transaction['partialPayments'] != null) {
      final pp = transaction['partialPayments'] as List;
      paid = pp.fold<double>(
          0, (s, p) => s + (p['amount'] as num).toDouble());
    }
    return paid.toStringAsFixed(2);
  }

  String _calculateRemainingAmount(Map transaction) {
    double original = transaction['amount']?.toDouble() ?? 0.0;
    double paid = double.parse(_calculateAmountPaidTillNow(transaction));
    double remaining = original - paid;
    if (paid >= original) return '0.00';
    if (transaction['interestType'] != null &&
        transaction['interestRate'] != null) {
      final txDate = DateTime.tryParse(transaction['date'] ?? '');
      if (txDate != null) {
        final days = DateTime.now().difference(txDate).inDays;
        if (days > 0) {
          final rate = transaction['interestRate']?.toDouble() ?? 0.0;
          if (transaction['interestType'] == 'simple') {
            remaining = remaining + (remaining * rate * days / 365);
          } else if (transaction['interestType'] == 'compound') {
            final n = transaction['compoundingFrequency']?.toInt() ?? 1;
            remaining = remaining * pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return remaining.toStringAsFixed(2);
  }

  Future<Map<String, dynamic>?> _fetchCounterpartyProfile(String email) async {
    if (email.isEmpty) return null;
    try {
      final res = await ApiClient.get(
          '/api/users/profile-by-email?email=${Uri.encodeComponent(email)}');
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  Future<void> _showPayNow() async {
    final t = _t;
    // role='lender' means the DB creator is the lender → pay them (t['userEmail']).
    // role='borrower' means the DB creator is the borrower → lender is the counterparty.
    // Using t['counterpartyEmail'] blindly is wrong when the lender created the transaction,
    // because then counterpartyEmail IS the current user (borrower).
    final String payToEmail = (t['role']?.toString() == 'lender')
        ? t['userEmail']?.toString() ?? ''
        : t['counterpartyEmail']?.toString() ?? '';
    final transactionId = t['transactionId']?.toString() ?? '';
    final remaining = double.tryParse(_calculateRemainingAmount(t)) ?? 0;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No outstanding balance to pay.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (!mounted) return;
    await LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: payToEmail,
      amount: remaining,
      description: 'Secure transaction repayment',
      secureTransactionId: transactionId,
      onSuccess: () => _clearAfterPayment(remaining),
    );
  }

  // Marks payer's side cleared after payment. Razorpay path records the partial payment
  // automatically in verifyP2PPayment; wallet path records it here via the clear endpoint.
  Future<void> _clearAfterPayment(double amountPaid) async {
    final email = Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null || !mounted) return;
    // Payment made — clear both sides
    try {
      final res = await ApiClient.post('/api/transactions/clear',
          body: {'transactionId': _t['transactionId'], 'email': email, 'bothSides': true});
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _t['userCleared'] = true;
          _t['counterpartyCleared'] = true;
          _needsRefresh = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment sent and marked as cleared!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Payment sent! Refresh to see updated status.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _toggleFavourite() async {
    final email =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return;
    final tid = _t['transactionId'];
    final fav = _t['favourite'] as List<dynamic>;
    final isFav = fav.contains(email);
    setState(() {
      if (isFav) {
        fav.remove(email);
      } else {
        fav.add(email);
      }
      _needsRefresh = true;
    });
    try {
      final res = await ApiClient.put(
          '/api/transactions/$tid/favourite', body: {'email': email});
      if (res.statusCode != 200) {
        setState(() {
          if (isFav) {
            fav.add(email);
          } else {
            fav.remove(email);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to update favourite'),
            backgroundColor: Colors.red));
      }
    } catch (_) {
      setState(() {
        if (isFav) {
          fav.add(email);
        } else {
          fav.remove(email);
        }
      });
    }
  }

  Future<void> _clearTransaction() async {
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    if (email == null) return;
    try {
      final res = await ApiClient.post('/api/transactions/clear',
          body: {'transactionId': _t['transactionId'], 'email': email});
      if (res.statusCode == 200) {
        setState(() {
          if (_t['userEmail'] == email) {
            _t['userCleared'] = true;
          } else {
            _t['counterpartyCleared'] = true;
          }
          _needsRefresh = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Transaction cleared'),
            backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to clear transaction'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Network error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteTransaction() async {
    final email =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return;
    try {
      final res = await ApiClient.post('/api/transactions/delete',
          body: {'transactionId': _t['transactionId'], 'email': email});
      if (res.statusCode == 200) {
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data?['error'] ?? 'Failed to delete'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Network error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showDeleteConfirmationDialog() {
    showDialog(
        context: context,
        builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(children: [
                    ClipPath(
                      clipper: _TopWaveClipper(),
                      child: Container(
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Colors.red[400]!, Colors.red[600]!],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                        ),
                      ),
                    ),
                    Positioned.fill(
                        child: Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: CircleAvatar(
                                    radius: 28,
                                    backgroundColor: Colors.white,
                                    child: Icon(Icons.delete_forever,
                                        color: Colors.red[600], size: 40))))),
                  ]),
                  const SizedBox(height: 20),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('Delete Transaction',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.red[600]))),
                  const SizedBox(height: 12),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                          'Are you sure you want to delete this transaction? This action cannot be undone.')),
                  const SizedBox(height: 20),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey),
                                child: const Text('Cancel')),
                            ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteTransaction();
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.white))),
                          ])),
                ],
              ),
            ));
  }

  void _navigateToChat() async {
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final currentEmail = user?['email'];
    final userEmail = _t['userEmail'];
    final counterpartyEmail = _t['counterpartyEmail'];
    final otherEmail =
        currentEmail == userEmail ? counterpartyEmail : userEmail;
    final profile = await _fetchCounterpartyProfile(otherEmail?.toString() ?? '');
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open chat. User not found.')));
      return;
    }
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatPage(
                transactionId: _t['_id'],
                otherUserId: profile['_id'])));
  }

  void _showReceiptOptionsDialog() {
    showDialog(
        context: context,
        builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 20),
                Text('Generate Receipt',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.blue[600])),
                const SizedBox(height: 12),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Choose an option to generate the receipt.',
                        textAlign: TextAlign.center)),
                const SizedBox(height: 20),
                Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                              icon: const Icon(Icons.email, color: Colors.white),
                              label: const Text('Send to Email',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[600],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _sendReceiptByEmail();
                              }),
                          ElevatedButton.icon(
                              icon: const Icon(Icons.download,
                                  color: Colors.white),
                              label: const Text('Download Locally',
                                  style: TextStyle(color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[600],
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _downloadReceiptLocally();
                              }),
                        ])),
              ]),
            ));
  }

  void _sendReceiptByEmail() async {
    final email =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Dialog(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Sending to email...')
                ]))));
    try {
      final res = await ApiClient.post(
          '/api/transactions/${_t['transactionId']}/receipt',
          body: {'email': email, 'action': 'email'});
      Navigator.pop(context);
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Receipt sent to your email!'),
            backgroundColor: Colors.green));
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data?['error'] ?? 'Failed to send receipt'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Network error: $e'), backgroundColor: Colors.red));
    }
  }

  void _downloadReceiptLocally() async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Dialog(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Text('Downloading locally...')
                ]))));
    try {
      final email =
          Provider.of<SessionProvider>(context, listen: false).user?['email'];
      final res = await ApiClient.post(
          '/api/transactions/${_t['transactionId']}/receipt',
          body: {'email': email, 'action': 'download'});
      Navigator.pop(context);
      if (res.statusCode == 200) {
        final out = await getTemporaryDirectory();
        final file =
            File('${out.path}/receipt-${_t['transactionId']}.pdf');
        await file.writeAsBytes(res.bodyBytes);
        OpenFile.open(file.path);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Receipt downloaded to ${file.path}'),
                backgroundColor: Colors.green));
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data?['error'] ?? 'Failed to download'),
            backgroundColor: Colors.red));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Network error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showPartialPaymentDialog() {
    showDialog(
        context: context,
        builder: (_) => PartialPaymentDialog(
              transaction: Map<String, dynamic>.from(_t),
              onPaymentComplete: () {
                _needsRefresh = true;
                Navigator.of(context).pop(true);
              },
            ));
  }

  void _showPartialPaymentHistoryDialog() {
    showDialog(
        context: context,
        builder: (_) => PartialPaymentHistoryDialog(
              transaction: _t,
              displayCurrencyData: _displayCurrencyData,
              selectedDisplayCurrency: _selectedDisplayCurrency,
            ));
  }

  Widget _serviceChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ]),
            if (badge != null && badge > 0)
              Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                      child: Text('$badge',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9)))),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
      String value, String label, IconData icon, Color color) {
    // Outer container uses a gradient (saffron top → white middle → green bottom)
    // as a 3px "stripe" wrapper. Inner container is white — this avoids the
    // "borderRadius with non-uniform border colors" Flutter constraint.
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFF9933),
            Color(0xFFFF9933),
            Colors.white,
            Colors.white,
            Color(0xFF138808),
            Color(0xFF138808),
          ],
          stops: [0.0, 0.05, 0.05, 0.95, 0.95, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, Color iconColor, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailDivider() {
    return Row(
      children: [
        Container(width: 4, height: 1, color: const Color(0xFFFF9933)),
        Expanded(child: Container(height: 1, color: const Color(0xFFE3F2FD))),
        Container(width: 4, height: 1, color: const Color(0xFF138808)),
      ],
    );
  }

  double _calculateDailyInterestAccrual(Map t) {
    final remaining = double.tryParse(_calculateRemainingAmount(t)) ?? 0.0;
    final rate = (t['interestRate'] as num?)?.toDouble() ?? 0.0;
    if (t['interestType'] == 'simple') {
      return remaining * rate / 100 / 365;
    } else if (t['interestType'] == 'compound') {
      final n = (t['compoundingFrequency'] as num?)?.toInt() ?? 1;
      return remaining * (pow(1 + (rate / 100) / n, n / 365.0) - 1);
    }
    return 0.0;
  }

  String _paymentVelocity(Map t) {
    final pp = t['partialPayments'];
    if (pp is! List || pp.length < 2) return '—';
    final dates = pp
        .map((p) => DateTime.tryParse(p['date']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList();
    if (dates.length < 2) return '—';
    dates.sort();
    double totalGap = 0;
    for (int i = 1; i < dates.length; i++) {
      totalGap += dates[i].difference(dates[i - 1]).inDays;
    }
    final avg = (totalGap / (dates.length - 1)).round();
    return 'Every ~$avg days';
  }

  int _daysOutstanding(Map t) {
    final createdAt = DateTime.tryParse(
        (t['createdAt'] ?? t['date'] ?? '').toString());
    if (createdAt == null) return 0;
    return _now.difference(createdAt).inDays;
  }

  void _copyTransactionId() {
    final id = _t['transactionId']?.toString() ?? '';
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transaction ID copied!'),
        duration: Duration(seconds: 2)));
  }

  void _shareTransaction() {
    final t = _t;
    final role = widget.isLending ? 'Lent' : 'Borrowed';
    final amount =
        _formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString());
    final counterparty = t['counterpartyEmail'] ?? '—';
    final rawDate = t['date']?.toString() ?? '';
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final interest =
        (t['interestType'] != null && t['interestRate'] != null)
            ? '${t['interestType']} @ ${t['interestRate']}%'
            : 'None';
    final remaining = _formatDisplayAmount(
        double.tryParse(_calculateRemainingAmount(t)) ?? 0,
        t['currency']?.toString());
    final txId = t['transactionId'] ?? '—';
    Share.share(
      '📋 Transaction Summary\n'
      '━━━━━━━━━━━━━━━━━━━\n'
      '$role: $amount\n'
      'Counterparty: $counterparty\n'
      'Date: $date\n'
      'Interest: $interest\n'
      'Remaining: $remaining\n'
      'ID: $txId\n'
      '━━━━━━━━━━━━━━━━━━━\n'
      'Shared via LenDen',
      subject: 'LenDen Transaction: $amount',
    );
  }

  void _showPaymentTimeline() {
    final t = _t;
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
    final fullyCleared =
        t['userCleared'] == true && t['counterpartyCleared'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF00B4D8), Color(0xFF0077B6)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timeline,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Text('Payment Timeline',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0077B6))),
                ]),
                const SizedBox(height: 20),
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
        ),
      ),
    );
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

  void _showRepaymentSchedule() {
    final t = _t;
    if (t['interestType'] == null || t['interestRate'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No interest on this transaction')));
      return;
    }
    final remaining =
        double.tryParse(_calculateRemainingAmount(t)) ?? 0.0;
    final rate = (t['interestRate'] as num).toDouble();
    final type = t['interestType']?.toString() ?? '';

    double amountAt(int days) {
      if (type == 'simple') {
        return remaining + (remaining * rate * days / 36500);
      } else {
        final n = (t['compoundingFrequency'] as num?)?.toInt() ?? 1;
        return remaining * pow(1 + (rate / 100) / n, n * (days / 365.0));
      }
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                const Text('Repayment Schedule',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0077B6))),
              ]),
              const SizedBox(height: 12),
              Text(
                  'Amount owed grows over time if not cleared.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ...[30, 60, 90, 180].map((days) {
                final amt = amountAt(days);
                final isEarly = days <= 30;
                final isMid = days <= 60;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isEarly
                        ? Colors.green.shade50
                        : isMid
                            ? Colors.orange.shade50
                            : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isEarly
                            ? Colors.green.shade200
                            : isMid
                                ? Colors.orange.shade200
                                : Colors.red.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('In $days days',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      Text(
                          _formatDisplayAmount(
                              amt, t['currency']?.toString()),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isEarly
                                  ? Colors.green[700]
                                  : isMid
                                      ? Colors.orange[700]
                                      : Colors.red[700])),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0077B6)),
                child: const Text('Close',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    final t = _t;
    final isLending = widget.isLending;

    final youCleared =
        (isLending ? t['userCleared'] : t['counterpartyCleared']) == true;
    final otherCleared =
        (isLending ? t['counterpartyCleared'] : t['userCleared']) == true;
    final fullyCleared = youCleared && otherCleared;
    final hasPartialPayment = _hasPartialPayment(t);
    final isBorrower = !isLending;
    final isFav = (t['favourite'] as List<dynamic>).contains(email);

    List<Map<String, dynamic>> attachments = [];
    if (t['files'] is List && (t['files'] as List).isNotEmpty) {
      attachments = List<Map<String, dynamic>>.from(t['files']);
    } else if (t['photos'] is List && (t['photos'] as List).isNotEmpty) {
      attachments = (t['photos'] as List)
          .map<Map<String, dynamic>>(
              (p) => {'type': 'image/jpeg', 'data': p, 'name': 'Photo'})
          .toList();
    }

    final expectedReturnDate =
        DateTime.tryParse((t['expectedReturnDate'] ?? '').toString());
    final isOverdue = expectedReturnDate != null &&
        expectedReturnDate.isBefore(_now) &&
        !fullyCleared;
    final isDueSoon = expectedReturnDate != null &&
        !isOverdue &&
        expectedReturnDate.difference(_now).inDays >= 0 &&
        expectedReturnDate.difference(_now).inDays <= 7 &&
        !fullyCleared;

    final counterpartyEmail = t['counterpartyEmail']?.toString() ?? '';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_needsRefresh);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          backgroundColor: isLending ? Colors.teal : Colors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Transaction Detail',
              style: TextStyle(fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_needsRefresh),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header gradient card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isLending
                        ? [Colors.teal, Colors.teal.shade700]
                        : [Colors.orange, Colors.orange.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          isLending
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: Colors.white,
                          size: 22),
                      const SizedBox(width: 8),
                      Text(
                          isLending
                              ? 'Lending (You gave money)'
                              : 'Borrowing (You took money)',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                      const Spacer(),
                      if (hasPartialPayment)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: Colors.purple,
                                borderRadius: BorderRadius.circular(12)),
                            child: const Text('Partial',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 8),
                    Text(
                        _formatDisplayAmount(
                            (t['amount'] as num?) ?? 0,
                            t['currency']?.toString()),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            fullyCleared
                                ? Icons.verified
                                : hasPartialPayment
                                    ? Icons.account_balance_wallet_outlined
                                    : (youCleared || otherCleared)
                                        ? Icons.check
                                        : Icons.hourglass_empty,
                            color: Colors.white,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(
                            fullyCleared
                                ? 'Fully Cleared'
                                : hasPartialPayment
                                    ? 'Partially Paid'
                                    : (youCleared && !otherCleared)
                                        ? 'You cleared'
                                        : (!youCleared && otherCleared)
                                            ? 'Other cleared'
                                            : 'Uncleared',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                    if (expectedReturnDate != null && !fullyCleared) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: (isOverdue
                                    ? Colors.red
                                    : isDueSoon
                                        ? Colors.amber
                                        : Colors.white)
                                .withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                  isOverdue
                                      ? Icons.warning_amber_rounded
                                      : Icons.schedule_rounded,
                                  color: Colors.white,
                                  size: 13),
                              const SizedBox(width: 5),
                              Text(
                                  _remainingTimeLabel(expectedReturnDate),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(children: [
                      const Icon(Icons.person_outline,
                          color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text('Counterparty: $counterpartyEmail',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                    const SizedBox(height: 8),
                    // Days outstanding + daily interest accrual
                    Row(children: [
                      const Icon(Icons.hourglass_top,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text('${_daysOutstanding(t)} days outstanding',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                      const Spacer(),
                      if (t['interestType'] != null &&
                          t['interestRate'] != null &&
                          !fullyCleared)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.trending_up,
                                    color: Colors.redAccent, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                    '+${_formatDisplayAmount(_calculateDailyInterestAccrual(t), t['currency']?.toString())}/day',
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ]),
                        ),
                    ]),
                    const SizedBox(height: 6),
                    // Cleared status side-by-side
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      youCleared
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: youCleared
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                      'You: ${youCleared ? 'Cleared ✓' : 'Pending'}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11)),
                                ]),
                            Container(
                                width: 1,
                                height: 16,
                                color: Colors.white30),
                            Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      otherCleared
                                          ? Icons.check_circle
                                          : Icons.cancel,
                                      color: otherCleared
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                      size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                      'Them: ${otherCleared ? 'Cleared ✓' : 'Pending'}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11)),
                                ]),
                          ]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Horizontal service bar
              SizedBox(
                height: 50,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (isBorrower && !fullyCleared)
                      _serviceChip(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'Pay Now',
                          color: const Color(0xFF023E8A),
                          onTap: _showPayNow),
                    if (isBorrower && !fullyCleared)
                      _serviceChip(
                          icon: Icons.payment,
                          label: 'Partial Pay',
                          color: Colors.purple,
                          onTap: _showPartialPaymentDialog),
                    _serviceChip(
                        icon: Icons.history,
                        label: 'Pay History',
                        color: Colors.indigo,
                        onTap: _showPartialPaymentHistoryDialog),
                    _serviceChip(
                        icon: Icons.receipt_long,
                        label: 'Receipt',
                        color: Colors.green,
                        onTap: _showReceiptOptionsDialog),
                    _serviceChip(
                        icon: Icons.chat_bubble_outline,
                        label: 'Chat',
                        color: Colors.blue,
                        onTap: _navigateToChat),
                    if (!youCleared)
                      _serviceChip(
                          icon: Icons.check_circle_outline,
                          label: 'Clear',
                          color: Colors.orange,
                          onTap: _clearTransaction),
                    _serviceChip(
                        icon: isFav
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: isFav ? 'Unfavourite' : 'Favourite',
                        color: Colors.red,
                        onTap: _toggleFavourite),
                    if (attachments.isNotEmpty)
                      _serviceChip(
                          icon: Icons.attach_file,
                          label: 'Attachments',
                          color: Colors.teal,
                          badge: attachments.length,
                          onTap: () => showDialog(
                              context: context,
                              builder: (_) => _AttachmentCarouselDialog(
                                  attachments: attachments))),
                    if (fullyCleared)
                      _serviceChip(
                          icon: Icons.delete_forever,
                          label: 'Delete',
                          color: Colors.red,
                          onTap: _showDeleteConfirmationDialog),
                    _serviceChip(
                        icon: Icons.share,
                        label: 'Share',
                        color: Colors.deepPurple,
                        onTap: _shareTransaction),
                    _serviceChip(
                        icon: Icons.timeline,
                        label: 'Timeline',
                        color: Colors.cyan,
                        onTap: _showPaymentTimeline),
                    if (t['interestType'] != null &&
                        t['interestRate'] != null)
                      _serviceChip(
                          icon: Icons.table_chart,
                          label: 'Schedule',
                          color: Colors.brown,
                          onTap: _showRepaymentSchedule),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Stat cards row
              SizedBox(
                height: 95,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _statCard(
                        _formatDisplayAmount(
                            (t['amount'] as num?) ?? 0,
                            t['currency']?.toString()),
                        'Principal',
                        Icons.attach_money,
                        Colors.green),
                    if (t['interestType'] != null &&
                        t['interestRate'] != null)
                      _statCard(
                          _formatDisplayAmount(
                              double.tryParse(
                                      _calculateCurrentAmountWithInterest(t)) ??
                                  0,
                              t['currency']?.toString()),
                          'With Interest',
                          Icons.percent,
                          Colors.blue),
                    _statCard(
                        _formatDisplayAmount(
                            double.tryParse(
                                    _calculateAmountPaidTillNow(t)) ??
                                0,
                            t['currency']?.toString()),
                        'Amount Paid',
                        Icons.payments,
                        Colors.teal),
                    _statCard(
                        _formatDisplayAmount(
                            double.tryParse(
                                    _calculateRemainingAmount(t)) ??
                                0,
                            t['currency']?.toString()),
                        'Remaining',
                        Icons.account_balance_wallet,
                        Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Repayment progress bar
              Builder(builder: (context) {
                final totalWithInterest = double.tryParse(
                        _calculateCurrentAmountWithInterest(t)) ??
                    (t['amount'] as num? ?? 0).toDouble();
                final paid =
                    double.tryParse(_calculateAmountPaidTillNow(t)) ?? 0.0;
                final progress = fullyCleared
                    ? 1.0
                    : (totalWithInterest > 0
                        ? (paid / totalWithInterest).clamp(0.0, 1.0)
                        : 0.0);
                if (paid == 0 && !fullyCleared) return const SizedBox.shrink();
                final pct = (progress * 100).toStringAsFixed(1);
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Repayment Progress',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          Text('$pct%',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: progress >= 1.0
                                      ? Colors.green
                                      : progress > 0.5
                                          ? Colors.orange
                                          : Colors.red)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              progress >= 1.0
                                  ? Colors.green
                                  : progress > 0.5
                                      ? Colors.orange
                                      : Colors.red),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                              _formatDisplayAmount(
                                  paid, t['currency']?.toString()),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                          Text(
                              _formatDisplayAmount(totalWithInterest,
                                  t['currency']?.toString()),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                );
              }),

              // Details card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tricolor top bar
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: Row(
                        children: [
                          Expanded(child: Container(height: 5, color: const Color(0xFFFF9933))),
                          Expanded(child: Container(height: 5, color: Colors.white)),
                          Expanded(child: Container(height: 5, color: const Color(0xFF138808))),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with icon
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00B4D8), Color(0xFF0077B6)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.receipt_long, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              const Text('Transaction Details',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17,
                                      letterSpacing: 0.3,
                                      color: Color(0xFF0077B6))),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Info rows in a styled container
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FBFF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFBBDEFB), width: 1),
                            ),
                            child: Column(
                              children: [
                                _detailRow(Icons.calendar_today, const Color(0xFF1976D2),
                                    'Date', t['date']?.toString().substring(0, 10) ?? '—'),
                                _detailDivider(),
                                _detailRow(Icons.access_time, const Color(0xFF7B1FA2),
                                    'Time', t['time']?.toString() ?? '—'),
                                _detailDivider(),
                                _detailRow(Icons.place, const Color(0xFF9C27B0),
                                    'Place', (t['place'] ?? '').toString().isNotEmpty ? t['place'].toString() : '—'),
                                _detailDivider(),
                                _detailDivider(),
                                GestureDetector(
                                  onTap: _copyTransactionId,
                                  child: _detailRow(
                                      Icons.confirmation_number,
                                      Colors.grey.shade600,
                                      'Transaction ID',
                                      '${t['transactionId'] ?? '—'}  📋'),
                                ),
                                _detailDivider(),
                                _detailRow(
                                    Icons.history_toggle_off,
                                    Colors.blue.shade400,
                                    'Days Outstanding',
                                    '${_daysOutstanding(t)} days'),
                                if (_hasPartialPayment(t) &&
                                    ((_t['partialPayments'] as List?)
                                                ?.length ??
                                            0) >
                                        1) ...[
                                  _detailDivider(),
                                  _detailRow(Icons.speed, Colors.purple,
                                      'Payment Velocity',
                                      _paymentVelocity(t)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Counterparty tap row with tricolor left accent
                          GestureDetector(
                            onTap: () async {
                              showDialog(
                                  context: context,
                                  builder: (_) => FutureBuilder<Map<String, dynamic>?>(
                                        future: _fetchCounterpartyProfile(counterpartyEmail),
                                        builder: (ctx, snap) {
                                          if (snap.connectionState == ConnectionState.waiting) {
                                            return const Center(child: CircularProgressIndicator());
                                          }
                                          final profile = snap.data;
                                          if (profile == null) {
                                            return _StylishProfileDialog(
                                                title: 'Counterparty Info',
                                                name: 'No profile found.',
                                                avatarProvider: const AssetImage('assets/Other.png'));
                                          }
                                          if (profile['deactivatedAccount'] == true) {
                                            return _StylishProfileDialog(
                                                title: 'Counterparty Info',
                                                name: 'Account Deactivated.',
                                                avatarProvider: const AssetImage('assets/Other.png'));
                                          }
                                          if (profile['profileIsPrivate'] == true) {
                                            return _StylishProfileDialog(
                                                title: 'Counterparty Info',
                                                name: 'Profile is private.',
                                                avatarProvider: const AssetImage('assets/Other.png'));
                                          }
                                          dynamic imgUrl = profile['profileImage'];
                                          if (imgUrl is Map) imgUrl = imgUrl['url'];
                                          if (imgUrl != null && imgUrl is! String) imgUrl = null;
                                          final gender = profile['gender'] ?? 'Other';
                                          final avatarProv = (imgUrl != null &&
                                                  imgUrl.toString().isNotEmpty &&
                                                  imgUrl != 'null')
                                              ? NetworkImage(imgUrl) as ImageProvider
                                              : AssetImage(gender == 'Male'
                                                  ? 'assets/Male.png'
                                                  : gender == 'Female'
                                                      ? 'assets/Female.png'
                                                      : 'assets/Other.png');
                                          return _StylishProfileDialog(
                                              title: 'Counterparty',
                                              name: profile['name'] ?? 'Counterparty',
                                              avatarProvider: avatarProv,
                                              email: profile['email'],
                                              phone: (profile['phone'] ?? '').toString(),
                                              gender: profile['gender']);
                                        },
                                      ));
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFFF3E0), Color(0xFFE8F5E9)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                border: Border(
                                  left: const BorderSide(color: Color(0xFFFF9933), width: 4),
                                  top: BorderSide(color: Colors.orange.shade100, width: 1),
                                  bottom: BorderSide(color: Colors.green.shade100, width: 1),
                                  right: const BorderSide(color: Color(0xFF138808), width: 4),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.person_outline, color: Colors.teal, size: 18),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Counterparty',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w500)),
                                        Text(counterpartyEmail,
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.black87,
                                                fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Icon(Icons.info_outline, color: Colors.teal, size: 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (t['interestType'] != null && t['interestRate'] != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Column(
                                children: [
                                  _detailRow(Icons.percent, Colors.blue.shade700,
                                      'Interest',
                                      '${t['interestType'] == 'simple' ? 'Simple' : 'Compound'} @ ${t['interestRate']}%'),
                                  if (t['expectedReturnDate'] != null) ...[
                                    _detailDivider(),
                                    _detailRow(Icons.calendar_month, Colors.teal,
                                        'Return Date',
                                        t['expectedReturnDate']?.toString().substring(0, 10) ?? ''),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          if ((t['description'] ?? '').toString().trim().isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.notes_rounded, color: Colors.teal, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Description',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey,
                                                fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 3),
                                        Text(t['description'].toString(),
                                            style: const TextStyle(
                                                fontSize: 14, color: Colors.black87)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (!youCleared) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFE3F2FD), Color(0xFFE8F5E9)],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border(
                                  top: const BorderSide(color: Color(0xFFFF9933), width: 2),
                                  bottom: const BorderSide(color: Color(0xFF138808), width: 2),
                                  left: BorderSide(color: Colors.blue.shade200, width: 1),
                                  right: BorderSide(color: Colors.blue.shade200, width: 1),
                                ),
                              ),
                              child: const Row(children: [
                                Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        'Both parties must clear this transaction before it can be deleted.',
                                        style: TextStyle(
                                            color: Color(0xFF1565C0),
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic))),
                              ]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Classes moved from view_secure_transactions_page.dart
// ---------------------------------------------------------------------------

class PartialPaymentDialog extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final VoidCallback onPaymentComplete;

  const PartialPaymentDialog({
    Key? key,
    required this.transaction,
    required this.onPaymentComplete,
  }) : super(key: key);

  @override
  _PartialPaymentDialogState createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<PartialPaymentDialog> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController();
  final TextEditingController _lenderOtpController = TextEditingController();
  final TextEditingController _borrowerOtpController =
      TextEditingController();

  String? lenderEmail;
  String? borrowerEmail;
  String? paidBy;
  bool lenderOtpSent = false;
  bool borrowerOtpSent = false;
  bool lenderOtpVerified = false;
  bool borrowerOtpVerified = false;
  bool isProcessing = false;
  bool isSendingLenderOtp = false;
  bool isSendingBorrowerOtp = false;
  bool isVerifyingLenderOtp = false;
  bool isVerifyingBorrowerOtp = false;
  String? message;
  bool isMessageError = false;

  int lenderOtpSecondsLeft = 0;
  int borrowerOtpSecondsLeft = 0;
  bool lenderOtpExpired = false;
  bool borrowerOtpExpired = false;
  Timer? _otpTimer;

  @override
  void initState() {
    super.initState();
    _initializeEmails();
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _checkOtpExpiration();
    });
  }

  void _initializeEmails() {
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final userEmail = user?['email'];

    if (widget.transaction['role'] == 'lender') {
      lenderEmail = widget.transaction['userEmail'];
      borrowerEmail = widget.transaction['counterpartyEmail'];
    } else {
      lenderEmail = widget.transaction['counterpartyEmail'];
      borrowerEmail = widget.transaction['userEmail'];
    }

    if (userEmail == lenderEmail) {
      paidBy = 'lender';
    } else if (userEmail == borrowerEmail) {
      paidBy = 'borrower';
    }
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _amountController.dispose();
    _descriptionController.dispose();
    _lenderOtpController.dispose();
    _borrowerOtpController.dispose();
    super.dispose();
  }

  void _showMessage(String msg, {bool isError = false}) {
    setState(() {
      message = msg;
      isMessageError = isError;
    });
    Future.delayed(Duration(seconds: 3), () {
      if (mounted) setState(() => message = null);
    });
  }

  String _calculateRemainingAmount(Map transaction) {
    double original = transaction['amount']?.toDouble() ?? 0.0;
    double paid = 0.0;
    bool isFullyCleared = (transaction['userCleared'] == true &&
        transaction['counterpartyCleared'] == true);
    if (isFullyCleared) {
      paid = original;
    } else if (transaction['isPartiallyPaid'] == true &&
        transaction['partialPayments'] != null) {
      List pp = transaction['partialPayments'] as List;
      paid = pp.fold<double>(
          0, (s, p) => s + (p['amount'] as num).toDouble());
    }
    double remaining = original - paid;
    if (paid >= original) return '0.00';
    if (transaction['interestType'] != null &&
        transaction['interestRate'] != null) {
      final txDate = DateTime.tryParse(transaction['date'] ?? '');
      if (txDate != null) {
        final days = DateTime.now().difference(txDate).inDays;
        if (days > 0) {
          final rate = transaction['interestRate']?.toDouble() ?? 0.0;
          if (transaction['interestType'] == 'simple') {
            remaining = remaining + (remaining * rate * days / 365);
          } else if (transaction['interestType'] == 'compound') {
            final n =
                transaction['compoundingFrequency']?.toInt() ?? 1;
            remaining = remaining * pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return remaining.toStringAsFixed(2);
  }

  void _checkOtpExpiration() {
    if (lenderOtpSecondsLeft > 0 && lenderOtpSent && !lenderOtpVerified) {
      setState(() => lenderOtpSecondsLeft--);
      if (lenderOtpSecondsLeft == 0) {
        setState(() => lenderOtpExpired = true);
        _showMessage('Lender OTP has expired. Please resend.',
            isError: true);
      }
    }
    if (borrowerOtpSecondsLeft > 0 &&
        borrowerOtpSent &&
        !borrowerOtpVerified) {
      setState(() => borrowerOtpSecondsLeft--);
      if (borrowerOtpSecondsLeft == 0) {
        setState(() => borrowerOtpExpired = true);
        _showMessage('Borrower OTP has expired. Please resend.',
            isError: true);
      }
    }
  }

  Future<void> _sendOtp(String email, bool isLender) async {
    setState(() {
      if (isLender) {
        isSendingLenderOtp = true;
      } else {
        isSendingBorrowerOtp = true;
      }
    });
    try {
      final response = await ApiClient.post(
          '/api/transactions/send-partial-payment-otp',
          body: {'email': email});
      if (response.statusCode == 200) {
        setState(() {
          if (isLender) {
            lenderOtpSent = true;
            lenderOtpSecondsLeft = 120;
            lenderOtpExpired = false;
            isSendingLenderOtp = false;
          } else {
            borrowerOtpSent = true;
            borrowerOtpSecondsLeft = 120;
            borrowerOtpExpired = false;
            isSendingBorrowerOtp = false;
          }
        });
        _showMessage(
            'OTP sent to ${isLender ? 'lender' : 'borrower'} email');
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showMessage(data['error'] ?? 'Failed to send OTP', isError: true);
        setState(() {
          if (isLender) {
            isSendingLenderOtp = false;
          } else {
            isSendingBorrowerOtp = false;
          }
        });
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
      setState(() {
        if (isLender) {
          isSendingLenderOtp = false;
        } else {
          isSendingBorrowerOtp = false;
        }
      });
    }
  }

  Future<void> _verifyOtp(
      String email, String otp, bool isLender) async {
    if (isLender && lenderOtpExpired) {
      _showMessage('Lender OTP has expired. Please resend.',
          isError: true);
      return;
    }
    if (!isLender && borrowerOtpExpired) {
      _showMessage('Borrower OTP has expired. Please resend.',
          isError: true);
      return;
    }
    setState(() {
      if (isLender) {
        isVerifyingLenderOtp = true;
      } else {
        isVerifyingBorrowerOtp = true;
      }
    });
    try {
      final response = await ApiClient.post(
          '/api/transactions/verify-partial-payment-otp',
          body: {'email': email, 'otp': otp});
      if (response.statusCode == 200) {
        setState(() {
          if (isLender) {
            lenderOtpVerified = true;
            isVerifyingLenderOtp = false;
          } else {
            borrowerOtpVerified = true;
            isVerifyingBorrowerOtp = false;
          }
        });
        _showMessage(
            'OTP verified for ${isLender ? 'lender' : 'borrower'}');
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showMessage(data['error'] ?? 'Failed to verify OTP',
            isError: true);
        setState(() {
          if (isLender) {
            isVerifyingLenderOtp = false;
          } else {
            isVerifyingBorrowerOtp = false;
          }
        });
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
      setState(() {
        if (isLender) {
          isVerifyingLenderOtp = false;
        } else {
          isVerifyingBorrowerOtp = false;
        }
      });
    }
  }

  Future<void> _processPartialPayment() async {
    if (!lenderOtpVerified || !borrowerOtpVerified) {
      _showMessage('Both parties must verify their OTP', isError: true);
      return;
    }
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      _showMessage('Please enter a valid amount', isError: true);
      return;
    }
    final remainingAmount =
        double.tryParse(_calculateRemainingAmount(widget.transaction)) ??
            0.0;
    if (amount > remainingAmount) {
      _showMessage(
          'Payment amount cannot exceed remaining amount of ${remainingAmount.toStringAsFixed(2)} ${widget.transaction['currency']}',
          isError: true);
      return;
    }
    setState(() => isProcessing = true);
    try {
      final response =
          await ApiClient.post('/api/transactions/partial-payment', body: {
        'transactionId': widget.transaction['transactionId'],
        'amount': amount,
        'description': _descriptionController.text,
        'paidBy': paidBy,
        'lenderEmail': lenderEmail,
        'borrowerEmail': borrowerEmail,
        'lenderOtpVerified': lenderOtpVerified,
        'borrowerOtpVerified': borrowerOtpVerified,
      });
      if (response.statusCode == 200) {
        _showMessage('Partial payment processed successfully');
        Future.delayed(Duration(seconds: 2), () {
          Navigator.pop(context);
          widget.onPaymentComplete();
        });
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        _showMessage(data['error'] ?? 'Failed to process partial payment',
            isError: true);
      }
    } catch (e) {
      _showMessage('Network error: ${e.toString()}', isError: true);
    } finally {
      setState(() => isProcessing = false);
    }
  }

  Widget _otpSection({
    required String title,
    required String? email,
    required bool otpSent,
    required bool otpVerified,
    required bool otpExpired,
    required int otpSecondsLeft,
    required bool isSending,
    required bool isVerifying,
    required TextEditingController otpController,
    required bool isLender,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lock_clock, color: Color(0xFF00B4D8), size: 20),
            SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
          SizedBox(height: 8),
          Text('Email: ${email ?? ''}'),
          SizedBox(height: 8),
          if (otpSent) ...[
            Text('Enter the 6-digit OTP sent to $email:',
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
            SizedBox(height: 12),
            OtpInput(
              onChanged: (val) => otpController.text = val,
              enabled: otpSent,
              autoFocus: false,
            ),
            SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (email != null &&
                        !isSending &&
                        !otpVerified &&
                        (!otpSent || otpExpired))
                    ? () => _sendOtp(email, isLender)
                    : null,
                child: isSending
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 8),
                        Text('Sending OTP...'),
                      ])
                    : otpVerified
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.check_circle,
                                color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text('Verified'),
                          ])
                        : otpExpired
                            ? Text('Resend OTP')
                            : Text('Send OTP'),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        otpVerified ? Colors.green : Colors.orange),
              ),
            ),
          ]),
          if (otpSent && !otpVerified) ...[
            SizedBox(height: 4),
            Row(children: [
              Icon(otpExpired ? Icons.warning : Icons.timer,
                  color: otpExpired ? Colors.red : Colors.orange,
                  size: 14),
              SizedBox(width: 4),
              Text(
                otpExpired
                    ? 'OTP expired. Please resend.'
                    : 'OTP expires in ${otpSecondsLeft ~/ 60}:${(otpSecondsLeft % 60).toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 12,
                    color: otpExpired ? Colors.red : Colors.orange),
              ),
            ]),
          ],
          if (message != null &&
              ((isLender &&
                      (message!.contains('lender') ||
                          message!.contains('Lender'))) ||
                  (!isLender &&
                      (message!.contains('borrower') ||
                          message!.contains('Borrower'))))) ...[
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMessageError
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: isMessageError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(
                    isMessageError ? Icons.error : Icons.check_circle,
                    color: isMessageError ? Colors.red : Colors.green,
                    size: 16),
                SizedBox(width: 6),
                Expanded(
                    child: Text(message!,
                        style: TextStyle(
                            color: isMessageError
                                ? Colors.red[700]
                                : Colors.green[700],
                            fontWeight: FontWeight.w500,
                            fontSize: 12))),
              ]),
            ),
          ],
          if (otpSent && !otpVerified) ...[
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: (!isVerifying)
                  ? () => _verifyOtp(email!, otpController.text, isLender)
                  : null,
              child: isVerifying
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 8),
                      Text('Verifying OTP...'),
                    ])
                  : Text('Verify OTP'),
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFF8F6FA),
        child: Container(
          width: 400,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(Icons.payment, color: Color(0xFF00B4D8), size: 28),
                  SizedBox(width: 12),
                  Text('Partial Payment',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                SizedBox(height: 20),
                TextFormField(
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: 'Payment Amount',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                    helperText: (lenderOtpVerified && borrowerOtpVerified)
                        ? 'Amount locked after OTP verification'
                        : 'Maximum: ${_calculateRemainingAmount(widget.transaction)} ${widget.transaction['currency']}',
                    helperMaxLines: 2,
                  ),
                  keyboardType:
                      TextInputType.numberWithOptions(decimal: true),
                  enabled: !(lenderOtpVerified && borrowerOtpVerified),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.description),
                    helperText: (lenderOtpVerified && borrowerOtpVerified)
                        ? 'Description locked after OTP verification'
                        : null,
                  ),
                  maxLines: 2,
                  enabled: !(lenderOtpVerified && borrowerOtpVerified),
                ),
                SizedBox(height: 20),
                _otpSection(
                  title: 'Lender OTP Verification',
                  email: lenderEmail,
                  otpSent: lenderOtpSent,
                  otpVerified: lenderOtpVerified,
                  otpExpired: lenderOtpExpired,
                  otpSecondsLeft: lenderOtpSecondsLeft,
                  isSending: isSendingLenderOtp,
                  isVerifying: isVerifyingLenderOtp,
                  otpController: _lenderOtpController,
                  isLender: true,
                ),
                SizedBox(height: 16),
                _otpSection(
                  title: 'Borrower OTP Verification',
                  email: borrowerEmail,
                  otpSent: borrowerOtpSent,
                  otpVerified: borrowerOtpVerified,
                  otpExpired: borrowerOtpExpired,
                  otpSecondsLeft: borrowerOtpSecondsLeft,
                  isSending: isSendingBorrowerOtp,
                  isVerifying: isVerifyingBorrowerOtp,
                  otpController: _borrowerOtpController,
                  isLender: false,
                ),
                SizedBox(height: 20),
                if (message != null &&
                    !message!.contains('lender') &&
                    !message!.contains('Lender') &&
                    !message!.contains('borrower') &&
                    !message!.contains('Borrower')) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMessageError
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isMessageError
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(
                          isMessageError
                              ? Icons.error
                              : Icons.check_circle,
                          color:
                              isMessageError ? Colors.red : Colors.green,
                          size: 20),
                      SizedBox(width: 8),
                      Expanded(
                          child: Text(message!,
                              style: TextStyle(
                                  color: isMessageError
                                      ? Colors.red[700]
                                      : Colors.green[700],
                                  fontWeight: FontWeight.w500))),
                    ]),
                  ),
                  SizedBox(height: 16),
                ],
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                          onPressed: isProcessing
                              ? null
                              : () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green),
                          child: Text('Cancel')),
                      ElevatedButton(
                          onPressed: (lenderOtpVerified &&
                                  borrowerOtpVerified &&
                                  !isProcessing)
                              ? _processPartialPayment
                              : null,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green),
                          child: isProcessing
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : Text('Process Payment')),
                    ]),
              ],
            ),
          ),
        ));
  }
}

class PartialPaymentHistoryDialog extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final DisplayCurrencyData? displayCurrencyData;
  final String selectedDisplayCurrency;

  const PartialPaymentHistoryDialog({
    Key? key,
    required this.transaction,
    required this.displayCurrencyData,
    required this.selectedDisplayCurrency,
  }) : super(key: key);

  String _getPaidByEmail(Map payment, Map transaction) {
    String paidBy = payment['paidBy'] ?? '';
    if (paidBy == 'lender') return transaction['userEmail'] ?? 'Lender';
    if (paidBy == 'borrower')
      return transaction['counterpartyEmail'] ?? 'Borrower';
    return paidBy;
  }

  String _formatDisplayAmount(num amount, String? originalCurrency) {
    final src = (originalCurrency ?? 'INR').toUpperCase();
    final tgt = selectedDisplayCurrency.toUpperCase();
    final canConvert = displayCurrencyData?.canConvert(src, tgt) ??
        (src == tgt);
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

    return Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 400,
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.history, color: Colors.purple, size: 28),
                SizedBox(width: 12),
                Text('Partial Payment History',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple[700])),
              ]),
              SizedBox(height: 20),
              if (partialPayments.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('No partial payments yet.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: partialPayments.length,
                    itemBuilder: (ctx, i) {
                      final p = partialPayments[i] as Map;
                      final amount = (p['amount'] as num?) ?? 0;
                      final date = p['date']?.toString() ?? '';
                      final desc = p['description']?.toString() ?? '';
                      final paidByEmail =
                          _getPaidByEmail(p, transaction);
                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.payments,
                                    color: Colors.purple, size: 18),
                                SizedBox(width: 6),
                                Text(
                                    _formatDisplayAmount(
                                        amount, currency),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple[700],
                                        fontSize: 15)),
                              ]),
                              if (date.isNotEmpty) ...[
                                SizedBox(height: 4),
                                Text(
                                    'Date: ${date.length >= 10 ? date.substring(0, 10) : date}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700])),
                              ],
                              if (paidByEmail.isNotEmpty) ...[
                                SizedBox(height: 4),
                                Text('Paid by: $paidByEmail',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[700])),
                              ],
                              if (desc.isNotEmpty) ...[
                                SizedBox(height: 4),
                                Text('Note: $desc',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600])),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple),
                child: Text('Close',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ));
  }
}

class _TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.8);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.8);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.6, size.width, size.height * 0.8);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class _AttachmentCarouselDialog extends StatefulWidget {
  final List<Map<String, dynamic>> attachments;
  const _AttachmentCarouselDialog({required this.attachments});
  @override
  State<_AttachmentCarouselDialog> createState() =>
      _AttachmentCarouselDialogState();
}

class _AttachmentCarouselDialogState
    extends State<_AttachmentCarouselDialog> {
  int _currentIndex = 0;
  PageController? _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.attachments;
    return Dialog(
        backgroundColor: Colors.black,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 350,
          height: 420,
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: attachments.length,
                  onPageChanged: (i) =>
                      setState(() => _currentIndex = i),
                  itemBuilder: (ctx, i) {
                    final file = attachments[i];
                    if (file['type'] != null &&
                        file['type'].toString().startsWith('image/')) {
                      final bytes = base64Decode(file['data']);
                      return InteractiveViewer(
                          child: Image.memory(bytes,
                              fit: BoxFit.contain));
                    } else if (file['type'] == 'application/pdf') {
                      return Center(
                          child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                            Icon(Icons.picture_as_pdf,
                                size: 80, color: Colors.red),
                            SizedBox(height: 16),
                            Text(file['name'] ?? 'PDF',
                                style:
                                    TextStyle(color: Colors.white)),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: Icon(Icons.open_in_new),
                              label: Text('Open PDF'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal),
                              onPressed: () async {
                                final bytes =
                                    base64Decode(file['data']);
                                final tempDir =
                                    await getTemporaryDirectory();
                                final tempFile = File(
                                    '${tempDir.path}/${file['name'] ?? 'document.pdf'}');
                                await tempFile.writeAsBytes(bytes,
                                    flush: true);
                                await OpenFile.open(tempFile.path);
                              },
                            ),
                          ]));
                    }
                    return Center(
                        child: Text('Unsupported file',
                            style: TextStyle(color: Colors.white)));
                  },
                ),
              ),
              SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      attachments.length,
                      (i) => Container(
                            margin:
                                EdgeInsets.symmetric(horizontal: 4),
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _currentIndex
                                    ? Colors.teal
                                    : Colors.white24),
                          ))),
              SizedBox(height: 16),
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                        icon:
                            Icon(Icons.arrow_back_ios, color: Colors.white),
                        onPressed: () {
                          int newIndex =
                              (_currentIndex - 1 + attachments.length) %
                                  attachments.length;
                          _pageController?.animateToPage(newIndex,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.ease);
                        }),
                    IconButton(
                        icon: Icon(Icons.arrow_forward_ios,
                            color: Colors.white),
                        onPressed: () {
                          int newIndex =
                              (_currentIndex + 1) % attachments.length;
                          _pageController?.animateToPage(newIndex,
                              duration: Duration(milliseconds: 300),
                              curve: Curves.ease);
                        }),
                  ]),
              SizedBox(height: 8),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal),
                  child: Text('Close')),
            ],
          ),
        ));
  }
}

class _StylishProfileDialog extends StatelessWidget {
  final String title;
  final String name;
  final ImageProvider avatarProvider;
  final String? email;
  final String? phone;
  final String? gender;
  const _StylishProfileDialog(
      {required this.title,
      required this.name,
      required this.avatarProvider,
      this.email,
      this.phone,
      this.gender});

  @override
  Widget build(BuildContext context) {
    return Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
                color: Color(0xFF00B4D8),
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24))),
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [
              CircleAvatar(radius: 36, backgroundImage: avatarProvider),
              SizedBox(height: 12),
              Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      color: Colors.white)),
              SizedBox(height: 4),
              Text(title,
                  style:
                      TextStyle(fontSize: 14, color: Colors.white70)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 18),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (email != null) ...[
                    Row(children: [
                      Icon(Icons.email, size: 18, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(email!, style: TextStyle(fontSize: 16))
                    ]),
                    SizedBox(height: 10),
                  ],
                  if (phone != null && phone!.isNotEmpty) ...[
                    Row(children: [
                      Icon(Icons.phone, size: 18, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(phone!, style: TextStyle(fontSize: 16))
                    ]),
                    SizedBox(height: 10),
                  ],
                  if (gender != null) ...[
                    Row(children: [
                      Icon(Icons.transgender,
                          size: 18, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(gender!, style: TextStyle(fontSize: 16))
                    ]),
                    SizedBox(height: 10),
                  ],
                ]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF00B4D8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text('Close')),
          ),
        ]));
  }
}
