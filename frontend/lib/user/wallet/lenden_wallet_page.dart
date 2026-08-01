import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../session.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../otp_input.dart';
import '../../utils/api_client.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/group_transactions/group_transaction_page.dart';
import '../transaction/secure_transactions/view_secure_transactions_page.dart';
import '../digitise/subscriptions_page.dart';
import '../support/help_support_page.dart';
import '../support/contact_page.dart';
import '../../widgets/payment_success_page.dart';
import '../../widgets/currency_display.dart';
import '../../utils/theme_helper.dart';
import '../../settings/set_wallet_pin_page.dart';
import '../scanner/qr_scanner_page.dart';
import '../scanner/user_qr_page.dart';
import '../../l10n/app_localizations.dart';
import '../../api_config.dart';

class LendenWalletPage extends StatefulWidget {
  final bool autoOpenPayUser;
  final bool autoOpenAddMoney;

  const LendenWalletPage(
      {super.key, this.autoOpenPayUser = false, this.autoOpenAddMoney = false});

  @override
  State<LendenWalletPage> createState() => _LendenWalletPageState();
}

class _LendenWalletPageState extends State<LendenWalletPage>
    with CurrencyDisplayMixin<LendenWalletPage> {
  bool _loading = true;
  bool _networkError = false;
  double _walletBalance = 0;
  List<Map<String, dynamic>> _transactions = [];
  String? _razorpayPaymentLink;
  String _historyType = 'all';
  String _historySearch = '';
  Timer? _historySearchDebounce;
  final TextEditingController _historySearchCtrl = TextEditingController();
  int _historyPage = 1;
  int _historyTotal = 0;
  bool _historyLoadingMore = false;
  static const _historyLimit = 20;

  String t(String key) => AppLocalizations.of(context).t(key);

  Color _withdrawalStatusColor(String status) {
    switch (status) {
      case 'processed':
        return const Color(0xFF2E7D32);
      case 'failed':
        return Colors.red;
      case 'reversed':
        return Colors.orange;
      default:
        return AppColors.cyan;
    }
  }

  String _withdrawalStatusLabel(String status) {
    switch (status) {
      case 'processed':
        return t('status_processed_label');
      case 'failed':
        return t('status_failed_label');
      case 'reversed':
        return t('status_reversed_label');
      default:
        return t('status_pending_label');
    }
  }

  @override
  void initState() {
    super.initState();
    loadCurrencies();
    Future.wait([_fetchPaymentConfig(), _fetchWalletData()]).then((_) {
      if (!mounted) return;
      if (widget.autoOpenPayUser) _showPayToUserSheet();
      if (widget.autoOpenAddMoney) _showAddMoneySheet();
    });
  }

  @override
  void dispose() {
    _historySearchDebounce?.cancel();
    _historySearchCtrl.dispose();
    super.dispose();
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

  Future<void> _fetchWalletData({bool resetPage = true}) async {
    if (resetPage) {
      setState(() {
        _loading = true;
        _networkError = false;
        _historyPage = 1;
        _transactions = [];
      });
    } else {
      setState(() => _historyLoadingMore = true);
    }
    bool hadError = false;
    try {
      final page = resetPage ? 1 : _historyPage;
      final histPath = '/api/wallet/history?page=$page&limit=$_historyLimit'
          '${_historyType != 'all' ? '&type=$_historyType' : ''}'
          '${_historySearch.isNotEmpty ? '&search=${Uri.encodeComponent(_historySearch)}' : ''}';
      final futures = resetPage
          ? [ApiClient.get('/api/wallet/balance'), ApiClient.get(histPath)]
          : [ApiClient.get(histPath)];
      final results = await Future.wait(futures);

      if (!mounted) return;
      if (resetPage) {
        final balRes = results[0];
        final histRes = results[1];
        if (balRes.statusCode == 200) {
          final data = jsonDecode(balRes.body);
          _walletBalance = (data['balance'] ?? 0).toDouble();
        } else {
          hadError = true;
        }
        if (histRes.statusCode == 200) {
          final data = jsonDecode(histRes.body);
          _transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          _historyTotal = (data['total'] ?? 0) as int;
          _historyPage = 1;
        }
      } else {
        final histRes = results[0];
        if (histRes.statusCode == 200) {
          final data = jsonDecode(histRes.body);
          _transactions = [
            ..._transactions,
            ...List<Map<String, dynamic>>.from(data['transactions'] ?? []),
          ];
          _historyTotal = (data['total'] ?? 0) as int;
        }
      }
    } catch (_) {
      hadError = true;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _historyLoadingMore = false;
      if (resetPage && hadError) _networkError = true;
    });
  }

  Future<void> _loadMoreHistory() async {
    if (_historyLoadingMore || _transactions.length >= _historyTotal) return;
    final nextPage = _historyPage + 1;
    _historyPage = nextPage;
    try {
      await _fetchWalletData(resetPage: false);
    } catch (_) {
      // Revert page increment so a retry fetches the correct page
      if (mounted) setState(() => _historyPage = nextPage - 1);
    }
  }

  void _showAddMoneySheet() {
    if (_razorpayPaymentLink == null) {
      showSnack(context, t('payment_config_unavailable_message'),
          isError: true);
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
        onCredited: (addedAmount, balance) {
          _fetchWalletData();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentSuccessPage(
                title: t('money_added_title'),
                amount: addedAmount,
                transactionType: t('wallet_topup_label'),
              ),
            ),
          );
        },
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

  Future<void> _showBuyCoinsSheet() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final pricing = session.coinPricingConfig;
    final coinValue = (pricing['coinValue'] as num? ?? 0.10).toDouble();
    final coinCurrency = (pricing['coinValueCurrency'] as String?) ?? 'INR';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WalletBuyCoinsSheet(
        coinValue: coinValue,
        coinCurrency: coinCurrency,
        walletBalance: _walletBalance,
        displayCurrencyData: currencyData,
        initialDisplayCurrency: selectedCurrency,
      ),
    );

    if (result == null || !mounted) return;
    final newWalletBal = (result['newWalletBalance'] as num?)?.toDouble();
    if (newWalletBal != null) setState(() => _walletBalance = newWalletBal);
    final newCoinBal = (result['newCoinBalance'] as num?)?.toInt();
    if (newCoinBal != null) session.updateUserCoins(newCoinBal);
    showSnack(context,
        'Bought ${result['coins']} coins for $coinCurrency ${result['totalCost']}!');
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

  Widget _buildNetworkErrorBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 15, color: Color(0xFFE53935)),
        const SizedBox(width: 5),
        Text(
          t('no_connection_label'),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE53935),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _fetchWalletData,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
            ),
            child: Text(
              t('retry_label'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE53935),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkErrorHistory() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFFE53935).withValues(alpha: 0.18),
                  const Color(0xFFE53935).withValues(alpha: 0.04),
                ],
              ),
            ),
            child: const Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: Color(0xFFE53935),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('no_internet_connection_title'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            t('check_connection_and_retry_message'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppThemeColors.secondaryText(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppThemeColors.cardBg(context),
                  foregroundColor: const Color(0xFFE53935),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _fetchWalletData,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  t('retry_label'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.tinted(context,
          light: const Color(0xFFF0F7FF), dark: const Color(0xFF121212)),
      body: Stack(
        children: [
          // Header gradient
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 260,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppThemeColors.waveGradient(context),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back,
                          color: AppThemeColors.primaryText(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(t('lenden_wallet_title'),
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(context))),
                          Text(t('store_send_real_money_subtitle'),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh,
                          color: AppThemeColors.primaryText(context)),
                      onPressed: _fetchWalletData,
                    ),
                  ]),
                ),

                // ── Scrollable body ───────────────────────────────────
                Expanded(
                    child: RefreshIndicator(
                        onRefresh: _fetchWalletData,
                        color: AppColors.cyan,
                        child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(children: [
                              // Balance card — tricolor border
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(26),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.cyan
                                              .withValues(alpha: 0.18),
                                          blurRadius: 24,
                                          offset: const Offset(0, 10)),
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
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(children: [
                                                const Icon(
                                                    Icons
                                                        .account_balance_wallet_rounded,
                                                    color: Color(0xFFFF8000),
                                                    size: 20),
                                                const SizedBox(width: 7),
                                                Text(t('lenden_wallet_balance_label'),
                                                    style: const TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors.cyan)),
                                              ]),
                                              buildCurrencySelector(),
                                            ]),
                                        const SizedBox(height: 10),
                                        if (_loading)
                                          const CircularProgressIndicator(
                                              color: AppColors.cyan)
                                        else if (_networkError)
                                          _buildNetworkErrorBadge()
                                        else
                                          Text(
                                            formatAmount(_walletBalance),
                                            style: const TextStyle(
                                                fontSize: 40,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.cyan),
                                          ),
                                        const SizedBox(height: 4),
                                        Text(t('available_to_send_or_pay'),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: AppThemeColors.mutedText(
                                                    context))),
                                        const SizedBox(height: 20),
                                        Row(children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.cyan,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 13),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14)),
                                                elevation: 0,
                                              ),
                                              icon: const Icon(
                                                  Icons.add_rounded,
                                                  color: Colors.white),
                                              label: Text(t('add_money_label'),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white)),
                                              onPressed: _showAddMoneySheet,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(
                                                    color: Color(0xFFFF8000),
                                                    width: 1.8),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 13),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            14)),
                                              ),
                                              icon: const Icon(
                                                  Icons.send_rounded,
                                                  color: Color(0xFFFF8000)),
                                              label: Text(t('pay_user_label'),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          Color(0xFFFF8000))),
                                              onPressed: _showPayToUserSheet,
                                            ),
                                          ),
                                        ]),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(
                                                  color: Color(0xFF1B5E20),
                                                  width: 1.8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 13),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          14)),
                                            ),
                                            icon: const Icon(
                                                Icons.account_balance_rounded,
                                                color: Color(0xFF1B5E20)),
                                            label: Text(
                                                t('withdraw_to_bank_upi_label'),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF1B5E20))),
                                            onPressed: _showWithdrawSheet,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFFD4A017),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(vertical: 13),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(14)),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.monetization_on_rounded, color: Colors.white),
                                            label: const Text('Buy LenDen Coins',
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                            onPressed: _showBuyCoinsSheet,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: AppColors.cyan, width: 1.8),
                                                padding: const EdgeInsets.symmetric(vertical: 13),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                              ),
                                              icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.cyan),
                                              label: const Text('Scan QR',
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan)),
                                              onPressed: () => Navigator.push(context,
                                                  MaterialPageRoute(builder: (_) => const QrScannerPage())),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: const BorderSide(color: AppColors.cyan, width: 1.8),
                                                padding: const EdgeInsets.symmetric(vertical: 13),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                              ),
                                              icon: const Icon(Icons.qr_code_rounded, color: AppColors.cyan),
                                              label: const Text('My QR',
                                                  style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan)),
                                              onPressed: () => Navigator.push(context,
                                                  MaterialPageRoute(builder: (_) => const UserQrPage())),
                                            ),
                                          ),
                                        ]),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Info chips row
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(children: [
                                  _infoBadge(
                                      Icons.security_rounded,
                                      t('secure_payments_label'),
                                      AppColors.cyan),
                                  const SizedBox(width: 10),
                                  _infoBadge(
                                      Icons.flash_on_rounded,
                                      t('instant_transfer_label'),
                                      const Color(0xFFFF8000)),
                                ]),
                              ),

                              const SizedBox(height: 14),

                              // Settle quick transactions CTA — tricolor border
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const QuickTransactionsPage())),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppThemeColors.tinted(context,
                                            light: const Color(0xFFFFF8F0),
                                            dark: const Color(0xFF3A2B16)),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFF8000)
                                                .withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.handshake_rounded,
                                              color: Color(0xFFFF8000),
                                              size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(t('settle_quick_transactions_label'),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color:
                                                            Color(0xFFFF8000))),
                                                Text(t('pay_off_pending_balances_message'),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppThemeColors
                                                            .secondaryText(
                                                                context))),
                                              ]),
                                        ),
                                        const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 13,
                                            color: Color(0xFFFF8000)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Group Transactions CTA — tricolor border
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const GroupTransactionPage())),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppThemeColors.tinted(context,
                                            light: const Color(0xFFF0F9FF),
                                            dark: const Color(0xFF16323A)),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: AppColors.cyan
                                                .withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.group_rounded,
                                              color: AppColors.cyan, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(t('group_transactions_label'),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color: AppColors.cyan)),
                                                Text(t('settle_shared_group_expenses_message'),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppThemeColors
                                                            .secondaryText(
                                                                context))),
                                              ]),
                                        ),
                                        const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 13,
                                            color: AppColors.cyan),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Secure Transactions CTA — tricolor border
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const UserTransactionsPage())),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppThemeColors.tinted(context,
                                            light: const Color(0xFFF0FFF4),
                                            dark: const Color(0xFF173A2A)),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: Colors.teal
                                                .withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.verified_user_rounded,
                                              color: Colors.teal,
                                              size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(t('secure_transactions_label'),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color: Colors.teal)),
                                                Text(t('manage_lend_borrow_records_message'),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppThemeColors
                                                            .secondaryText(
                                                                context))),
                                              ]),
                                        ),
                                        const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 13,
                                            color: Colors.teal),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Subscribe to Premium CTA — tricolor border
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(18),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const SubscriptionsPage())),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppThemeColors.tinted(context,
                                            light: const Color(0xFFF5F0FF),
                                            dark: const Color(0xFF2E1F3A)),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Row(children: [
                                        Container(
                                          padding: const EdgeInsets.all(9),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF9C27B0)
                                                .withValues(alpha: 0.14),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                              Icons.workspace_premium_rounded,
                                              color: Color(0xFF9C27B0),
                                              size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(t('go_premium_label'),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                        color:
                                                            Color(0xFF9C27B0))),
                                                Text(t('subscribe_using_wallet_balance_message'),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: AppThemeColors
                                                            .secondaryText(
                                                                context))),
                                              ]),
                                        ),
                                        const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 13,
                                            color: Color(0xFF9C27B0)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Quick-access: withdrawal tracker
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: OutlinedButton.icon(
                                  onPressed: () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const _WithdrawalHistorySheet(),
                                  ),
                                  icon: const Icon(Icons.account_balance_rounded, size: 16),
                                  label: Text(t('track_withdrawals_label')),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.orange,
                                    side: const BorderSide(color: Colors.orange, width: 1.2),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size(double.infinity, 42),
                                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Transaction history
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(children: [
                                  Text(t('transaction_history_label'),
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: AppThemeColors.primaryText(
                                              context))),
                                  const Spacer(),
                                  if (!_loading && _historyTotal > 0)
                                    Text(
                                        '${_transactions.length}/$_historyTotal ${t('records_label').toLowerCase()}',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppThemeColors.mutedText(
                                                context))),
                                ]),
                              ),
                              const SizedBox(height: 8),
                              // History search bar
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: TextField(
                                  controller: _historySearchCtrl,
                                  style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: t('search_wallet_history_hint'),
                                    hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                                    prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.cyan),
                                    suffixIcon: _historySearch.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear_rounded, size: 16),
                                            onPressed: () {
                                              _historySearchDebounce?.cancel();
                                              _historySearchCtrl.clear();
                                              setState(() => _historySearch = '');
                                              _fetchWalletData();
                                            },
                                          )
                                        : null,
                                    filled: true,
                                    fillColor: AppThemeColors.surfaceBg(context),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan, width: 1.2)),
                                  ),
                                  onChanged: (val) {
                                    _historySearchDebounce?.cancel();
                                    _historySearchDebounce = Timer(const Duration(milliseconds: 350), () {
                                      setState(() => _historySearch = val.trim());
                                      _fetchWalletData();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Type filter chips
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(children: [
                                  for (final entry in const {
                                    'all': 'All',
                                    'credit': 'Received',
                                    'debit': 'Sent',
                                    'topup': 'Top-up',
                                    'withdrawal': 'Withdrawal',
                                  }.entries)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: GestureDetector(
                                        onTap: () {
                                          if (_historyType != entry.key) {
                                            setState(() => _historyType = entry.key);
                                            _fetchWalletData();
                                          }
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 160),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _historyType == entry.key
                                                ? AppColors.cyan
                                                : AppThemeColors.cardBg(context),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _historyType == entry.key
                                                  ? AppColors.cyan
                                                  : Colors.grey.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text(entry.value,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _historyType == entry.key
                                                    ? Colors.white
                                                    : AppThemeColors.secondaryText(context),
                                              )),
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                              const SizedBox(height: 10),

                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.cyan)),
                                )
                              else if (_networkError)
                                _buildNetworkErrorHistory()
                              else if (_transactions.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.receipt_long_rounded,
                                            size: 64,
                                            color: AppThemeColors.divider(
                                                context)),
                                        const SizedBox(height: 8),
                                        Text(t('no_transactions_yet_message'),
                                            style: TextStyle(
                                                color: AppThemeColors
                                                    .secondaryText(context))),
                                        const SizedBox(height: 4),
                                        Text(t('add_money_to_get_started_message'),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppThemeColors.mutedText(
                                                    context))),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: _showAddMoneySheet,
                                          icon: const Icon(Icons.add_card_rounded, size: 18),
                                          label: Text(t('add_money_label')),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.cyan,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ]),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 4),
                                  itemCount: _transactions.length,
                                  itemBuilder: (_, i) {
                                    final tx = _transactions[i];
                                    final type =
                                        (tx['type'] ?? 'credit').toString();
                                    final isWithdrawal = type == 'withdrawal';
                                    final isCredit = !isWithdrawal &&
                                        (type == 'credit' ||
                                            type == 'topup' ||
                                            type == 'add' ||
                                            type == 'receive');
                                    final amount =
                                        ((tx['amount'] ?? 0) as num).toDouble();
                                    final balanceAfter = tx['balanceAfter'] !=
                                            null
                                        ? (tx['balanceAfter'] as num).toDouble()
                                        : null;
                                    final noteRaw =
                                        (tx['note'] ?? tx['description'] ?? '')
                                            .toString();
                                    final note = noteRaw.toLowerCase();
                                    final fromEmail =
                                        (tx['fromEmail'] ?? '').toString();
                                    final toEmail =
                                        (tx['toEmail'] ?? '').toString();
                                    final hasRazorpay =
                                        tx['razorpayPaymentId'] != null &&
                                            tx['razorpayPaymentId']
                                                .toString()
                                                .isNotEmpty;
                                    final withdrawalStatus =
                                        (tx['status'] ?? '').toString();
                                    final date =
                                        (tx['createdAt'] ?? '').toString();
                                    final dateShort = date.length >= 10
                                        ? date.substring(0, 10)
                                        : date;

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
                                    } else if (note.contains('group expense') ||
                                        note.contains('group repayment')) {
                                      txLabel = t('group_repayment_label');
                                      txIcon = Icons.group_rounded;
                                      txBadgeColor = const Color(0xFF1565C0);
                                    } else if (note
                                        .contains('secure transaction')) {
                                      txLabel = t('secure_txn_label');
                                      txIcon = Icons.verified_user_rounded;
                                      txBadgeColor = const Color(0xFF6A1B9A);
                                    } else if (hasRazorpay) {
                                      txLabel = isCredit
                                          ? t('razorpay_received_label')
                                          : t('razorpay_p2p_label');
                                      txIcon = Icons.payment_rounded;
                                      txBadgeColor = AppColors.cyan;
                                    } else {
                                      txLabel = isCredit
                                          ? t('wallet_received_label')
                                          : t('wallet_transfer_label');
                                      txIcon = isCredit
                                          ? Icons.arrow_downward_rounded
                                          : Icons.arrow_upward_rounded;
                                      txBadgeColor = isCredit
                                          ? const Color(0xFF2E7D32)
                                          : const Color(0xFFFF8000);
                                    }

                                    final txColor = isCredit
                                        ? const Color(0xFF2E7D32)
                                        : const Color(0xFFD32F2F);
                                    final counterparty =
                                        isCredit ? fromEmail : toEmail;
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.orange,
                                            Colors.white,
                                            Colors.green
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(13),
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.cardBg(context),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: txBadgeColor
                                                      .withValues(alpha: 0.12),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(txIcon,
                                                    color: txBadgeColor,
                                                    size: 20),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    noteRaw.isNotEmpty
                                                        ? noteRaw
                                                        : txLabel,
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 13,
                                                        color: AppThemeColors
                                                            .primaryText(
                                                                context)),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(children: [
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 7,
                                                          vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: txBadgeColor
                                                            .withValues(
                                                                alpha: 0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                            color: txBadgeColor
                                                                .withValues(
                                                                    alpha:
                                                                        0.35),
                                                            width: 0.8),
                                                      ),
                                                      child: Text(txLabel,
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  txBadgeColor,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600)),
                                                    ),
                                                    if (hasRazorpay) ...[
                                                      const SizedBox(width: 6),
                                                      Icon(Icons.lock_rounded,
                                                          size: 11,
                                                          color: Colors
                                                              .green[700]),
                                                      const SizedBox(width: 2),
                                                      Text(t('secured_label'),
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors
                                                                  .green[700],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500)),
                                                    ],
                                                    if (isWithdrawal &&
                                                        withdrawalStatus
                                                            .isNotEmpty) ...[
                                                      const SizedBox(width: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 7,
                                                                vertical: 2),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: _withdrawalStatusColor(
                                                                  withdrawalStatus)
                                                              .withValues(
                                                                  alpha: 0.1),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          border: Border.all(
                                                              color: _withdrawalStatusColor(
                                                                      withdrawalStatus)
                                                                  .withValues(
                                                                      alpha:
                                                                          0.35),
                                                              width: 0.8),
                                                        ),
                                                        child: Text(
                                                            _withdrawalStatusLabel(
                                                                withdrawalStatus),
                                                            style: TextStyle(
                                                                fontSize: 10,
                                                                color: _withdrawalStatusColor(
                                                                    withdrawalStatus),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600)),
                                                      ),
                                                    ],
                                                  ]),
                                                  if (counterparty
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Row(children: [
                                                      Icon(
                                                        isCredit
                                                            ? Icons
                                                                .person_rounded
                                                            : Icons
                                                                .send_rounded,
                                                        size: 11,
                                                        color: AppThemeColors
                                                            .mutedText(context),
                                                      ),
                                                      const SizedBox(width: 3),
                                                      Expanded(
                                                        child: Text(
                                                          '${isCredit ? t('from_label') : t('to_label')}: $counterparty',
                                                          style: TextStyle(
                                                              fontSize: 10.5,
                                                              color: AppThemeColors
                                                                  .mutedText(
                                                                      context)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ]),
                                                  ],
                                                  const SizedBox(height: 3),
                                                  Row(children: [
                                                    Icon(
                                                        Icons
                                                            .calendar_today_rounded,
                                                        size: 11,
                                                        color: AppThemeColors
                                                            .mutedText(
                                                                context)),
                                                    const SizedBox(width: 4),
                                                    Text(dateShort,
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: AppThemeColors
                                                                .mutedText(
                                                                    context))),
                                                  ]),
                                                  if (isWithdrawal && (tx['failureReason'] ?? '').toString().isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Row(children: [
                                                      const Icon(Icons.info_outline_rounded, size: 11, color: Colors.red),
                                                      const SizedBox(width: 3),
                                                      Expanded(
                                                        child: Text(
                                                          tx['failureReason'].toString(),
                                                          style: const TextStyle(fontSize: 10.5, color: Colors.red),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                    ]),
                                                  ],
                                                ],
                                              )),
                                              const SizedBox(width: 8),
                                              Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.end,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      '${isCredit ? '+' : '-'}${formatAmount(amount)}',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                          color: txColor),
                                                    ),
                                                    if (balanceAfter !=
                                                        null) ...[
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        '${t('balance_colon_label')} ${formatAmount(balanceAfter)}',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color: AppThemeColors
                                                                .mutedText(
                                                                    context),
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500),
                                                      ),
                                                    ],
                                                    if (hasRazorpay) ...[
                                                      const SizedBox(height: 4),
                                                      GestureDetector(
                                                        onTap: () {
                                                          Clipboard.setData(ClipboardData(
                                                            text: tx['razorpayPaymentId'].toString(),
                                                          ));
                                                          showSnack(context, t('payment_id_copied_label'));
                                                        },
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.copy_rounded, size: 10, color: AppThemeColors.mutedText(context)),
                                                            const SizedBox(width: 3),
                                                            Text(t('copy_id_label'), style: TextStyle(fontSize: 9, color: AppThemeColors.mutedText(context))),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ]),
                                            ]),
                                      ),
                                    );
                                  },
                                ),
                              if (!_loading && _transactions.length < _historyTotal)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  child: _historyLoadingMore
                                      ? const Center(child: Padding(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2),
                                        ))
                                      : OutlinedButton.icon(
                                          onPressed: _loadMoreHistory,
                                          icon: const Icon(Icons.expand_more_rounded, size: 18),
                                          label: Text(t('load_more_label')),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppColors.cyan,
                                            side: const BorderSide(color: AppColors.cyan),
                                            minimumSize: const Size(double.infinity, 40),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                ),
                              const SizedBox(height: 24),
                            ])))) // closes Column.children + Column + SCView + RefreshIndicator + Expanded
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
          Flexible(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: color),
                  maxLines: 1)),
        ]),
      ),
    );
  }
}

// ─────────────────────── Withdrawal History Sheet ───────────────────────

class _WithdrawalHistorySheet extends StatefulWidget {
  const _WithdrawalHistorySheet();

  @override
  State<_WithdrawalHistorySheet> createState() => _WithdrawalHistorySheetState();
}

class _WithdrawalHistorySheetState extends State<_WithdrawalHistorySheet> {
  List<dynamic> _withdrawals = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/wallet/withdrawals');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _withdrawals = data['withdrawals'] ?? []; _loading = false; });
      } else {
        setState(() { _error = 'Failed to load withdrawals.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'processed': return const Color(0xFF2E7D32);
      case 'failed': return Colors.red;
      case 'reversed': return Colors.deepOrange;
      default: return Colors.orange;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'processed': return 'Processed';
      case 'failed': return 'Rejected';
      case 'reversed': return 'Reversed';
      default: return 'Pending';
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso.substring(0, 10);
    final local = dt.toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${local.day} ${months[local.month - 1]} ${local.year}, $h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.scaffoldBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 38, height: 4,
              decoration: BoxDecoration(
                color: AppThemeColors.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Text('My Withdrawal Requests',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: AppThemeColors.secondaryText(context), size: 20),
                    onPressed: _fetch,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _withdrawals.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_rounded, size: 56, color: AppThemeColors.divider(context)),
                                  const SizedBox(height: 12),
                                  Text('No withdrawal requests yet.',
                                      style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              color: AppColors.cyan,
                              onRefresh: _fetch,
                              child: ListView.builder(
                                controller: ctrl,
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                itemCount: _withdrawals.length,
                                itemBuilder: (_, i) => _wCard(_withdrawals[i] as Map<String, dynamic>),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wCard(Map<String, dynamic> w) {
    final amount = (w['amount'] as num?)?.toDouble() ?? 0;
    final status = (w['status'] ?? 'processing').toString();
    final mode = (w['mode'] ?? '').toString();
    final isUpi = mode == 'upi';
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(isUpi ? Icons.qr_code_rounded : Icons.account_balance_rounded,
                    size: 16, color: color),
                const SizedBox(width: 8),
                Text(isUpi ? 'UPI Withdrawal' : 'Bank Withdrawal',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                const Spacer(),
                Text('₹${amount.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withValues(alpha: 0.35)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_statusIcon(status), size: 12, color: color),
                        const SizedBox(width: 5),
                        Text(_statusLabel(status),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                      ]),
                    ),
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(context),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(isUpi ? 'UPI' : 'Bank',
                          style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (isUpi && (w['upiId'] ?? '').toString().isNotEmpty)
                  _row(Icons.alternate_email_rounded, 'UPI ID', w['upiId'].toString()),
                if (!isUpi) ...[
                  if ((w['accountHolderName'] ?? '').toString().isNotEmpty)
                    _row(Icons.person_outline_rounded, 'Account Holder', w['accountHolderName'].toString()),
                  if ((w['accountNumber'] ?? '').toString().isNotEmpty)
                    _row(Icons.credit_card_rounded, 'Account No.', w['accountNumber'].toString()),
                  if ((w['ifsc'] ?? '').toString().isNotEmpty)
                    _row(Icons.code_rounded, 'IFSC', w['ifsc'].toString()),
                  if ((w['bankName'] ?? '').toString().isNotEmpty)
                    _row(Icons.account_balance_rounded, 'Bank', w['bankName'].toString()),
                ],
                _row(Icons.schedule_rounded, 'Requested', _fmtDate((w['createdAt'] ?? '').toString())),
                if ((w['processedAt'] ?? '').toString().isNotEmpty)
                  _row(Icons.check_circle_outline_rounded, 'Processed', _fmtDate(w['processedAt'].toString()),
                      valueColor: const Color(0xFF2E7D32)),
                if (status == 'failed' && (w['failureReason'] ?? '').toString().isNotEmpty)
                  _row(Icons.info_outline_rounded, 'Reason', w['failureReason'].toString(),
                      valueColor: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'processed': return Icons.check_circle_rounded;
      case 'failed': return Icons.cancel_rounded;
      case 'reversed': return Icons.replay_rounded;
      default: return Icons.hourglass_top_rounded;
    }
  }

  Widget _row(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: AppThemeColors.mutedText(context)),
          const SizedBox(width: 6),
          SizedBox(width: 100,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AppThemeColors.primaryText(context))),
          ),
        ],
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded,
                    color: AppColors.cyan, size: 22),
              ),
              const SizedBox(width: 10),
              Text(t('add_money_to_wallet_title'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan)),
            ]),
            const SizedBox(height: 4),
            Text(t('real_money_topup_description'),
                style: TextStyle(
                    fontSize: 12,
                    color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [100, 250, 500, 1000, 2000, 5000]
                  .map(
                    (amt) => GestureDetector(
                      onTap: () => setState(() {
                        _amountCtrl.text = '$amt';
                        _error = null;
                      }),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppThemeColors.tinted(context,
                                light: const Color(0xFFF0F7FF),
                                dark: const Color(0xFF1B3A57)),
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Text('₹$amt',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.cyan,
                                  fontSize: 13)),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            tricolorBorder(
              child: TextField(
                controller: _amountCtrl,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: t('enter_amount_rupee_label'),
                  prefixText: '₹ ',
                  filled: true,
                  fillColor: AppThemeColors.tinted(context,
                      light: const Color(0xFFF5F7FA),
                      dark: const Color(0xFF2A2A2A)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.cyan, width: 1.5),
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white),
                label: Text(t('continue'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white)),
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
  final void Function(double addedAmount, double balance) onCredited;

  const _AddMoneyConfirmSheet(
      {required this.amount,
      required this.paymentLink,
      required this.onCredited});

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
      showSnack(context, t('enter_payment_id_before_closing_message'),
          isError: true);
    }
  }

  Future<void> _openPaymentLink() async {
    setState(() => _hasClickedPayNow = true);
    // razorpay.me Payment Handle pages don't support an amount query param —
    // passing one breaks the page with a generic error, so the payer must
    // type the amount in themselves on Razorpay's page (same as the
    // subscriptions manual-payment flow).
    await launchUrl(Uri.parse(widget.paymentLink),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _verify() async {
    final paymentId = _paymentIdCtrl.text.trim();
    if (paymentId.isEmpty) {
      setState(() => _errorText = t('please_enter_payment_id_message'));
      return;
    }
    setState(() {
      _verifying = true;
      _hasAttemptedVerify = true;
      _errorText = null;
    });
    try {
      final res =
          await ApiClient.post('/api/wallet/topup/manual/verify', body: {
        'paymentId': paymentId,
        'amount': widget.amount,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        Navigator.of(context).pop();
        widget.onCredited(
          (data['addedAmount'] as num).toDouble(),
          (data['balance'] as num).toDouble(),
        );
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _verifying = false;
          _errorText =
              err['error'] ?? t('payment_verification_failed_generic_message');
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _verifying = false;
          _errorText = e.toString().contains('SocketException')
              ? 'No internet connection. Please try again.'
              : 'Something went wrong. Please try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    return PopScope(
      canPop: _canClose(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          showSnack(context, t('enter_payment_id_before_closing_message'),
              isError: true);
        }
      },
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppThemeColors.secondaryText(context)),
                    onPressed: _tryClose,
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  t('amount_to_pay_colon_label').replaceFirst(
                      '{amount}', '₹${widget.amount.toStringAsFixed(2)}'),
                  style: TextStyle(
                      fontSize: 15,
                      color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF3A2F12)
                        : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFFFFCC02)
                            .withValues(alpha: isDark ? 0.5 : 1),
                        width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16,
                          color: isDark
                              ? const Color(0xFFFFD54F)
                              : const Color(0xFFF57F17)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('pay_exact_amount_wallet_warning_message')
                              .replaceFirst('{amount}',
                                  '₹${widget.amount.toStringAsFixed(2)}'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFFFFD54F)
                                  : const Color(0xFFF57F17)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF12283A)
                        : const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF2196F3)
                            .withValues(alpha: isDark ? 0.5 : 1),
                        width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16,
                              color: isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF1565C0)),
                          const SizedBox(width: 6),
                          Text(t('before_you_pay_label'),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? const Color(0xFF64B5F6)
                                      : const Color(0xFF1565C0))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(t('save_payment_id_and_receipt_message'),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFF1565C0))),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t('after_paying_enter_payment_id_message'),
                  style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _paymentIdCtrl,
                  enabled: !_verifying,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    hintText: 'pay_XXXXXXXXXXXXXX',
                    errorText: _errorText,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(t('verify_and_add_to_wallet_label')),
                ),
                if (_errorText != null && !_verifying) ...[
                  const SizedBox(height: 14),
                  Text(
                    t('need_help_with_payment_message'),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.help_center, size: 16),
                          label: Text(t('help_and_support'),
                              style: const TextStyle(fontSize: 12.5)),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => HelpSupportPage()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.contact_support, size: 16),
                          label: Text(t('contact_us_title'),
                              style: const TextStyle(fontSize: 12.5)),
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

  // Auth step — replaces the old bespoke OTP-only step with _WalletAuthStep
  // which supports both PIN and OTP.
  bool _showAuthStep = false;
  bool _hasPinSet = false;

  // Friend quick-pick strip — lets the sender tap an avatar instead of typing an email.
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = true;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
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

  @override
  void dispose() {
    _emailCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
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
      Color(0xFF0077B6),
      Color(0xFF2E7D32),
      Color(0xFF6A1B9A),
      Color(0xFFD32F2F),
      Color(0xFF00838F),
      Color(0xFFE65100),
      Color(0xFF1565C0),
      Color(0xFF558B2F),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String username) {
    final n = name.trim();
    if (n.isNotEmpty) {
      final parts = n.split(' ');
      if (parts.length >= 2)
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return n[0].toUpperCase();
    }
    if (username.trim().isNotEmpty) return username[0].toUpperCase();
    return '?';
  }

  bool _validateDetails(String t(String key)) {
    final to = _emailCtrl.text.trim();
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (to.isEmpty) {
      setState(() => _error = t('enter_email_message'));
      return false;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(to)) {
      setState(() => _error = t('please_enter_valid_email_address'));
      return false;
    }
    if (amt == null || amt <= 0) {
      setState(() => _error = t('enter_a_valid_amount_message'));
      return false;
    }
    if (amt > widget.walletBalance) {
      setState(() => _error =
          '${t('insufficient_balance_label')} (₹${widget.walletBalance.toStringAsFixed(2)})');
      return false;
    }
    return true;
  }

  // Called by _WalletAuthStep when user completes PIN or OTP verification.
  Future<void> _confirmAndPay(String authField, String credential) async {
    final t = AppLocalizations.of(context).t;
    final to = _emailCtrl.text.trim();
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post('/api/wallet/pay/verify-otp', body: {
        'to': to,
        'amount': amt,
        'note': _noteCtrl.text.trim(),
        authField: credential,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context);
        widget.onSuccess(amt, to);
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _sending = false;
          _showAuthStep = false;
          _error = err['error'] ?? t('payment_failed_label');
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _sending = false;
          _showAuthStep = false;
          _error = t('error_colon_label').replaceFirst('{error}', '$e');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFFF8000).withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.send_rounded,
                    color: Color(0xFFFF8000), size: 22),
              ),
              const SizedBox(width: 10),
              Text(t('pay_to_user_title'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF8000))),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFF0F7FF),
                      dark: const Color(0xFF16323A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: AppColors.cyan, size: 16),
                  const SizedBox(width: 6),
                  Text(
                      '${t('wallet_balance_colon_label')} ₹${widget.walletBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            if (!_showAuthStep) ...[
              if (_loadingFriends) ...[
                const Center(
                    child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.cyan)),
                )),
                const SizedBox(height: 6),
              ] else if (_friends.isNotEmpty) ...[
                Row(children: [
                  const Icon(Icons.people_alt_rounded,
                      size: 14, color: Color(0xFFFF8000)),
                  const SizedBox(width: 6),
                  Text(t('select_a_friend_label'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF8000))),
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
                      final fId = (f['_id'] ?? '').toString();
                      final name = (f['name'] ?? '').toString();
                      final username = (f['username'] ?? '').toString();
                      final email = (f['email'] ?? '').toString();
                      final selected = _emailCtrl.text.trim().toLowerCase() ==
                          email.toLowerCase();
                      final avatarColor = _avatarColor(name.isNotEmpty ? name : username);
                      final initials = _initials(name, username);
                      return GestureDetector(
                        onTap: () => setState(() {
                          _emailCtrl.text = email;
                          _error = null;
                        }),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: selected
                                  ? const LinearGradient(
                                      colors: [
                                          Colors.orange,
                                          Colors.white,
                                          Colors.green
                                        ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight)
                                  : null,
                              border: selected
                                  ? null
                                  : Border.all(
                                      color: AppThemeColors.divider(context),
                                      width: 1.4),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                          color: const Color(0xFFFF8000)
                                              .withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ]
                                  : null,
                            ),
                            child: Container(
                              width: 48, height: 48,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: avatarColor),
                              child: ClipOval(
                                child: Stack(fit: StackFit.expand, children: [
                                  Center(child: Text(initials,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15))),
                                  if (fId.isNotEmpty)
                                    Image.network(
                                      '${ApiConfig.baseUrl}/api/users/$fId/profile-image',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 62,
                            child: Text(
                              name.isNotEmpty
                                  ? name.split(' ').first
                                  : (username.isNotEmpty ? username : email),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: selected
                                    ? const Color(0xFFFF8000)
                                    : AppThemeColors.secondaryText(context),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 1.5),
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 1.5),
                    ),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Clarifying note — this only moves money between LenDen wallets.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFFFF8E1),
                      dark: const Color(0xFF4A3F1F)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Color(0xFFF57F17), size: 15),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(t('pay_user_wallet_only_note_message'),
                              style: const TextStyle(
                                  fontSize: 11.5, color: Color(0xFFF57F17)))),
                    ]),
              ),
            ] else ...[
              // Auth step — verify identity via PIN or Email OTP before debiting.
              _WalletAuthStep(
                hasPinSet: _hasPinSet,
                paying: _sending,
                onAuthenticated: _confirmAndPay,
                onBack: () => setState(() {
                  _showAuthStep = false;
                  _error = null;
                }),
              ),
            ],

            if (_error != null && !_showAuthStep)
              Padding(
                padding: const EdgeInsets.only(top: 10),
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

            if (!_showAuthStep) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _sendingOtp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white),
                  label: Text(t('continue'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white)),
                  onPressed: _sendingOtp
                      ? null
                      : () {
                          if (_validateDetails(t))
                            setState(() {
                              _showAuthStep = true;
                              _error = null;
                            });
                        },
                ),
              ),
            ],
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
  bool _showAuthStep = false;
  bool _hasPinSet = false;

  @override
  void initState() {
    super.initState();
    _fetchPinStatus();
  }

  Future<void> _fetchPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (mounted && res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _hasPinSet = data['hasPin'] == true);
      }
    } catch (_) {}
  }

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

  bool _validateForm() {
    final t = AppLocalizations.of(context).t;
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt < 100) {
      setState(() => _error = t('minimum_withdrawal_label'));
      return false;
    }
    if (amt > widget.walletBalance) {
      setState(() => _error =
          '${t('insufficient_balance_label')} (₹${widget.walletBalance.toStringAsFixed(2)})');
      return false;
    }
    if (_mode == 'upi' && _upiCtrl.text.trim().isEmpty) {
      setState(() => _error = t('enter_your_upi_id_message'));
      return false;
    }
    if (_mode == 'upi' && !_upiCtrl.text.trim().contains('@')) {
      setState(() => _error = t('invalid_upi_id_message'));
      return false;
    }
    if (_mode == 'bank_account') {
      if (_holderCtrl.text.trim().isEmpty) {
        setState(() => _error = t('enter_account_holder_name_message'));
        return false;
      }
      if (_accountCtrl.text.trim().isEmpty) {
        setState(() => _error = t('enter_account_number_message'));
        return false;
      }
      if (_ifscCtrl.text.trim().isEmpty) {
        setState(() => _error = t('enter_ifsc_code_message'));
        return false;
      }
    }
    return true;
  }

  Future<void> _submit(String authField, String credential) async {
    final t = AppLocalizations.of(context).t;
    final amt = double.parse(_amountCtrl.text.trim());
    setState(() { _loading = true; _error = null; });
    try {
      final body = <String, dynamic>{'amount': amt, 'mode': _mode, authField: credential};
      if (_mode == 'upi') {
        body['upiId'] = _upiCtrl.text.trim();
      } else {
        body['accountHolderName'] = _holderCtrl.text.trim();
        body['accountNumber'] = _accountCtrl.text.trim();
        body['ifsc'] = _ifscCtrl.text.trim().toUpperCase();
        if (_bankCtrl.text.trim().isNotEmpty)
          body['bankName'] = _bankCtrl.text.trim();
      }
      final res = await ApiClient.post('/api/wallet/withdraw', body: body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        Navigator.pop(context);
        widget.onSuccess(amt, manualReview: data['manualReview'] == true);
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _loading = false;
          _showAuthStep = false;
          _error = err['error'] ?? t('withdrawal_failed_label');
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _showAuthStep = false;
          _error = t('error_colon_label').replaceFirst('{error}', '$e');
        });
    }
  }

  InputDecoration _field(String label,
          {String? hint, Widget? prefix, Widget? prefixIcon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        prefix: prefix,
        filled: true,
        fillColor: AppThemeColors.surfaceBg(context),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
              Center(
                  child: Container(
                width: 48,
                height: 5,
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
                  child: const Icon(Icons.account_balance_rounded,
                      color: Color(0xFF1B5E20), size: 22),
                ),
                const SizedBox(width: 10),
                Text(t('withdraw_money_title'),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B5E20))),
              ]),
              const SizedBox(height: 10),
              // Balance pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: Color(0xFF2E7D32), size: 16),
                  const SizedBox(width: 6),
                  Text(
                      '${t('available_colon_label')} ₹${widget.walletBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ]),
              ),
              if (_showAuthStep) ...[
                const SizedBox(height: 16),
                _WalletAuthStep(
                  hasPinSet: _hasPinSet,
                  paying: _loading,
                  onAuthenticated: _submit,
                  onBack: () => setState(() { _showAuthStep = false; _error = null; }),
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
              ] else ...[
              const SizedBox(height: 16),
              // Mode toggle
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFF0F7FF),
                      dark: const Color(0xFF16323A)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                      child: GestureDetector(
                    onTap: () => setState(() => _mode = 'upi'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mode == 'upi'
                            ? const Color(0xFF1B5E20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.phone_android_rounded,
                                size: 16,
                                color: _mode == 'upi'
                                    ? Colors.white
                                    : const Color(0xFF1B5E20)),
                            const SizedBox(width: 6),
                            Text(t('upi_label'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _mode == 'upi'
                                      ? Colors.white
                                      : const Color(0xFF1B5E20),
                                )),
                          ]),
                    ),
                  )),
                  Expanded(
                      child: GestureDetector(
                    onTap: () => setState(() => _mode = 'bank_account'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _mode == 'bank_account'
                            ? const Color(0xFF1B5E20)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_rounded,
                                size: 16,
                                color: _mode == 'bank_account'
                                    ? Colors.white
                                    : const Color(0xFF1B5E20)),
                            const SizedBox(width: 6),
                            Text(t('bank_account_label'),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _mode == 'bank_account'
                                      ? Colors.white
                                      : const Color(0xFF1B5E20),
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
                  decoration: _field(t('amount_rupee_label'),
                      hint: t('minimum_rupee_100_hint'),
                      prefixIcon: const Icon(Icons.currency_rupee_rounded)),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(height: 12),
              // Mode-specific fields
              if (_mode == 'upi') ...[
                tricolorBorder(
                  child: TextField(
                    controller: _upiCtrl,
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('upi_id_label'),
                        hint: 'name@bank',
                        prefixIcon: const Icon(Icons.alternate_email_rounded)),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
              ] else ...[
                tricolorBorder(
                  child: TextField(
                    controller: _holderCtrl,
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('account_holder_name_label'),
                        prefixIcon: const Icon(Icons.person_rounded)),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _accountCtrl,
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('account_number_label'),
                        prefixIcon: const Icon(Icons.credit_card_rounded)),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _ifscCtrl,
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('ifsc_code_label'),
                        hint: 'HDFC0001234',
                        prefixIcon: const Icon(Icons.code_rounded)),
                    textCapitalization: TextCapitalization.characters,
                  ),
                ),
                const SizedBox(height: 12),
                tricolorBorder(
                  child: TextField(
                    controller: _bankCtrl,
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: _field(t('bank_name_optional_label'),
                        prefixIcon: const Icon(Icons.business_rounded)),
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
              const SizedBox(height: 20),
              // Manual review notice — money leaves the wallet now, but is transferred to the
              // user's bank/UPI by an admin since no automatic payout account is configured yet.
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFFFF8E1),
                      dark: const Color(0xFF4A3F1F)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Color(0xFFF57F17), size: 15),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(
                        t('withdraw_manual_review_notice_message'),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFF57F17)),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.account_balance_rounded,
                          color: Colors.white),
                  label: Text(
                      _loading
                          ? t('processing_ellipsis_label')
                          : t('withdraw_label'),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white)),
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() => _error = null);
                          if (_validateForm()) {
                            setState(() => _showAuthStep = true);
                          }
                        },
                ),
              ),
              ], // closes else [...
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────

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
      builder: (ctx) => _PaymentSheet(
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

class _PaymentSheet extends StatefulWidget {
  final String counterpartyEmail;
  final double amount;
  final String description;
  final String payEndpoint;
  final Map<String, dynamic> payBody;
  final VoidCallback? onSuccess;

  const _PaymentSheet({
    required this.counterpartyEmail,
    required this.amount,
    required this.description,
    required this.payEndpoint,
    required this.payBody,
    this.onSuccess,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
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
            _WalletAuthStep(
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

// ── Wallet auth step ──────────────────────────────────────────────────────────
// Inline widget shown inside payment sheets BEFORE the actual API call.
// Offers PIN (instant, no email needed) and Email OTP as auth methods, with
// a tab-style toggle at the top when the user has a PIN configured.
// Calls onAuthenticated('authPin'/'authOtp', code) on success; onBack to cancel.

class _WalletAuthStep extends StatefulWidget {
  final bool hasPinSet;
  final bool paying;
  final void Function(String authField, String credential) onAuthenticated;
  final VoidCallback onBack;

  const _WalletAuthStep({
    required this.hasPinSet,
    required this.onAuthenticated,
    required this.onBack,
    this.paying = false,
  });

  @override
  State<_WalletAuthStep> createState() => _WalletAuthStepState();
}

class _WalletAuthStepState extends State<_WalletAuthStep> {
  bool _usePinMode = true; // start in PIN mode if PIN is set
  String _code = '';
  bool _sendingOtp = false;
  bool _otpSent = false;
  String _otpEmail = '';
  int _timeRemaining = 120;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usePinMode = widget.hasPinSet;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String t(String key) => AppLocalizations.of(context).t(key);

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_timeRemaining > 0) {
          _timeRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _sendOtp() async {
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post('/api/wallet/auth/send-otp', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _sendingOtp = false;
          _otpSent = true;
          _otpEmail = (data['email'] ?? '').toString();
          _timeRemaining = 120;
          _code = '';
        });
        _startTimer();
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _sendingOtp = false;
          _error = err['error'] ?? t('failed_to_send_otp_retry');
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _sendingOtp = false;
          _error = '$e';
        });
    }
  }

  void _confirm() {
    if (_code.length != 6) {
      setState(() => _error = t('please_enter_valid_6_digit_otp'));
      return;
    }
    _timer?.cancel();
    widget.onAuthenticated(_usePinMode ? 'authPin' : 'authOtp', _code);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sendingOtp || widget.paying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Mode tabs — always shown so users discover PIN option ─────────
        Row(children: [
          _modeTab(t('use_pin_label'), Icons.dialpad_rounded, true),
          const SizedBox(width: 8),
          _modeTab(t('use_email_otp_label'), Icons.email_outlined, false),
        ]),
        const SizedBox(height: 16),

        // ── PIN mode ────────────────────────────────────────────────────────
        if (_usePinMode) ...[
          if (!widget.hasPinSet) ...[
            // PIN not configured yet — prompt user to set one
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t('pin_not_set_message'),
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.dialpad_rounded,
                            color: Colors.white, size: 16),
                        label: Text(t('set_pin_title'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SetWalletPinPage()));
                        },
                      ),
                    ),
                  ]),
            ),
          ] else ...[
            Text(t('enter_wallet_pin_label'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 10),
            Center(
                child: OtpInput(
              onChanged: (code) => setState(() {
                _code = code;
                _error = null;
              }),
              enabled: !busy,
              autoFocus: true,
              obscureText: true,
              showVisibilityToggle: true,
            )),
          ],
        ],

        // ── OTP mode ────────────────────────────────────────────────────────
        if (!_usePinMode) ...[
          if (!_otpSent) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _sendingOtp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.email_outlined, color: Colors.white),
                label: Text(
                    _sendingOtp ? t('sending_otp_label') : t('send_otp_label'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: busy ? null : _sendOtp,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: const Color(0xFFF0F7FF),
                    dark: const Color(0xFF16323A)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('otp_sent_to_email_desc'),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppThemeColors.secondaryText(context))),
                    const SizedBox(height: 3),
                    Text(_otpEmail,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan,
                            fontSize: 13)),
                  ]),
            ),
            Center(
                child: OtpInput(
              onChanged: (code) => setState(() {
                _code = code;
                _error = null;
              }),
              enabled: !busy,
              autoFocus: true,
            )),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (_timeRemaining > 30 ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          (_timeRemaining > 30 ? Colors.green : Colors.orange)
                              .withValues(alpha: 0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer,
                      size: 14,
                      color:
                          _timeRemaining > 30 ? Colors.green : Colors.orange),
                  const SizedBox(width: 4),
                  Text(_formatTime(_timeRemaining),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _timeRemaining > 30
                              ? Colors.green
                              : Colors.orange)),
                ]),
              ),
              TextButton(
                onPressed: (_timeRemaining == 0 && !busy) ? _sendOtp : null,
                child: Text(t('resend_otp'),
                    style: TextStyle(
                      color: (_timeRemaining == 0 && !busy)
                          ? AppColors.cyan
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ]),
          ],
        ],

        // ── Error ───────────────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Flexible(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.red, fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 16),

        // ── Confirm button ───────────────────────────────────────────────────
        if ((_usePinMode && widget.hasPinSet) || _otpSent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: widget.paying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user_rounded,
                      color: Colors.white),
              label: Text(
                  widget.paying
                      ? t('processing_ellipsis_label')
                      : t('verify_and_pay_label'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white)),
              onPressed: busy ? null : _confirm,
            ),
          ),
        const SizedBox(height: 8),
        // Back
        Center(
            child: TextButton(
          onPressed: busy ? null : widget.onBack,
          child: Text(t('cancel'),
              style: TextStyle(color: AppThemeColors.secondaryText(context))),
        )),
      ],
    );
  }

  Widget _modeTab(String label, IconData icon, bool isPinMode) {
    final selected = _usePinMode == isPinMode;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _usePinMode = isPinMode;
        _code = '';
        _error = null;
        _otpSent = false;
        _timer?.cancel();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  selected ? AppColors.cyan : AppThemeColors.divider(context)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 15,
              color: selected
                  ? Colors.white
                  : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppThemeColors.secondaryText(context))),
        ]),
      ),
    ));
  }
}

// ---------------------------------------------------------------------------
// Wallet page buy-coins sheet — proper StatefulWidget so the controller
// lifecycle is tied to the widget, not an outer function scope.
// SingleChildScrollView prevents the 99702-pixel RenderFlex overflow when
// the soft keyboard is open inside an isScrollControlled sheet.
// ---------------------------------------------------------------------------

class _WalletBuyCoinsSheet extends StatefulWidget {
  final double coinValue;
  final String coinCurrency;
  final double walletBalance;
  final DisplayCurrencyData? displayCurrencyData;
  final String initialDisplayCurrency;

  const _WalletBuyCoinsSheet({
    required this.coinValue,
    required this.coinCurrency,
    required this.walletBalance,
    required this.displayCurrencyData,
    required this.initialDisplayCurrency,
  });

  @override
  State<_WalletBuyCoinsSheet> createState() => _WalletBuyCoinsSheetState();
}

class _WalletBuyCoinsSheetState extends State<_WalletBuyCoinsSheet>
    with CurrencyDisplayMixin<_WalletBuyCoinsSheet> {
  late final TextEditingController _ctrl;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '10');
    loadCurrencies(
      seedData: widget.displayCurrencyData,
      seedCode: widget.initialDisplayCurrency,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _coins => int.tryParse(_ctrl.text.trim()) ?? 0;
  double get _baseCost => _coins * widget.coinValue;
  String get _totalCost => _baseCost.toStringAsFixed(2);
  bool get _canAfford => widget.walletBalance >= _baseCost;

  String get _displayCost => formatCurrencyAmount(
        _baseCost,
        from: widget.coinCurrency,
        to: selectedCurrency,
        data: currencyData,
      );

  String get _displayWalletBalance => formatCurrencyAmount(
        widget.walletBalance,
        from: 'INR',
        to: selectedCurrency,
        data: currencyData,
      );

  Future<void> _buy() async {
    if (_coins < 1 || !_canAfford) return;
    setState(() => _buying = true);
    try {
      final res = await ApiClient.post('/api/coins/buy-with-wallet',
          body: {'coinsToBuy': _coins});
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop(<String, dynamic>{
            'newWalletBalance': data['newWalletBalance'],
            'newCoinBalance': data['newCoinBalance'],
            'coins': _coins,
            'totalCost': _totalCost,
          });
        }
      } else {
        final err =
            (data['error'] ?? data['message'] ?? 'Purchase failed.').toString();
        if (mounted) showSnack(context, err, isError: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coins = _coins;
    final totalCost = _totalCost;
    final canAfford = _canAfford;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: const Color(0xFFFFF8E1),
                        dark: const Color(0xFF3A2F12)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.monetization_on_rounded,
                      color: Color(0xFFD4A017), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Buy LenDen Coins',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.primaryText(context),
                          )),
                      Text(
                        '1 coin = ${widget.coinCurrency} ${widget.coinValue.toStringAsFixed(2)}  •  Wallet: $_displayWalletBalance',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppThemeColors.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
                decoration: InputDecoration(
                  suffixText: 'coins',
                  suffixStyle: TextStyle(
                      fontSize: 16,
                      color: AppThemeColors.secondaryText(context)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppColors.cyan, width: 2)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [10, 25, 50, 100, 200].map((n) {
                  return ActionChip(
                    label: Text('+$n',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12)),
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.10),
                    side: const BorderSide(color: AppColors.cyan),
                    onPressed: () {
                      _ctrl.text = '$n';
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              buildSheetCurrencySelector(),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFEAF5FF),
                      dark: const Color(0xFF1B3A4A)),
                  borderRadius: BorderRadius.circular(14),
                  border: canAfford ? null : Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total cost',
                        style: TextStyle(
                            color: AppThemeColors.secondaryText(context))),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_displayCost,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: canAfford ? AppColors.cyan : Colors.red,
                            )),
                        if (selectedCurrency.toUpperCase() !=
                            widget.coinCurrency.toUpperCase())
                          Text(
                            '${widget.coinCurrency} $totalCost',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.mutedText(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!canAfford && coins > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Insufficient wallet balance',
                  style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (_buying || coins < 1 || !canAfford) ? null : _buy,
                  icon: _buying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.monetization_on_rounded),
                  label: Text(_buying
                      ? 'Buying…'
                      : 'Buy $coins Coin${coins == 1 ? '' : 's'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
