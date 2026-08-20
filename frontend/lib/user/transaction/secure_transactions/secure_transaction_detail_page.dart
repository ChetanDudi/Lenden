import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/currency_display.dart';
import '../../chats/chat_page.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../../utils/share_utils.dart';
import 'partial_payment_page.dart';
import 'partial_payment_history_page.dart';
import 'payment_timeline_page.dart';
import 'repayment_schedule_page.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/share_as_note_sheet.dart';

const _kStCategories = [
  {'key': 'food',          'label': 'Food',          'icon': Icons.restaurant_rounded},
  {'key': 'transport',     'label': 'Transport',     'icon': Icons.directions_car_rounded},
  {'key': 'accommodation', 'label': 'Stay',          'icon': Icons.hotel_rounded},
  {'key': 'entertainment', 'label': 'Fun',           'icon': Icons.sports_esports_rounded},
  {'key': 'shopping',      'label': 'Shopping',      'icon': Icons.shopping_cart_rounded},
  {'key': 'utilities',     'label': 'Utilities',     'icon': Icons.electrical_services_rounded},
  {'key': 'medical',       'label': 'Medical',       'icon': Icons.local_hospital_rounded},
  {'key': 'education',     'label': 'Education',     'icon': Icons.school_rounded},
  {'key': 'other',         'label': 'Other',         'icon': Icons.more_horiz_rounded},
];

IconData _stCatIcon(String? key) {
  final cat = _kStCategories.firstWhere((c) => c['key'] == key, orElse: () => _kStCategories.last);
  return cat['icon'] as IconData;
}

String _stCatLabel(String? key) {
  return (_kStCategories.firstWhere((c) => c['key'] == key, orElse: () => _kStCategories.last)['label'] as String);
}

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
    extends State<SecureTransactionDetailPage>
    with CurrencyDisplayMixin<SecureTransactionDetailPage> {
  late Map<String, dynamic> _t;
  DateTime _now = DateTime.now();
  Timer? _countdownTimer;
  bool _needsRefresh = false;
  bool _isCloseCounterparty = false;
  String? _counterpartyUserId;
  bool _togglingClose = false;

  @override
  void initState() {
    super.initState();
    _t = Map<String, dynamic>.from(widget.transaction);
    if (_t['favourite'] is List) {
      _t['favourite'] = List<dynamic>.from(_t['favourite']);
    } else {
      _t['favourite'] = <dynamic>[];
    }
    loadCurrencies();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _fetchCounterpartyInfo();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatDisplayAmount(num? amount, String? originalCurrency) {
    final numericAmount = (amount ?? 0).toDouble();
    final src = (originalCurrency ?? 'INR').toUpperCase();
    final tgt = selectedCurrency.toUpperCase();
    final canConvert =
        currencyData?.canConvert(src, tgt) ?? (src == tgt);
    if (!canConvert) {
      final sym = currencyData?.symbolFor(src) ?? src;
      return '$sym${numericAmount.toStringAsFixed(2)} $src';
    }
    final converted =
        currencyData?.convert(numericAmount, src, tgt) ?? numericAmount;
    final sym = currencyData?.symbolFor(tgt) ?? tgt;
    return '$sym${converted.toStringAsFixed(2)} $tgt';
  }

  bool _hasPartialPayment(Map t) {
    final pp = t['partialPayments'];
    return t['isPartiallyPaid'] == true || (pp is List && pp.isNotEmpty);
  }

  String _remainingTimeLabel(DateTime expectedReturnDate) {
    final tr = AppLocalizations.of(context).t;
    final diff = expectedReturnDate.difference(_now);
    if (diff.isNegative) {
      return tr('overdue_since_message').replaceFirst('{date}', DateFormat('MMM d').format(expectedReturnDate));
    }
    if (diff.inDays > 0) return tr('days_remaining_message').replaceFirst('{count}', '${diff.inDays}');
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    return tr('hms_remaining_message').replaceFirst('{h}', '$h').replaceFirst('{m}', '$m').replaceFirst('{s}', '$s');
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

  Future<void> _refreshTransaction() async {
    final tid = _t['transactionId'];
    if (tid == null) return;
    try {
      final res = await ApiClient.get('/api/transactions/${Uri.encodeComponent(tid.toString())}');
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final fresh = (body['transaction'] ?? body) as Map<String, dynamic>;
        setState(() {
          _t = Map<String, dynamic>.from(fresh);
          if (_t['favourite'] is List) {
            _t['favourite'] = List<dynamic>.from(_t['favourite']);
          } else {
            _t['favourite'] = <dynamic>[];
          }
          _needsRefresh = true;
        });
      }
    } catch (_) {}
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

  Future<void> _fetchCounterpartyInfo() async {
    final email = (_t['counterpartyEmail'] ?? '').toString();
    if (email.isEmpty) return;
    try {
      final profileRes = await ApiClient.get(
          '/api/users/profile-by-email?email=${Uri.encodeComponent(email)}');
      if (profileRes.statusCode == 200) {
        final profile = jsonDecode(profileRes.body) as Map<String, dynamic>;
        final userId = profile['_id']?.toString();
        if (userId != null && userId.isNotEmpty) {
          final favRes = await ApiClient.get('/api/user/favourites');
          if (favRes.statusCode == 200 && mounted) {
            final favData = jsonDecode(favRes.body);
            final closeList = (favData['closeCounterparties'] ?? []) as List;
            final isClose = closeList.any((item) {
              if (item is Map) return item['_id']?.toString() == userId;
              return item.toString() == userId;
            });
            setState(() {
              _counterpartyUserId = userId;
              _isCloseCounterparty = isClose;
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _toggleCloseCounterparty() async {
    if (_counterpartyUserId == null) return;
    setState(() => _togglingClose = true);
    try {
      final res = await ApiClient.post(
          '/api/user/favourites/close-counterparty/$_counterpartyUserId',
          body: {});
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _isCloseCounterparty = data['added'] == true);
        showSnack(context, data['message'] ?? 'Updated');
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _togglingClose = false);
    }
  }

  // "Pay Now" is now the same two-sided-OTP, real-wallet-transfer flow as
  // Partial Payment — just pre-filled with the full remaining amount — so
  // there is exactly one payment path for secure transactions and it always
  // requires both lender and borrower to verify OTP before any deduction.
  Future<void> _showPayNow() async {
    final tr = AppLocalizations.of(context).t;
    final remaining = double.tryParse(_calculateRemainingAmount(_t)) ?? 0;
    if (remaining <= 0) {
      if (mounted) {
        showSnack(context, tr('no_outstanding_balance_to_pay_message'), isError: true);
      }
      return;
    }
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PartialPaymentPage(
          transaction: Map<String, dynamic>.from(_t),
          isFullPayment: true,
        ),
      ),
    );
    if (result == true && mounted) {
      await _refreshTransaction();
    }
  }

  Future<void> _toggleFavourite() async {
    final tr = AppLocalizations.of(context).t;
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
        showSnack(context, tr('failed_to_update_favourite_message'), isError: true);
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
    final tr = AppLocalizations.of(context).t;
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
        showSnack(context, tr('transaction_cleared_message'));
      } else {
        showSnack(context, tr('failed_to_clear_transaction_message'), isError: true);
      }
    } catch (e) {
      showSnack(context, '${tr('network_error')}: $e', isError: true);
    }
  }

  Future<void> _deleteTransaction() async {
    final tr = AppLocalizations.of(context).t;
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
        showSnack(context, data?['error'] ?? tr('failed_to_delete_transaction'), isError: true);
      }
    } catch (e) {
      showSnack(context, '${tr('network_error')}: $e', isError: true);
    }
  }

  void _showDeleteConfirmationDialog() {
    final t = AppLocalizations.of(context).t;
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
                      clipper: const DeeperTopWaveClipper(),
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
                                    backgroundColor: AppThemeColors.cardBg(context),
                                    child: Icon(Icons.delete_forever,
                                        color: Colors.red[600], size: 40))))),
                  ]),
                  const SizedBox(height: 20),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(t('delete_transaction_title'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: Colors.red[600]))),
                  const SizedBox(height: 12),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                          t('confirm_delete_transaction_irreversible_message'))),
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
                                child: Text(t('cancel'))),
                            ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteTransaction();
                                },
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: Text(t('delete'),
                                    style: const TextStyle(color: Colors.white))),
                          ])),
                ],
              ),
            ));
  }

  void _navigateToChat() async {
    final tr = AppLocalizations.of(context).t;
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final currentEmail = user?['email'];
    final userEmail = _t['userEmail'];
    final counterpartyEmail = _t['counterpartyEmail'];
    final otherEmail =
        currentEmail == userEmail ? counterpartyEmail : userEmail;
    final profile = await _fetchCounterpartyProfile(otherEmail?.toString() ?? '');
    if (profile == null) {
      showSnack(context, tr('could_not_open_chat_user_not_found_message'), isError: true);
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
    final t = AppLocalizations.of(context).t;
    showDialog(
        context: context,
        builder: (ctx) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 20),
                Text(t('generate_receipt_label'),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Colors.blue[600])),
                const SizedBox(height: 12),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(t('choose_option_generate_receipt_message'),
                        textAlign: TextAlign.center)),
                const SizedBox(height: 20),
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                                icon: const Icon(Icons.email, color: Colors.white),
                                label: Text(t('send_to_email_label'),
                                    style: const TextStyle(color: Colors.white)),
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
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                                icon: const Icon(Icons.download,
                                    color: Colors.white),
                                label: Text(t('download_locally_label'),
                                    style: const TextStyle(color: Colors.white)),
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
                          ]),
                    )),
              ]),
            ));
  }

  void _sendReceiptByEmail() async {
    final tr = AppLocalizations.of(context).t;
    final email =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Text(tr('sending_to_email_message'))
                ]))));
    try {
      final res = await ApiClient.post(
          '/api/transactions/${_t['transactionId']}/receipt',
          body: {'email': email, 'action': 'email'});
      Navigator.pop(context);
      if (res.statusCode == 200) {
        showSnack(context, tr('receipt_sent_to_email_message'));
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        showSnack(context, data?['error'] ?? tr('failed_to_send_receipt_message'), isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      showSnack(context, '${tr('network_error')}: $e', isError: true);
    }
  }

  void _downloadReceiptLocally() async {
    final tr = AppLocalizations.of(context).t;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(width: 20),
                  Text(tr('downloading_locally_message'))
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
        showSnack(context, '${tr('receipt_downloaded_to_message')} ${file.path}');
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        showSnack(context, data?['error'] ?? tr('failed_to_download_message'), isError: true);
      }
    } catch (e) {
      Navigator.pop(context);
      showSnack(context, '${tr('network_error')}: $e', isError: true);
    }
  }

  void _showPartialPaymentDialog() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PartialPaymentPage(transaction: Map<String, dynamic>.from(_t)),
      ),
    );
    if (result == true && mounted) {
      await _refreshTransaction();
    }
  }

  void _showPartialPaymentHistoryDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PartialPaymentHistoryPage(
          transaction: _t,
          displayCurrencyData: currencyData,
          selectedDisplayCurrency: selectedCurrency,
        ),
      ),
    );
  }

  void _showRaiseDisputeDialog({required String counterpartyEmail}) {
    final tr = AppLocalizations.of(context).t;
    const disputeReasons = [
      'Payment not received',
      'Amount mismatch',
      'Wrong clearance marked',
      'Harassment or abusive behavior',
      'Other',
    ];
    String disputeReasonLabel(String r) {
      switch (r) {
        case 'Payment not received':
          return tr('payment_not_received_label');
        case 'Amount mismatch':
          return tr('amount_mismatch_label');
        case 'Wrong clearance marked':
          return tr('wrong_clearance_marked_label');
        case 'Harassment or abusive behavior':
          return tr('harassment_abusive_behavior_label');
        default:
          return tr('other');
      }
    }
    String reason = disputeReasons.first;
    final descriptionController = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.gavel_rounded, color: Colors.deepOrange, size: 26),
              const SizedBox(width: 8),
              Text(tr('raise_dispute_title')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('dispute_review_notice_message').replaceFirst('{email}', counterpartyEmail),
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: reason,
                  decoration: InputDecoration(labelText: tr('reason')),
                  items: disputeReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(disputeReasonLabel(r))))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => reason = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: tr('describe_what_happened_label'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      if (descriptionController.text.trim().isEmpty) {
                        showSnack(context, tr('please_describe_what_happened_message'), isError: true);
                        return;
                      }
                      setDialogState(() => submitting = true);
                      try {
                        final res = await ApiClient.post('/api/disputes', body: {
                          'transactionType': 'secure',
                          'transactionId': _t['_id'],
                          'reason': reason,
                          'description': descriptionController.text.trim(),
                        });
                        if (res.statusCode == 201) {
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          if (mounted) {
                            showSnack(context, tr('dispute_submitted_message'));
                          }
                        } else {
                          final data = jsonDecode(res.body);
                          setDialogState(() => submitting = false);
                          showSnack(context, (data['error'] ?? tr('failed_to_submit_dispute_message')).toString(), isError: true);
                        }
                      } catch (e) {
                        setDialogState(() => submitting = false);
                        showSnack(context, '${tr('error')}: $e', isError: true);
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(tr('submit'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
            AppColors.tricolorOrange,
            AppColors.tricolorOrange,
            Colors.white,
            Colors.white,
            AppColors.tricolorGreen,
            AppColors.tricolorGreen,
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
                style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 11)),
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
                    style: TextStyle(
                        fontSize: 11,
                        color: AppThemeColors.secondaryText(context),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppThemeColors.primaryText(context),
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
        Container(width: 4, height: 1, color: AppColors.tricolorOrange),
        Expanded(child: Container(height: 1, color: const Color(0xFFE3F2FD))),
        Container(width: 4, height: 1, color: AppColors.tricolorGreen),
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
        .map((p) => DateTime.tryParse(p['paidAt']?.toString() ?? ''))
        .whereType<DateTime>()
        .toList();
    if (dates.length < 2) return '—';
    dates.sort();
    double totalGap = 0;
    for (int i = 1; i < dates.length; i++) {
      totalGap += dates[i].difference(dates[i - 1]).inDays;
    }
    final avg = (totalGap / (dates.length - 1)).round();
    return AppLocalizations.of(context).t('every_approx_days_message').replaceFirst('{count}', '$avg');
  }

  int _daysOutstanding(Map t) {
    final createdAt = DateTime.tryParse(
        (t['createdAt'] ?? t['date'] ?? '').toString());
    if (createdAt == null) return 0;
    return _now.difference(createdAt).inDays;
  }

  void _copyTransactionId() {
    final tr = AppLocalizations.of(context).t;
    final id = _t['transactionId']?.toString() ?? '';
    Clipboard.setData(ClipboardData(text: id));
    showSnack(context, tr('transaction_id_copied_message'));
  }

  void _shareTransaction() {
    final tr = AppLocalizations.of(context).t;
    final t = _t;
    final role = widget.isLending ? tr('lent_label') : tr('borrowed_label');
    final amount =
        _formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString());
    final counterparty = t['counterpartyEmail'] ?? '—';
    final rawDate = t['date']?.toString() ?? '';
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final interest =
        (t['interestType'] != null && t['interestRate'] != null)
            ? '${t['interestType']} @ ${t['interestRate']}%'
            : tr('none_label');
    final remaining = _formatDisplayAmount(
        double.tryParse(_calculateRemainingAmount(t)) ?? 0,
        t['currency']?.toString());
    final txId = t['transactionId'] ?? '—';
    fetchAppInviteLink().then((appLink) {
      final footer = appLink.isNotEmpty ? '\n📥 $appLink' : '';
      Share.share(
        '📋 ${tr('transaction_summary_label')}\n'
        '-------------------\n'
        '$role: $amount\n'
        '${tr('counterparty_label')}: $counterparty\n'
        '${tr('date_label')}: $date\n'
        '${tr('interest_label')}: $interest\n'
        '${tr('remaining_label')}: $remaining\n'
        '${tr('id_label')}: $txId\n'
        '-------------------\n'
        '${tr('shared_via_lenden_message')}'
        '$footer',
        subject: '${tr('lenden_transaction_label')}: $amount',
      );
    });
  }

  void _shareTransactionAsNote() {
    final tr = AppLocalizations.of(context).t;
    final t = _t;
    final role = widget.isLending ? tr('lent_label') : tr('borrowed_label');
    final amount = _formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString());
    final counterparty = t['counterpartyEmail'] ?? '—';
    final rawDate = t['date']?.toString() ?? '';
    final date = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
    final remaining = _formatDisplayAmount(
        double.tryParse(_calculateRemainingAmount(t)) ?? 0, t['currency']?.toString());
    final content =
        '$role: $amount\n'
        '${tr('counterparty_label')}: $counterparty\n'
        '${tr('date_label')}: $date\n'
        '${tr('remaining_label')}: $remaining';
    showShareAsNoteSheet(context,
      title: '${tr('transaction_summary_label')} - $amount',
      content: content,
    );
  }

  void _showPaymentTimeline() {
    final t = _t;
    final fullyCleared = t['userCleared'] == true && t['counterpartyCleared'] == true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentTimelinePage(
          transaction: t,
          displayCurrencyData: currencyData,
          selectedDisplayCurrency: selectedCurrency,
          fullyCleared: fullyCleared,
        ),
      ),
    );
  }

  void _showRepaymentSchedule() {
    final tr = AppLocalizations.of(context).t;
    final t = _t;
    if (t['interestType'] == null || t['interestRate'] == null) {
      showSnack(context, tr('no_interest_on_transaction_message'));
      return;
    }
    final remaining = double.tryParse(_calculateRemainingAmount(t)) ?? 0.0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RepaymentSchedulePage(
          transaction: t,
          displayCurrencyData: currencyData,
          selectedDisplayCurrency: selectedCurrency,
          remainingAmount: remaining,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context).t;
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    final t = _t;
    final isLending = widget.isLending;
    // userCleared = creator's status, counterpartyCleared = other party's status.
    // Use creator identity — not isLending — to map cleared fields correctly.
    final isCreator = (email != null && email == t['userEmail']);
    final youCleared =
        (isCreator ? t['userCleared'] : t['counterpartyCleared']) == true;
    final otherCleared =
        (isCreator ? t['counterpartyCleared'] : t['userCleared']) == true;
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
        backgroundColor: AppThemeColors.scaffoldBg(context),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(loc('transaction_detail_title'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_needsRefresh),
          ),
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isLending
                          ? [Colors.teal, Colors.teal.shade700]
                          : [Colors.orange, Colors.orange.shade700],
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
                              ? loc('lending_you_gave_money_label')
                              : loc('borrowing_you_took_money_label'),
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
                            child: Text(loc('partial_label'),
                                style: const TextStyle(
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
                                ? loc('fully_cleared_label')
                                : hasPartialPayment
                                    ? loc('partially_paid_label')
                                    : (youCleared && !otherCleared)
                                        ? loc('you_cleared_label')
                                        : (!youCleared && otherCleared)
                                            ? loc('other_cleared_label')
                                            : loc('uncleared_label'),
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
                          child: Text('${loc('counterparty_label')}: $counterpartyEmail',
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
                      Text(loc('days_outstanding_label').replaceFirst('{count}', '${_daysOutstanding(t)}'),
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
                                    '+${_formatDisplayAmount(_calculateDailyInterestAccrual(t), t['currency']?.toString())}/${loc('per_day_label')}',
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
                                      '${loc('you_colon_label')} ${youCleared ? '${loc('cleared_check_label')} ✓' : loc('pending_label')}',
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
                                      '${loc('them_colon_label')} ${otherCleared ? '${loc('cleared_check_label')} ✓' : loc('pending_label')}',
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
                          label: loc('pay_now_label'),
                          color: const Color(0xFF023E8A),
                          onTap: _showPayNow),
                    if (isBorrower && !fullyCleared)
                      _serviceChip(
                          icon: Icons.payment,
                          label: loc('partial_pay_label'),
                          color: Colors.purple,
                          onTap: _showPartialPaymentDialog),
                    _serviceChip(
                        icon: Icons.history,
                        label: loc('pay_history_label'),
                        color: Colors.indigo,
                        onTap: _showPartialPaymentHistoryDialog),
                    _serviceChip(
                        icon: Icons.receipt_long,
                        label: loc('receipt_label'),
                        color: Colors.green,
                        onTap: _showReceiptOptionsDialog),
                    _serviceChip(
                        icon: Icons.chat_bubble_outline,
                        label: loc('chat'),
                        color: Colors.blue,
                        onTap: _navigateToChat),
                    _serviceChip(
                        icon: Icons.gavel_rounded,
                        label: loc('raise_dispute'),
                        color: Colors.deepOrange,
                        onTap: () => _showRaiseDisputeDialog(
                            counterpartyEmail: counterpartyEmail)),
                    if (!youCleared)
                      _serviceChip(
                          icon: Icons.check_circle_outline,
                          label: loc('clear'),
                          color: Colors.orange,
                          onTap: _clearTransaction),
                    _serviceChip(
                        icon: isFav
                            ? Icons.favorite
                            : Icons.favorite_border,
                        label: isFav ? loc('unfavourite_label') : loc('favourite_label'),
                        color: Colors.red,
                        onTap: _toggleFavourite),
                    if (attachments.isNotEmpty)
                      _serviceChip(
                          icon: Icons.attach_file,
                          label: loc('attachments_label'),
                          color: Colors.teal,
                          badge: attachments.length,
                          onTap: () => showDialog(
                              context: context,
                              builder: (_) => _AttachmentCarouselDialog(
                                  attachments: attachments))),
                    if (fullyCleared)
                      _serviceChip(
                          icon: Icons.delete_forever,
                          label: loc('delete'),
                          color: Colors.red,
                          onTap: _showDeleteConfirmationDialog),
                    _serviceChip(
                        icon: Icons.share,
                        label: loc('share_label'),
                        color: Colors.deepPurple,
                        onTap: _shareTransaction),
                    _serviceChip(
                        icon: Icons.note_add_rounded,
                        label: 'As Note',
                        color: AppColors.tricolorGreen,
                        onTap: _shareTransactionAsNote),
                    _serviceChip(
                        icon: Icons.timeline,
                        label: loc('timeline_label'),
                        color: Colors.cyan,
                        onTap: _showPaymentTimeline),
                    if (t['interestType'] != null &&
                        t['interestRate'] != null)
                      _serviceChip(
                          icon: Icons.table_chart,
                          label: loc('schedule_label'),
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
                        loc('principal_label'),
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
                          loc('with_interest_label'),
                          Icons.percent,
                          Colors.blue),
                    _statCard(
                        _formatDisplayAmount(
                            double.tryParse(
                                    _calculateAmountPaidTillNow(t)) ??
                                0,
                            t['currency']?.toString()),
                        loc('amount_paid_label'),
                        Icons.payments,
                        Colors.teal),
                    _statCard(
                        _formatDisplayAmount(
                            double.tryParse(
                                    _calculateRemainingAmount(t)) ??
                                0,
                            t['currency']?.toString()),
                        loc('remaining_label'),
                        Icons.account_balance_wallet,
                        Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Pay Now amount card
              if (!fullyCleared)
                Builder(builder: (_) {
                  final payNowAmount =
                      double.tryParse(_calculateRemainingAmount(t)) ?? 0.0;
                  final paidSoFar =
                      double.tryParse(_calculateAmountPaidTillNow(t)) ?? 0.0;
                  final hasPartial =
                      t['isPartiallyPaid'] == true && paidSoFar > 0;
                  final partialCount = hasPartial
                      ? ((t['partialPayments'] as List?)?.length ?? 0)
                      : 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.indigo.shade50,
                          Colors.blue.shade50,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.indigo.shade200),
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
                          Icon(Icons.flash_on,
                              color: Colors.indigo.shade600, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            loc('pay_now_amount_label'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatDisplayAmount(payNowAmount,
                                  t['currency']?.toString()),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                hasPartial
                                    ? loc('remaining_after_partial_payments_message').replaceFirst('{count}', '$partialCount')
                                    : loc('full_amount_to_settle_label'),
                                style: TextStyle(
                                    color: AppThemeColors.secondaryText(context), fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        if (hasPartial) ...[
                          const SizedBox(height: 10),
                          Divider(color: Colors.indigo.shade100, height: 1),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(loc('already_paid_label'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                              Text(
                                _formatDisplayAmount(paidSoFar,
                                    t['currency']?.toString()),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(loc('pay_now_remaining_label'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                              Text(
                                _formatDisplayAmount(payNowAmount,
                                    t['currency']?.toString()),
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.indigo.shade700),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),

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
                    color: AppThemeColors.cardBg(context),
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
                          Text(loc('repayment_progress_label'),
                              style: const TextStyle(
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
                          backgroundColor: AppThemeColors.divider(context),
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
                              style: TextStyle(
                                  fontSize: 11, color: AppThemeColors.mutedText(context))),
                          Text(
                              _formatDisplayAmount(totalWithInterest,
                                  t['currency']?.toString()),
                              style: TextStyle(
                                  fontSize: 11, color: AppThemeColors.mutedText(context))),
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
                  color: AppThemeColors.cardBg(context),
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
                          Expanded(child: Container(height: 5, color: AppColors.tricolorOrange)),
                          Expanded(child: Container(height: 5, color: Colors.white)),
                          Expanded(child: Container(height: 5, color: AppColors.tricolorGreen)),
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
                                    colors: [AppColors.cyan, Color(0xFF0077B6)],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.receipt_long, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(loc('transaction_details_label'),
                                  style: const TextStyle(
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
                                    loc('date'), t['date']?.toString().substring(0, 10) ?? '—'),
                                _detailDivider(),
                                _detailRow(Icons.access_time, const Color(0xFF7B1FA2),
                                    loc('time'), t['time']?.toString() ?? '—'),
                                _detailDivider(),
                                _detailRow(Icons.place, const Color(0xFF9C27B0),
                                    loc('place_label'), (t['place'] ?? '').toString().isNotEmpty ? t['place'].toString() : '—'),
                                _detailDivider(),
                                _detailDivider(),
                                GestureDetector(
                                  onTap: _copyTransactionId,
                                  child: _detailRow(
                                      Icons.confirmation_number,
                                      AppThemeColors.secondaryText(context),
                                      loc('transaction_id_label'),
                                      '${t['transactionId'] ?? '—'}  📋'),
                                ),
                                _detailDivider(),
                                _detailRow(
                                    Icons.history_toggle_off,
                                    Colors.blue.shade400,
                                    loc('days_outstanding_title'),
                                    loc('days_count_label').replaceFirst('{count}', '${_daysOutstanding(t)}')),
                                if (_hasPartialPayment(t) &&
                                    ((_t['partialPayments'] as List?)
                                                ?.length ??
                                            0) >
                                        1) ...[
                                  _detailDivider(),
                                  _detailRow(Icons.speed, Colors.purple,
                                      loc('payment_velocity_label'),
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
                                                title: loc('counterparty_info_label'),
                                                name: loc('no_profile_found_message'),
                                                avatarProvider: const AssetImage('assets/Other.png'));
                                          }
                                          if (profile['deactivatedAccount'] == true) {
                                            return _StylishProfileDialog(
                                                title: loc('counterparty_info_label'),
                                                name: loc('account_deactivated_label'),
                                                avatarProvider: const AssetImage('assets/Other.png'));
                                          }
                                          if (profile['profileIsPrivate'] == true) {
                                            return _StylishProfileDialog(
                                                title: loc('counterparty_info_label'),
                                                name: loc('profile_is_private_message'),
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
                                              title: loc('counterparty_label'),
                                              name: profile['name'] ?? loc('counterparty_label'),
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
                                  left: const BorderSide(color: AppColors.tricolorOrange, width: 4),
                                  top: BorderSide(color: Colors.orange.shade100, width: 1),
                                  bottom: BorderSide(color: Colors.green.shade100, width: 1),
                                  right: const BorderSide(color: AppColors.tricolorGreen, width: 4),
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
                                        Text(loc('counterparty_label'),
                                            style: const TextStyle(
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
                          if (_counterpartyUserId != null) ...[
                            const SizedBox(height: 8),
                            ActionChip(
                              avatar: Icon(
                                _isCloseCounterparty ? Icons.person_pin_rounded : Icons.person_add_alt_1_rounded,
                                size: 16,
                                color: _isCloseCounterparty ? AppColors.cyan : AppThemeColors.secondaryText(context),
                              ),
                              label: Text(
                                _isCloseCounterparty ? 'Close Counterparty' : 'Add as Close',
                                style: TextStyle(fontSize: 12, color: _isCloseCounterparty ? AppColors.cyan : AppThemeColors.secondaryText(context)),
                              ),
                              onPressed: _togglingClose ? null : _toggleCloseCounterparty,
                              backgroundColor: _isCloseCounterparty
                                  ? AppColors.cyan.withValues(alpha: 0.1)
                                  : AppThemeColors.surfaceBg(context),
                              side: BorderSide(color: _isCloseCounterparty ? AppColors.cyan.withValues(alpha: 0.3) : Colors.transparent),
                            ),
                          ],
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
                                      loc('interest_label'),
                                      '${t['interestType'] == 'simple' ? loc('simple_label') : loc('compound_label')} @ ${t['interestRate']}%'),
                                  if (t['expectedReturnDate'] != null) ...[
                                    _detailDivider(),
                                    _detailRow(Icons.calendar_month, Colors.teal,
                                        loc('return_date_label'),
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
                                        Text(loc('description_label'),
                                            style: const TextStyle(
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
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.22)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_stCatIcon((t['category'] ?? 'other').toString()), size: 16, color: Colors.deepPurple),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Category', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w500)),
                                    Text(_stCatLabel((t['category'] ?? 'other').toString()),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.deepPurple)),
                                  ],
                                ),
                              ],
                            ),
                          ),
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
                                  top: const BorderSide(color: AppColors.tricolorOrange, width: 2),
                                  bottom: const BorderSide(color: AppColors.tricolorGreen, width: 2),
                                  left: BorderSide(color: Colors.blue.shade200, width: 1),
                                  right: BorderSide(color: Colors.blue.shade200, width: 1),
                                ),
                              ),
                              child: Row(children: [
                                const Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        loc('both_parties_must_clear_message'),
                                        style: const TextStyle(
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
          ],
        ),
      ),
    );
  }
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
    final loc = AppLocalizations.of(context).t;
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
                            Text(file['name'] ?? loc('pdf_label'),
                                style:
                                    TextStyle(color: Colors.white)),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              icon: Icon(Icons.open_in_new),
                              label: Text(loc('open_pdf_label')),
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
                        child: Text(loc('unsupported_file_label'),
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
                  child: Text(loc('close'))),
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
    final loc = AppLocalizations.of(context).t;
    return Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
                color: AppColors.cyan,
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
                    backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Text(loc('close'))),
          ),
        ]));
  }
}
