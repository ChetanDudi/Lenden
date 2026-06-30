import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../otp_input.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/group_transactions/group_transaction_page.dart';
import '../transaction/secure_transactions/view_secure_transactions_page.dart';
import '../digitise/subscriptions_page.dart';
import '../support/help_support_page.dart';
import '../support/contact_page.dart';
import '../../widgets/payment_success_page.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

// Razorpay only works on Android/iOS — not on Windows, Web, or macOS.
bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// Test mode hint shown in all Razorpay payment sheets.
Widget _testModeHint(BuildContext context) {
  final t = AppLocalizations.of(context).t;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppThemeColors.tinted(context, light: const Color(0xFFFFF8E1), dark: const Color(0xFF4A3F1F)),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFFCC02), width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.science_rounded, size: 14, color: Color(0xFFF57F17)),
          const SizedBox(width: 6),
          Text(t('test_mode_credentials_hint'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
        ]),
        const SizedBox(height: 4),
        _testRow(Icons.credit_card_rounded, t('test_card_label'), '4111 1111 1111 1111  |  Exp: 12/28  |  CVV: 123  |  OTP: 1234'),
        const SizedBox(height: 2),
        _testRow(Icons.phone_android_rounded, t('test_upi_label'), 'success@razorpay'),
      ],
    ),
  );
}

Widget _testRow(IconData icon, String label, String value) => Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Icon(icon, size: 12, color: const Color(0xFF795548)),
    const SizedBox(width: 5),
    Text('$label: ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF795548))),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 11, color: Color(0xFF795548)))),
  ],
);

class LendenWalletPage extends StatefulWidget {
  const LendenWalletPage({super.key});

  @override
  State<LendenWalletPage> createState() => _LendenWalletPageState();
}

class _LendenWalletPageState extends State<LendenWalletPage> {
  bool _loading = true;
  double _walletBalance = 0;
  List<Map<String, dynamic>> _transactions = [];
  String? _razorpayPaymentLink;

  String t(String key) => AppLocalizations.of(context).t(key);

  Color _withdrawalStatusColor(String status) {
    switch (status) {
      case 'processed': return const Color(0xFF2E7D32);
      case 'failed': return Colors.red;
      case 'reversed': return Colors.orange;
      default: return AppColors.cyan;
    }
  }

  String _withdrawalStatusLabel(String status) {
    switch (status) {
      case 'processed': return t('status_processed_label');
      case 'failed': return t('status_failed_label');
      case 'reversed': return t('status_failed_label');
      default: return t('status_pending_label');
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchWalletData();
    _fetchPaymentConfig();
  }

  Future<void> _fetchPaymentConfig() async {
    try {
      final res = await ApiClient.get('/api/payment/config');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _razorpayPaymentLink = data['razorpayPaymentLink']);
      }
    } catch (_) {}
  }

  Future<void> _fetchWalletData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.get('/api/wallet/balance'),
        ApiClient.get('/api/wallet/history'),
      ]);
      final balRes = results[0];
      final histRes = results[1];
      if (balRes.statusCode == 200) {
        final data = jsonDecode(balRes.body);
        setState(() => _walletBalance = (data['balance'] ?? 0).toDouble());
      }
      if (histRes.statusCode == 200) {
        final data = jsonDecode(histRes.body);
        setState(() => _transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []));
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  void _showAddMoneySheet() {
    if (_razorpayPaymentLink == null) {
      showSnack(context, t('payment_config_unavailable_message'), isError: true);
      _fetchPaymentConfig();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddMoneyAmountSheet(
        onContinue: (amount) {
          Navigator.pop(ctx);
          _showAddMoneyConfirmSheet(amount);
        },
      ),
    );
  }

  // Dismiss-guarded, single-verification-path confirm step — exact structural
  // mirror of SubscriptionsPage._showManualPaymentSheet (PopScope guard,
  // isDismissible/enableDrag false, one atomic verify call, no background
  // polling racing against it).
  void _showAddMoneyConfirmSheet(double amount) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddMoneyConfirmSheet(
        amount: amount,
        paymentLink: _razorpayPaymentLink!,
        onCredited: () => _fetchWalletData(),
      ),
    );
  }

  void _showPayToUserSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayToUserSheet(
        walletBalance: _walletBalance,
        onSuccess: (amount, recipient) {
          _fetchWalletData();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentSuccessPage(
                title: t('payment_sent_title'),
                amount: amount,
                recipientName: recipient.isNotEmpty ? recipient : null,
                transactionType: t('lenden_wallet_transfer_label'),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showWithdrawSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WithdrawSheet(
        walletBalance: _walletBalance,
        onSuccess: (amount, {bool manualReview = false}) {
          final msg = manualReview
              ? '₹${amount.toStringAsFixed(2)} ${t('withdrawal_pending_admin_review_suffix')}'
              : '₹${amount.toStringAsFixed(2)} ${t('withdrawal_initiated_suffix')}';
          showSnack(context, msg);
          _fetchWalletData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF121212)),
      body: Stack(
        children: [
          // Header gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppThemeColors.waveGradient(context),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(t('lenden_wallet_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                          Text(t('store_send_real_money_subtitle'), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
                      onPressed: _fetchWalletData,
                    ),
                  ]),
                ),

                // ── Scrollable body ───────────────────────────────────
                Expanded(child: RefreshIndicator(
                  onRefresh: _fetchWalletData,
                  color: AppColors.cyan,
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(children: [

                // Balance card — tricolor border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: AppColors.cyan.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFF8000), size: 20),
                            const SizedBox(width: 7),
                            Text(t('lenden_wallet_balance_label'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.cyan)),
                          ]),
                          const SizedBox(height: 10),
                          _loading
                            ? const CircularProgressIndicator(color: AppColors.cyan)
                            : Text(
                                '₹${_walletBalance.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: AppColors.cyan),
                              ),
                          const SizedBox(height: 4),
                          Text(t('available_to_send_or_pay'), style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyan,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.add_rounded, color: Colors.white),
                                label: Text(t('add_money_label'), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                onPressed: _showAddMoneySheet,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFF8000), width: 1.8),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                icon: const Icon(Icons.send_rounded, color: Color(0xFFFF8000)),
                                label: Text(t('pay_user_label'), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
                                onPressed: _showPayToUserSheet,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF1B5E20), width: 1.8),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              icon: const Icon(Icons.account_balance_rounded, color: Color(0xFF1B5E20)),
                              label: Text(t('withdraw_to_bank_upi_label'), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                              onPressed: _showWithdrawSheet,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Info chips row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    _infoBadge(Icons.security_rounded, t('secure_payments_label'), AppColors.cyan),
                    const SizedBox(width: 10),
                    _infoBadge(Icons.flash_on_rounded, t('instant_transfer_label'), const Color(0xFFFF8000)),
                  ]),
                ),

                const SizedBox(height: 14),

                // Settle quick transactions CTA — tricolor border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickTransactionsPage())),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFFFF8F0), dark: const Color(0xFF3A2B16)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8000).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.handshake_rounded, color: Color(0xFFFF8000), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('settle_quick_transactions_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF8000))),
                              Text(t('pay_off_pending_balances_message'), style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFFF8000)),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Group Transactions CTA — tricolor border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupTransactionPage())),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFF0F9FF), dark: const Color(0xFF16323A)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.group_rounded, color: AppColors.cyan, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('group_transactions_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.cyan)),
                              Text(t('settle_shared_group_expenses_message'), style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.cyan),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Secure Transactions CTA — tricolor border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserTransactionsPage())),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFF0FFF4), dark: const Color(0xFF173A2A)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_user_rounded, color: Colors.teal, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('secure_transactions_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                              Text(t('manage_lend_borrow_records_message'), style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Colors.teal),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Subscribe to Premium CTA — tricolor border
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFF5F0FF), dark: const Color(0xFF2E1F3A)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C27B0).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFF9C27B0), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t('go_premium_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9C27B0))),
                              Text(t('subscribe_using_wallet_balance_message'), style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF9C27B0)),
                        ]),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Transaction history
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Text(t('transaction_history_label'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                    const Spacer(),
                    if (!_loading && _transactions.isNotEmpty)
                      Text('${_transactions.length} ${t('records_label').toLowerCase()}', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                  ]),
                ),
                const SizedBox(height: 10),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: AppColors.cyan)),
                  )
                else if (_transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_rounded, size: 64, color: AppThemeColors.divider(context)),
                      const SizedBox(height: 8),
                      Text(t('no_transactions_yet_message'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                      const SizedBox(height: 4),
                      Text(t('add_money_to_get_started_message'), style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                    ]),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    itemCount: _transactions.length,
                    itemBuilder: (_, i) {
                            final tx = _transactions[i];
                            final type = (tx['type'] ?? 'credit').toString();
                            final isWithdrawal = type == 'withdrawal';
                            final isCredit = !isWithdrawal && (type == 'credit' || type == 'topup' || type == 'add' || type == 'receive');
                            final amount = ((tx['amount'] ?? 0) as num).toDouble();
                            final balanceAfter = tx['balanceAfter'] != null ? (tx['balanceAfter'] as num).toDouble() : null;
                            final noteRaw = (tx['note'] ?? tx['description'] ?? '').toString();
                            final note = noteRaw.toLowerCase();
                            final fromEmail = (tx['fromEmail'] ?? '').toString();
                            final toEmail = (tx['toEmail'] ?? '').toString();
                            final hasRazorpay = tx['razorpayPaymentId'] != null && tx['razorpayPaymentId'].toString().isNotEmpty;
                            final withdrawalStatus = (tx['status'] ?? '').toString();
                            final date = (tx['createdAt'] ?? '').toString();
                            final dateShort = date.length >= 10 ? date.substring(0, 10) : date;

                            // Determine transaction category for badge
                            String txLabel;
                            IconData txIcon;
                            Color txBadgeColor;
                            if (isWithdrawal) {
                              txLabel = t('withdrawal_label');
                              txIcon = Icons.account_balance_rounded;
                              txBadgeColor = const Color(0xFF1B5E20);
                            } else if (type == 'topup') {
                              txLabel = t('wallet_topup_label');
                              txIcon = Icons.add_card_rounded;
                              txBadgeColor = const Color(0xFF2E7D32);
                            } else if (note.contains('subscription')) {
                              txLabel = t('subscription_label');
                              txIcon = Icons.workspace_premium_rounded;
                              txBadgeColor = const Color(0xFF9C27B0);
                            } else if (note.contains('group expense') || note.contains('group repayment')) {
                              txLabel = t('group_repayment_label');
                              txIcon = Icons.group_rounded;
                              txBadgeColor = const Color(0xFF1565C0);
                            } else if (note.contains('secure transaction')) {
                              txLabel = t('secure_txn_label');
                              txIcon = Icons.verified_user_rounded;
                              txBadgeColor = const Color(0xFF6A1B9A);
                            } else if (hasRazorpay) {
                              txLabel = isCredit ? t('razorpay_received_label') : t('razorpay_p2p_label');
                              txIcon = Icons.payment_rounded;
                              txBadgeColor = AppColors.cyan;
                            } else {
                              txLabel = isCredit ? t('wallet_received_label') : t('wallet_transfer_label');
                              txIcon = isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
                              txBadgeColor = isCredit ? const Color(0xFF2E7D32) : const Color(0xFFFF8000);
                            }

                            final txColor = isCredit ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
                            final counterparty = isCredit ? fromEmail : toEmail;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  colors: [Colors.orange, Colors.white, Colors.green],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: AppThemeColors.cardBg(context),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: txBadgeColor.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(txIcon, color: txBadgeColor, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        noteRaw.isNotEmpty ? noteRaw : txLabel,
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.primaryText(context)),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: txBadgeColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: txBadgeColor.withValues(alpha: 0.35), width: 0.8),
                                          ),
                                          child: Text(txLabel, style: TextStyle(fontSize: 10, color: txBadgeColor, fontWeight: FontWeight.w600)),
                                        ),
                                        if (hasRazorpay) ...[
                                          const SizedBox(width: 6),
                                          Icon(Icons.lock_rounded, size: 11, color: Colors.green[700]),
                                          const SizedBox(width: 2),
                                          Text(t('secured_label'), style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w500)),
                                        ],
                                        if (isWithdrawal && withdrawalStatus.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _withdrawalStatusColor(withdrawalStatus).withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: _withdrawalStatusColor(withdrawalStatus).withValues(alpha: 0.35), width: 0.8),
                                            ),
                                            child: Text(_withdrawalStatusLabel(withdrawalStatus),
                                              style: TextStyle(fontSize: 10, color: _withdrawalStatusColor(withdrawalStatus), fontWeight: FontWeight.w600)),
                                          ),
                                        ],
                                      ]),
                                      if (counterparty.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          Icon(
                                            isCredit ? Icons.person_rounded : Icons.send_rounded,
                                            size: 11, color: AppThemeColors.mutedText(context),
                                          ),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              '${isCredit ? t('from_label') : t('to_label')}: $counterparty',
                                              style: TextStyle(fontSize: 10.5, color: AppThemeColors.mutedText(context)),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ]),
                                      ],
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        Icon(Icons.calendar_today_rounded, size: 11, color: AppThemeColors.mutedText(context)),
                                        const SizedBox(width: 4),
                                        Text(dateShort, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                      ]),
                                    ],
                                  )),
                                  const SizedBox(width: 8),
                                  Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                                    Text(
                                      '${isCredit ? '+' : '-'}₹${amount.toStringAsFixed(2)}',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: txColor),
                                    ),
                                    if (balanceAfter != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        '${t('balance_colon_label')} ₹${balanceAfter.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context), fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ]),
                                ]),
                              ),
                            );
                          },
                    ),
                const SizedBox(height: 24),
              ]))))  // closes Column.children + Column + SCView + RefreshIndicator + Expanded
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color), maxLines: 1)),
        ]),
      ),
    );
  }
}

// ─────────────────────── Add Money Sheets ───────────────────────
// Two-step flow mirroring SubscriptionsPage's manual-payment pattern exactly:
//  1. _AddMoneyAmountSheet — freely dismissible amount entry.
//  2. _AddMoneyConfirmSheet — dismiss-guarded (isDismissible/enableDrag false +
//     PopScope) "pay then paste Payment ID" step with a single verification
//     call. There is deliberately no background auto-poll racing against the
//     manual verify call — an earlier version had one, and it could silently
//     win the atomic claim while the UI sat showing "waiting...", so the user
//     would then see a confusing "already used" error from the manual path.
//     One verification path = no race, exactly like subscriptions' flow.

class _AddMoneyAmountSheet extends StatefulWidget {
  final void Function(double amount) onContinue;

  const _AddMoneyAmountSheet({required this.onContinue});

  @override
  State<_AddMoneyAmountSheet> createState() => _AddMoneyAmountSheetState();
}

class _AddMoneyAmountSheetState extends State<_AddMoneyAmountSheet> {
  final _amountCtrl = TextEditingController();
  String? _error;

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _continue() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 1) {
      setState(() => _error = t('enter_valid_amount_min_1'));
      return;
    }
    widget.onContinue(amount);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 48, height: 5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green]),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, color: AppColors.cyan, size: 22),
              ),
              const SizedBox(width: 10),
              Text(t('add_money_to_wallet_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyan)),
            ]),
            const SizedBox(height: 4),
            Text(t('real_money_topup_description'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [100, 250, 500, 1000, 2000, 5000].map((amt) =>
                GestureDetector(
                  onTap: () => setState(() { _amountCtrl.text = '$amt'; _error = null; }),
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF1B3A57)),
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Text('₹$amt', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.cyan, fontSize: 13)),
                    ),
                  ),
                ),
              ).toList(),
            ),
            const SizedBox(height: 16),
            tricolorBorder(
              child: TextField(
                controller: _amountCtrl,
                onChanged: (_) { if (_error != null) setState(() => _error = null); },
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: t('enter_amount_rupee_label'),
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: AppThemeColors.tinted(context, light: const Color(0xFFF5F7FA), dark: const Color(0xFF2A2A2A)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                label: Text(t('continue'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Dismiss-guarded confirm step — exact structural mirror of
// SubscriptionsPage._showManualPaymentSheet (PopScope guard tied to
// hasClickedPayNow/hasAttemptedVerify, "before you pay" tips, pay-exact-amount
// warning, single Payment ID verify call, help/support fallback on failure).
class _AddMoneyConfirmSheet extends StatefulWidget {
  final double amount;
  final String paymentLink;
  final VoidCallback onCredited;

  const _AddMoneyConfirmSheet({required this.amount, required this.paymentLink, required this.onCredited});

  @override
  State<_AddMoneyConfirmSheet> createState() => _AddMoneyConfirmSheetState();
}

class _AddMoneyConfirmSheetState extends State<_AddMoneyConfirmSheet> {
  final _paymentIdCtrl = TextEditingController();
  bool _hasClickedPayNow = false;
  bool _hasAttemptedVerify = false;
  bool _verifying = false;
  String? _errorText;

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void dispose() {
    _paymentIdCtrl.dispose();
    super.dispose();
  }

  bool _canClose() => !_hasClickedPayNow || _hasAttemptedVerify;

  void _tryClose() {
    if (_canClose()) {
      Navigator.of(context).pop();
    } else {
      showSnack(context, t('enter_payment_id_before_closing_message'), isError: true);
    }
  }

  Future<void> _openPaymentLink() async {
    setState(() => _hasClickedPayNow = true);
    // razorpay.me Payment Handle pages don't support an amount query param —
    // passing one breaks the page with a generic error, so the payer must
    // type the amount in themselves on Razorpay's page (same as the
    // subscriptions manual-payment flow).
    await launchUrl(Uri.parse(widget.paymentLink), mode: LaunchMode.externalApplication);
  }

  Future<void> _verify() async {
    final paymentId = _paymentIdCtrl.text.trim();
    if (paymentId.isEmpty) {
      setState(() => _errorText = t('please_enter_payment_id_message'));
      return;
    }
    setState(() { _verifying = true; _hasAttemptedVerify = true; _errorText = null; });
    try {
      final res = await ApiClient.post('/api/wallet/topup/manual/verify', body: {
        'paymentId': paymentId,
        'amount': widget.amount,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        Navigator.of(context).pop();
        widget.onCredited();
        if (!mounted) return;
        showSnack(context, '₹${data['addedAmount']} ${t('added_to_wallet_suffix')}');
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _verifying = false;
          _errorText = err['error'] ?? t('payment_verification_failed_generic_message');
        });
      }
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _errorText = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    return PopScope(
      canPop: _canClose(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          showSnack(context, t('enter_payment_id_before_closing_message'), isError: true);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(t('add_money_to_wallet_title'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyan)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppThemeColors.secondaryText(context)),
                    onPressed: _tryClose,
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  t('amount_to_pay_colon_label').replaceFirst('{amount}', '₹${widget.amount.toStringAsFixed(2)}'),
                  style: TextStyle(fontSize: 15, color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3A2F12) : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFCC02).withValues(alpha: isDark ? 0.5 : 1), width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('pay_exact_amount_wallet_warning_message').replaceFirst('{amount}', '₹${widget.amount.toStringAsFixed(2)}'),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFFFD54F) : const Color(0xFFF57F17)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF12283A) : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: isDark ? 0.5 : 1), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 16, color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0)),
                          const SizedBox(width: 6),
                          Text(t('before_you_pay_label'),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(t('save_payment_id_and_receipt_message'),
                        style: TextStyle(fontSize: 12.5, color: isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _openPaymentLink,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(t('pay_now_open_link_label')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t('after_paying_enter_payment_id_message'),
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentIdCtrl,
                  enabled: !_verifying,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    hintText: 'pay_XXXXXXXXXXXXXX',
                    errorText: _errorText,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _verifying
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(t('verify_and_add_to_wallet_label')),
                ),
                if (_errorText != null && !_verifying) ...[
                  const SizedBox(height: 14),
                  Text(
                    t('need_help_with_payment_message'),
                    style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.help_center, size: 16),
                          label: Text(t('help_and_support'), style: const TextStyle(fontSize: 12.5)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => HelpSupportPage()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.contact_support, size: 16),
                          label: Text(t('contact_us_title'), style: const TextStyle(fontSize: 12.5)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ContactPage()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Reusable static method to show a payment sheet from any transaction page.
// Checks if counterparty phone exists; if not, shows a prompt.
class _PayToUserSheet extends StatefulWidget {
  final double walletBalance;
  final void Function(double amount, String recipient) onSuccess;

  const _PayToUserSheet({required this.walletBalance, required this.onSuccess});

  @override
  State<_PayToUserSheet> createState() => _PayToUserSheetState();
}

class _PayToUserSheetState extends State<_PayToUserSheet> {
  final _emailCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;
  bool _sendingOtp = false;
  String? _error;

  // OTP step — gates the actual transfer behind the sender confirming their own email.
  bool _showOtpStep = false;
  String _otpCode = '';
  int _timeRemaining = 120;
  Timer? _timer;
  String _otpEmail = '';

  // Friend quick-pick strip — lets the sender tap an avatar instead of typing an email.
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? [])
              .where((f) => (f['email'] ?? '').toString().isNotEmpty)
              .toList();
          _loadingFriends = false;
        });
      } else {
        setState(() => _loadingFriends = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF0077B6), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFD32F2F), Color(0xFF00838F), Color(0xFFE65100),
      Color(0xFF1565C0), Color(0xFF558B2F),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String username) {
    final n = name.trim();
    if (n.isNotEmpty) {
      final parts = n.split(' ');
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return n[0].toUpperCase();
    }
    if (username.trim().isNotEmpty) return username[0].toUpperCase();
    return '?';
  }

  bool _validateDetails(String t(String key)) {
    final to = _emailCtrl.text.trim();
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (to.isEmpty) { setState(() => _error = t('enter_email_message')); return false; }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(to)) {
      setState(() => _error = t('please_enter_valid_email_address'));
      return false;
    }
    if (amt == null || amt <= 0) { setState(() => _error = t('enter_a_valid_amount_message')); return false; }
    if (amt > widget.walletBalance) {
      setState(() => _error = '${t('insufficient_balance_label')} (₹${widget.walletBalance.toStringAsFixed(2)})');
      return false;
    }
    return true;
  }

  Future<void> _sendOtp() async {
    final t = AppLocalizations.of(context).t;
    if (!_validateDetails(t)) return;

    setState(() { _sendingOtp = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/pay/send-otp', body: {
        'to': _emailCtrl.text.trim(),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _sendingOtp = false;
          _showOtpStep = true;
          _otpEmail = (data['email'] ?? '').toString();
          _timeRemaining = 120;
          _otpCode = '';
        });
        _startTimer();
      } else {
        final err = jsonDecode(res.body);
        setState(() { _sendingOtp = false; _error = err['error'] ?? t('failed_to_send_otp_retry'); });
      }
    } catch (e) {
      if (mounted) setState(() { _sendingOtp = false; _error = t('error_colon_label').replaceFirst('{error}', '$e'); });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        if (_timeRemaining > 0) {
          _timeRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmAndPay() async {
    final t = AppLocalizations.of(context).t;
    if (_otpCode.length != 6) {
      setState(() => _error = t('please_enter_valid_6_digit_otp'));
      return;
    }
    final to = _emailCtrl.text.trim();
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null) return;

    setState(() { _sending = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/pay/verify-otp', body: {
        'to': to, 'amount': amt, 'note': _noteCtrl.text.trim(), 'otp': _otpCode,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        _timer?.cancel();
        Navigator.pop(context);
        widget.onSuccess(amt, to);
      } else {
        final err = jsonDecode(res.body);
        setState(() { _sending = false; _error = err['error'] ?? t('payment_failed_label'); });
      }
    } catch (e) {
      if (mounted) setState(() { _sending = false; _error = t('error_colon_label').replaceFirst('{error}', '$e'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tricolor sheet handle
            Center(child: Container(
              width: 48, height: 5,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green]),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF8000).withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded, color: Color(0xFFFF8000), size: 22),
              ),
              const SizedBox(width: 10),
              Text(t('pay_to_user_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.white, Colors.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF16323A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: AppColors.cyan, size: 16),
                  const SizedBox(width: 6),
                  Text('${t('wallet_balance_colon_label')} ₹${widget.walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            if (!_showOtpStep) ...[
              if (_loadingFriends) ...[
                const Center(child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan)),
                )),
                const SizedBox(height: 6),
              ] else if (_friends.isNotEmpty) ...[
                Row(children: [
                  const Icon(Icons.people_alt_rounded, size: 14, color: Color(0xFFFF8000)),
                  const SizedBox(width: 6),
                  Text(t('select_a_friend_label'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFF8000))),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _friends.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final f = _friends[i];
                      final name = (f['name'] ?? '').toString();
                      final username = (f['username'] ?? '').toString();
                      final email = (f['email'] ?? '').toString();
                      final selected = _emailCtrl.text.trim().toLowerCase() == email.toLowerCase();
                      return GestureDetector(
                        onTap: () => setState(() { _emailCtrl.text = email; _error = null; }),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: selected
                                ? const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight)
                                : null,
                              border: selected ? null : Border.all(color: AppThemeColors.divider(context), width: 1.4),
                              boxShadow: selected
                                ? [BoxShadow(color: const Color(0xFFFF8000).withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))]
                                : null,
                            ),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: _avatarColor(name.isNotEmpty ? name : username),
                              child: Text(_initials(name, username),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 62,
                            child: Text(
                              name.isNotEmpty ? name.split(' ').first : (username.isNotEmpty ? username : email),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                                color: selected ? const Color(0xFFFF8000) : AppThemeColors.secondaryText(context),
                              ),
                              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
              tricolorBorder(
                child: TextField(
                  controller: _emailCtrl,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: t('pay_to_user_email_label'),
                    prefixIcon: const Icon(Icons.person_search_rounded),
                    hintText: 'user@example.com',
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: 12),
              tricolorBorder(
                child: TextField(
                  controller: _amountCtrl,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: t('amount_rupee_label'),
                    prefixText: '₹ ',
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(height: 12),
              tricolorBorder(
                child: TextField(
                  controller: _noteCtrl,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: t('note_optional_label'),
                    prefixIcon: const Icon(Icons.note_alt_outlined),
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Clarifying note — this only moves money between LenDen wallets.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context, light: const Color(0xFFFFF8E1), dark: const Color(0xFF4A3F1F)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFF57F17), size: 15),
                  const SizedBox(width: 8),
                  Flexible(child: Text(t('pay_user_wallet_only_note_message'),
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFFF57F17)))),
                ]),
              ),
            ] else ...[
              // OTP step — confirm the sender's own email before debiting.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF16323A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('otp_sent_to_email_desc'),
                    style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 4),
                  Text(_otpEmail, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan, fontSize: 14)),
                ]),
              ),
              const SizedBox(height: 18),
              Center(
                child: OtpInput(
                  onChanged: (code) => setState(() => _otpCode = code),
                  enabled: !_sending,
                  autoFocus: true,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_timeRemaining > 30 ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: (_timeRemaining > 30 ? Colors.green : Colors.orange).withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer, size: 16, color: _timeRemaining > 30 ? Colors.green : Colors.orange),
                      const SizedBox(width: 4),
                      Text(_formatTime(_timeRemaining), style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold,
                        color: _timeRemaining > 30 ? Colors.green : Colors.orange,
                      )),
                    ]),
                  ),
                  TextButton(
                    onPressed: (_timeRemaining == 0 && !_sendingOtp) ? _sendOtp : null,
                    child: Text(t('resend_otp'), style: TextStyle(
                      color: (_timeRemaining == 0 && !_sendingOtp) ? AppColors.cyan : Colors.grey,
                      fontWeight: FontWeight.bold,
                    )),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _sending ? null : () {
                  _timer?.cancel();
                  setState(() { _showOtpStep = false; _otpCode = ''; _error = null; });
                },
                child: Text(t('change_details_label'), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
              ),
            ],

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: (_sending || _sendingOtp)
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(_showOtpStep ? Icons.verified_rounded : Icons.mark_email_read_rounded, color: Colors.white),
                label: Text(
                  _showOtpStep
                    ? (_sending ? t('processing_ellipsis_label') : t('verify_and_pay_label'))
                    : (_sendingOtp ? t('sending_ellipsis_label') : t('send_otp_label')),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
                onPressed: (_sending || _sendingOtp) ? null : (_showOtpStep ? _confirmAndPay : _sendOtp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Withdraw Sheet ───────────────────────

class _WithdrawSheet extends StatefulWidget {
  final double walletBalance;
  final void Function(double amount, {bool manualReview}) onSuccess;

  const _WithdrawSheet({required this.walletBalance, required this.onSuccess});

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  String _mode = 'upi'; // 'upi' | 'bank_account'
  final _amountCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _upiCtrl.dispose();
    _holderCtrl.dispose();
    _accountCtrl.dispose();
    _ifscCtrl.dispose();
    _bankCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = AppLocalizations.of(context).t;
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt < 100) {
      setState(() => _error = t('minimum_withdrawal_label'));
      return;
    }
    if (amt > widget.walletBalance) {
      setState(() => _error = '${t('insufficient_balance_label')} (₹${widget.walletBalance.toStringAsFixed(2)})');
      return;
    }
    if (_mode == 'upi' && _upiCtrl.text.trim().isEmpty) {
      setState(() => _error = t('enter_your_upi_id_message'));
      return;
    }
    if (_mode == 'upi' && !_upiCtrl.text.trim().contains('@')) {
      setState(() => _error = t('invalid_upi_id_message'));
      return;
    }
    if (_mode == 'bank_account') {
      if (_holderCtrl.text.trim().isEmpty) { setState(() => _error = t('enter_account_holder_name_message')); return; }
      if (_accountCtrl.text.trim().isEmpty) { setState(() => _error = t('enter_account_number_message')); return; }
      if (_ifscCtrl.text.trim().isEmpty) { setState(() => _error = t('enter_ifsc_code_message')); return; }
    }

    setState(() { _loading = true; _error = null; });
    try {
      final body = <String, dynamic>{ 'amount': amt, 'mode': _mode };
      if (_mode == 'upi') {
        body['upiId'] = _upiCtrl.text.trim();
      } else {
        body['accountHolderName'] = _holderCtrl.text.trim();
        body['accountNumber'] = _accountCtrl.text.trim();
        body['ifsc'] = _ifscCtrl.text.trim().toUpperCase();
        if (_bankCtrl.text.trim().isNotEmpty) body['bankName'] = _bankCtrl.text.trim();
      }
      final res = await ApiClient.post('/api/wallet/withdraw', body: body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        Navigator.pop(context);
        widget.onSuccess(amt, manualReview: data['manualReview'] == true);
      } else {
        final err = jsonDecode(res.body);
        setState(() { _loading = false; _error = err['error'] ?? t('withdrawal_failed_label'); });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = t('error_colon_label').replaceFirst('{error}', '$e'); });
    }
  }

  InputDecoration _field(String label, {String? hint, Widget? prefix, Widget? prefixIcon}) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    prefix: prefix,
    filled: true,
    fillColor: AppThemeColors.surfaceBg(context),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(child: Container(
                width: 48, height: 5,
                decoration: BoxDecoration(
                  color: AppThemeColors.divider(context),
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
              const SizedBox(height: 20),
              // Title row
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_rounded, color: Color(0xFF1B5E20), size: 22),
                ),
                const SizedBox(width: 10),
                Text(t('withdraw_money_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
              ]),
              const SizedBox(height: 10),
              // Balance pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF2E7D32), size: 16),
                  const SizedBox(width: 6),
                  Text('${t('available_colon_label')} ₹${widget.walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 16),
              // Mode toggle
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF16323A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _mode = 'upi'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mode == 'upi' ? const Color(0xFF1B5E20) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.phone_android_rounded,
                          size: 16, color: _mode == 'upi' ? Colors.white : const Color(0xFF1B5E20)),
                        const SizedBox(width: 6),
                        Text(t('upi_label'), style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _mode == 'upi' ? Colors.white : const Color(0xFF1B5E20),
                        )),
                      ]),
                    ),
                  )),
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => _mode = 'bank_account'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mode == 'bank_account' ? const Color(0xFF1B5E20) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.account_balance_rounded,
                          size: 16, color: _mode == 'bank_account' ? Colors.white : const Color(0xFF1B5E20)),
                        const SizedBox(width: 6),
                        Text(t('bank_account_label'), style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _mode == 'bank_account' ? Colors.white : const Color(0xFF1B5E20),
                        )),
                      ]),
                    ),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              // Amount field
              tricolorBorder(
                child: TextField(
                  controller: _amountCtrl,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: _field(t('amount_rupee_label'), hint: t('minimum_rupee_100_hint'), prefixIcon: const Icon(Icons.currency_rupee_rounded)),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(height: 12),
              // Mode-specific fields
              if (_mode == 'upi') ...[
                tricolorBorder(
                  child: TextField(
                    controller: _upiCtrl,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('upi_id_label'), hint: 'name@bank', prefixIcon: const Icon(Icons.alternate_email_rounded)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ] else ...[
                tricolorBorder(
                  child: TextField(
                    controller: _holderCtrl,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('account_holder_name_label'), prefixIcon: const Icon(Icons.person_rounded)),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _accountCtrl,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('account_number_label'), prefixIcon: const Icon(Icons.credit_card_rounded)),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _ifscCtrl,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('ifsc_code_label'), hint: 'HDFC0001234', prefixIcon: const Icon(Icons.code_rounded)),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _bankCtrl,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('bank_name_optional_label'), prefixIcon: const Icon(Icons.business_rounded)),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
              // Error box
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Flexible(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                    ]),
                  ),
                ),
              const SizedBox(height: 20),
              // Manual review notice — money leaves the wallet now, but is transferred to the
              // user's bank/UPI by an admin since no automatic payout account is configured yet.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context, light: const Color(0xFFFFF8E1), dark: const Color(0xFF4A3F1F)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFF57F17), size: 15),
                  const SizedBox(width: 8),
                  Flexible(child: Text(
                    t('withdraw_manual_review_notice_message'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFF57F17)),
                  )),
                ]),
              ),
              const SizedBox(height: 16),
              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.account_balance_rounded, color: Colors.white),
                  label: Text(_loading ? t('processing_ellipsis_label') : t('withdraw_label'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  onPressed: _loading ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────

class LendenPaymentHelper {
  static Future<void> showPaymentSheet(
    BuildContext context, {
    required String counterpartyEmail,
    required double amount,
    required String description,
    String? counterpartyPhone,
    String? quickTransactionId,
    String? secureTransactionId,
    VoidCallback? onSuccess,
  }) async {
    final hasPhone = counterpartyPhone != null && counterpartyPhone.trim().isNotEmpty;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PaymentSheet(
        counterpartyEmail: counterpartyEmail,
        counterpartyPhone: counterpartyPhone,
        amount: amount,
        description: description,
        hasPhone: hasPhone,
        quickTransactionId: quickTransactionId,
        secureTransactionId: secureTransactionId,
        onSuccess: onSuccess,
      ),
    );

    // Sheet popped with Razorpay order data — open Razorpay from page context
    // (not from within the bottom sheet) so the SDK can present its UI properly.
    if (result == null || result['type'] != 'razorpay') return;
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RazorpayPayPage(
          options: Map<String, dynamic>.from(result['options'] as Map),
          quickTransactionId: quickTransactionId,
          secureTransactionId: secureTransactionId,
          onSuccess: onSuccess,
        ),
      ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  final String counterpartyEmail;
  final String? counterpartyPhone;
  final double amount;
  final String description;
  final bool hasPhone;
  final String? quickTransactionId;
  final String? secureTransactionId;
  final VoidCallback? onSuccess;

  const _PaymentSheet({
    required this.counterpartyEmail,
    required this.counterpartyPhone,
    required this.amount,
    required this.description,
    required this.hasPhone,
    this.quickTransactionId,
    this.secureTransactionId,
    this.onSuccess,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  bool _payingRazorpay = false;
  bool _payingWallet = false;
  String? _error;
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  String get _effectivePhone =>
      (widget.counterpartyPhone?.trim().isNotEmpty == true)
          ? widget.counterpartyPhone!
          : _phoneController.text.trim();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _payViaRazorpay() async {
    final t = AppLocalizations.of(context).t;
    if (!_isMobile) {
      setState(() => _error = t('razorpay_android_ios_only'));
      return;
    }
    if (!widget.hasPhone && _phoneController.text.trim().isEmpty) {
      setState(() => _error = t('enter_phone_for_razorpay_upi_message'));
      return;
    }
    setState(() { _payingRazorpay = true; _error = null; });
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final body = {
        'toEmail': widget.counterpartyEmail,
        'amount': (widget.amount * 100).toInt(),
        'description': widget.description,
      };
      if (widget.quickTransactionId != null) body['quickTransactionId'] = widget.quickTransactionId!;
      if (widget.secureTransactionId != null) body['secureTransactionId'] = widget.secureTransactionId!;
      final orderRes = await ApiClient.post('/api/payment/create-p2p-order', body: body);
      if (!mounted) return;
      if (orderRes.statusCode != 200) {
        final err = jsonDecode(orderRes.body);
        setState(() { _payingRazorpay = false; _error = err['error'] ?? t('failed_to_create_order'); });
        return;
      }
      final data = jsonDecode(orderRes.body);
      final user = session.user ?? {};
      final phone = _effectivePhone;
      final options = {
        'key': data['keyId'],
        'amount': data['amount'],
        'currency': 'INR',
        'name': 'LenDen Pay',
        'description': widget.description,
        'order_id': data['orderId'],
        'prefill': {
          'email': user['email'] ?? '',
          if (phone.isNotEmpty) 'contact': phone,
          'name': user['name'] ?? '',
        },
        'theme': {'color': '#00B4D8'},
      };
      // Close the sheet and pass order data up — Razorpay SDK must open from a full-page
      // context (not a bottom sheet) so it can properly present its UI on Android/iOS.
      if (mounted) {
        setState(() => _payingRazorpay = false);
        Navigator.pop(context, {'type': 'razorpay', 'options': options});
      }
    } catch (e) {
      if (mounted) setState(() { _payingRazorpay = false; _error = t('error_colon_label').replaceFirst('{error}', '$e'); });
    }
  }

  Future<void> _payViaWallet() async {
    final t = AppLocalizations.of(context).t;
    setState(() { _payingWallet = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/pay', body: {
        'to': widget.counterpartyEmail,
        'amount': widget.amount,
        'note': widget.description,
      });
      if (!mounted) return;
      setState(() => _payingWallet = false);
      if (res.statusCode == 200) {
        Navigator.pop(context);
        widget.onSuccess?.call();
      } else {
        final err = jsonDecode(res.body);
        setState(() => _error = err['error'] ?? t('payment_failed_label'));
      }
    } catch (e) {
      if (mounted) setState(() { _payingWallet = false; _error = t('error_colon_label').replaceFirst('{error}', '$e'); });
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
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tricolor sheet handle
          Center(child: Container(
            width: 48, height: 5,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green]),
              borderRadius: BorderRadius.circular(3),
            ),
          )),
          const SizedBox(height: 18),
          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFF8000).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.payments_rounded, color: Color(0xFFFF8000), size: 22),
            ),
            const SizedBox(width: 10),
            Text(t('pay_now_label'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
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
                color: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF16323A)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.person_outline, size: 16, color: AppColors.cyan),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.counterpartyEmail, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.currency_rupee, size: 16, color: Color(0xFFFF8000)),
                  const SizedBox(width: 6),
                  Text('₹${widget.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
                ]),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.note_outlined, size: 16, color: AppThemeColors.mutedText(context)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(widget.description, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)))),
                  ]),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Phone section
          if (!widget.hasPhone) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.phone_disabled_rounded, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('phone_number_not_found_label'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    t('phone_not_on_lenden_message'),
                    style: TextStyle(color: Colors.orange[800], fontSize: 12),
                  ),
                ])),
              ]),
            ),
            const SizedBox(height: 10),
            StatefulBuilder(builder: (ctx, setLocal) {
              return TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  hintText: t('enter_phone_number_optional_upi_hint'),
                  prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.cyan, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.divider(context))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
                  filled: true,
                  fillColor: AppThemeColors.surfaceBg(context),
                ),
                onChanged: (_) => setLocal(() {}),
              );
            }),
            const SizedBox(height: 14),
          ],

          // Test mode hint
          _testModeHint(context),
          const SizedBox(height: 14),

          // Razorpay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: _payingRazorpay
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payment_rounded, color: Colors.white),
              label: Text(_payingRazorpay ? t('processing_ellipsis_label') : t('pay_via_razorpay_upi_more_label'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
              onPressed: (_payingRazorpay || _payingWallet) ? null : _payViaRazorpay,
            ),
          ),

          const SizedBox(height: 12),

          // Wallet button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.cyan, width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _payingWallet
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                : const Icon(Icons.account_balance_wallet_rounded, color: AppColors.cyan),
              label: Text(_payingWallet ? t('processing_ellipsis_label') : t('pay_via_lenden_wallet_label'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.cyan)),
              onPressed: (_payingWallet || _payingRazorpay) ? null : _payViaWallet,
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

// Full-page Razorpay host — opens the SDK from a proper Navigator page context so
// the SDK can present its Activity/ViewController without interference from sheets.
class _RazorpayPayPage extends StatefulWidget {
  final Map<String, dynamic> options;
  final String? quickTransactionId;
  final String? secureTransactionId;
  final VoidCallback? onSuccess;

  const _RazorpayPayPage({
    required this.options,
    this.quickTransactionId,
    this.secureTransactionId,
    this.onSuccess,
  });

  @override
  State<_RazorpayPayPage> createState() => _RazorpayPayPageState();
}

class _RazorpayPayPageState extends State<_RazorpayPayPage> {
  Razorpay? _razorpay;
  bool _opening = false;   // waiting for Razorpay overlay to appear
  bool _verifying = false; // waiting for backend verification
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {
        if (mounted) setState(() => _opening = false);
      });
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  // Called by the "Open Razorpay" button — always user-triggered so the
  // Android Activity is guaranteed to be RESUMED before the SDK presents.
  void _openRazorpay() {
    if (!_isMobile) {
      setState(() => _error = AppLocalizations.of(context).t('razorpay_android_ios_only'));
      return;
    }
    setState(() { _opening = true; _error = null; });
    _razorpay!.open(widget.options);
  }

  void _onSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() { _opening = false; _verifying = true; _error = null; });
    try {
      final verifyBody = {
        'razorpayOrderId': response.orderId,
        'razorpayPaymentId': response.paymentId,
        'razorpaySignature': response.signature,
      };
      if (widget.quickTransactionId != null) {
        verifyBody['quickTransactionId'] = widget.quickTransactionId!;
      }
      if (widget.secureTransactionId != null) {
        verifyBody['secureTransactionId'] = widget.secureTransactionId!;
      }
      final verifyRes = await ApiClient.post('/api/payment/verify-p2p', body: verifyBody);
      if (!mounted) return;
      if (verifyRes.statusCode == 200) {
        Navigator.pop(context);
        widget.onSuccess?.call();
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() { _verifying = false; _error = t('payment_verification_failed_contact_support_message'); });
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context).t;
        setState(() { _verifying = false; _error = '${t('verification_error_prefix')} $e'; });
      }
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    setState(() {
      _opening = false;
      _error = response.message?.isNotEmpty == true ? response.message! : t('payment_cancelled_or_failed_message');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final amountRupees = ((widget.options['amount'] as num?) ?? 0) / 100;
    final description = widget.options['description']?.toString() ?? '';

    // Full-screen verifying overlay
    if (_verifying) {
      return Scaffold(
        backgroundColor: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF121212)),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 52, height: 52,
              child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 3)),
            const SizedBox(height: 20),
            Text(t('verifying_payment_message'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.cyan)),
            const SizedBox(height: 6),
            Text(t('please_wait_do_not_go_back_message'), style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppThemeColors.tinted(context, light: const Color(0xFFF0F7FF), dark: const Color(0xFF121212)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.cyan),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
              ),
              const Spacer(),

              // Tricolor payment card
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payment_rounded, color: AppColors.cyan, size: 38),
                    ),
                    const SizedBox(height: 16),
                    Text(t('complete_your_payment_label'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.cyan)),
                    const SizedBox(height: 14),
                    Text('₹${amountRupees.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description, style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context)), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 18),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.lock_outline, size: 13, color: AppThemeColors.mutedText(context)),
                      const SizedBox(width: 4),
                      Text(t('secured_by_razorpay_label'), style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                    ]),
                  ]),
                ),
              ),

              const Spacer(),

              // Error
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 14),
              ],

              // CTA button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: _opening
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.open_in_new_rounded, color: Colors.white),
                  label: Text(
                    _opening ? t('opening_ellipsis_label') : (_error != null ? t('retry_payment_label') : t('open_razorpay_upi_more_label')),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  onPressed: _opening ? null : _openRazorpay,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
