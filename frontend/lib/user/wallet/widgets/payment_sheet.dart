import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../lenden_wallet_page.dart';
import 'wallet_auth_step.dart';

class LendenPaymentHelper {
  // Shows a wallet-only "confirm & pay" sheet. The actual POST is made by the
  // caller-supplied payEndpoint + payBody — each module (quick transactions,
  // group expenses) owns its own atomic pay endpoint that performs the wallet
  // transfer and its own bookkeeping together server-side, so this sheet is
  // just a thin confirm-and-call UI, not a payment method chooser. Secure
  // Transactions don't use this sheet at all — they go through the two-sided
  // OTP partial-payment flow instead.
  static Future<void> showPaymentSheet(
    BuildContext context, {
    required String counterpartyEmail,
    required double amount,
    required String description,
    required String payEndpoint,
    Map<String, dynamic> payBody = const {},
    VoidCallback? onSuccess,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentSheet(
        counterpartyEmail: counterpartyEmail,
        amount: amount,
        description: description,
        payEndpoint: payEndpoint,
        payBody: payBody,
        onSuccess: onSuccess,
      ),
    );
  }
}

class PaymentSheet extends StatefulWidget {
  final String counterpartyEmail;
  final double amount;
  final String description;
  final String payEndpoint;
  final Map<String, dynamic> payBody;
  final VoidCallback? onSuccess;

  const PaymentSheet({
    super.key,
    required this.counterpartyEmail,
    required this.amount,
    required this.description,
    required this.payEndpoint,
    required this.payBody,
    this.onSuccess,
  });

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  bool _paying = false;
  String? _error;
  bool _insufficientBalance = false;
  bool _showAuth = false;
  bool _hasPinSet = false;

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _hasPinSet = data['hasPin'] == true);
      }
    } catch (_) {}
  }

  Future<void> _pay(String authField, String authCredential) async {
    final t = AppLocalizations.of(context).t;
    setState(() {
      _paying = true;
      _error = null;
      _insufficientBalance = false;
    });
    try {
      final body = Map<String, dynamic>.from(widget.payBody)
        ..addAll({authField: authCredential});
      final res = await ApiClient.post(widget.payEndpoint, body: body);
      if (!mounted) return;
      setState(() => _paying = false);
      if (res.statusCode == 200) {
        Navigator.pop(context);
        widget.onSuccess?.call();
      } else {
        final err = jsonDecode(res.body);
        final errMsg = (err['error'] ?? t('payment_failed_label')).toString();
        setState(() {
          _showAuth = false;
          _error = errMsg;
          _insufficientBalance = errMsg.toLowerCase().contains('insufficient');
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _paying = false;
          _showAuth = false;
          _error = t('error_colon_label').replaceFirst('{error}', '$e');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tricolor sheet handle
          Center(
              child: Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.white, Colors.green]),
              borderRadius: BorderRadius.circular(3),
            ),
          )),
          const SizedBox(height: 18),
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xFFFF8000).withValues(alpha: 0.12),
                  shape: BoxShape.circle),
              child: const Icon(Icons.payments_rounded,
                  color: Color(0xFFFF8000), size: 22),
            ),
            const SizedBox(width: 10),
            Text(t('pay_now_label'),
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF8000))),
          ]),
          const SizedBox(height: 16),
          // Amount & details — tricolor border card
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: const Color(0xFFF0F7FF),
                    dark: const Color(0xFF16323A)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AppColors.cyan),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(widget.counterpartyEmail,
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              color: AppThemeColors.primaryText(context)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.currency_rupee,
                      size: 16, color: Color(0xFFFF8000)),
                  const SizedBox(width: 6),
                  Text('₹${widget.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF8000))),
                ]),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.note_outlined,
                        size: 16, color: AppThemeColors.mutedText(context)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(widget.description,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppThemeColors.secondaryText(context)))),
                  ]),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 20),

          if (_showAuth) ...[
            // Auth step — user verifies via PIN or Email OTP before the debit.
            WalletAuthStep(
              hasPinSet: _hasPinSet,
              onAuthenticated: (authField, credential) =>
                  _pay(authField, credential),
              onBack: () => setState(() {
                _showAuth = false;
                _error = null;
              }),
              paying: _paying,
            ),
          ] else ...[
            // Pay button — tapping opens the auth step rather than paying immediately.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white),
                label: Text(t('pay_via_lenden_wallet_label'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white)),
                onPressed: () => setState(() {
                  _showAuth = true;
                  _error = null;
                }),
              ),
            ),

            if (_error != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                        child: Text(_error!,
                            style: const TextStyle(
                                color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ),
              if (_insufficientBalance) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cyan, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.add_card_rounded,
                        color: AppColors.cyan),
                    label: Text(t('add_money_label'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.cyan)),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const LendenWalletPage(autoOpenAddMoney: true)),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
