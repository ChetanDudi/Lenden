import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/group_transactions/group_transaction_page.dart';
import '../transaction/secure_transactions/view_secure_transactions_page.dart';
import '../digitise/subscriptions_page.dart';

// Razorpay only works on Android/iOS — not on Windows, Web, or macOS.
bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

// Test mode hint shown in all Razorpay payment sheets.
Widget get _testModeHint => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: BoxDecoration(
    color: const Color(0xFFFFF8E1),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: const Color(0xFFFFCC02), width: 1),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(children: [
        Icon(Icons.science_rounded, size: 14, color: Color(0xFFF57F17)),
        SizedBox(width: 6),
        Text('Test Mode — use these credentials in Razorpay:',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
      ]),
      const SizedBox(height: 4),
      _testRow(Icons.credit_card_rounded, 'Card', '4111 1111 1111 1111  |  Exp: 12/28  |  CVV: 123  |  OTP: 1234'),
      const SizedBox(height: 2),
      _testRow(Icons.phone_android_rounded, 'UPI', 'success@razorpay'),
    ],
  ),
);

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
  Razorpay? _razorpay;
  bool _processingPayment = false;
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    }
    _fetchWalletData();
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _amountController.dispose();
    super.dispose();
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

  Future<void> _initiateAddMoney(double amount) async {
    if (!_isMobile) {
      _showSnack('Razorpay payments are only available on Android & iOS.');
      return;
    }
    setState(() => _processingPayment = true);
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final orderRes = await ApiClient.post('/api/wallet/create-order', body: {
        'amount': (amount * 100).toInt(),
      });
      if (!mounted) return;
      if (orderRes.statusCode != 200) {
        final err = jsonDecode(orderRes.body);
        _showSnack(err['error'] ?? 'Failed to create order');
        setState(() => _processingPayment = false);
        return;
      }
      final orderData = jsonDecode(orderRes.body);
      final user = session.user ?? {};
      final options = {
        'key': orderData['keyId'],
        'amount': orderData['amount'],
        'currency': 'INR',
        'name': 'LenDen Wallet',
        'description': 'Add money to wallet',
        'order_id': orderData['orderId'],
        'prefill': {
          'email': user['email'] ?? '',
          'contact': user['phone'] ?? '',
          'name': user['name'] ?? '',
        },
        'theme': {'color': '#00B4D8'},
      };
      _razorpay!.open(options);
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e');
        setState(() => _processingPayment = false);
      }
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    try {
      final verifyRes = await ApiClient.post('/api/wallet/verify', body: {
        'razorpayOrderId': response.orderId,
        'razorpayPaymentId': response.paymentId,
        'razorpaySignature': response.signature,
      });
      if (!mounted) return;
      setState(() => _processingPayment = false);
      if (verifyRes.statusCode == 200) {
        final data = jsonDecode(verifyRes.body);
        _amountController.clear();
        _showSnack('₹${data['addedAmount'] ?? ''} added to wallet!', success: true);
        _fetchWalletData();
      } else {
        _showSnack('Payment received but verification failed. Contact support.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _processingPayment = false);
        _showSnack('Verification error: $e');
      }
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _processingPayment = false);
    _showSnack('Payment failed: ${response.message ?? 'Unknown'}');
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _processingPayment = false);
  }

  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ));
  }

  void _showAddMoneySheet() {
    _amountController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (context, setSheet) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                    decoration: BoxDecoration(color: const Color(0xFF00B4D8).withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, color: Color(0xFF00B4D8), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text('Add Money to Wallet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00B4D8))),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const SizedBox(width: 4),
                  Icon(Icons.lock_outline, size: 12, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text('Secured by Razorpay · Test Mode', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ]),
                const SizedBox(height: 10),
                _testModeHint,
                const SizedBox(height: 10),
                // Quick amount chips — tricolor gradient border
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: [100, 250, 500, 1000, 2000, 5000].map((amt) =>
                    GestureDetector(
                      onTap: () => setSheet(() => _amountController.text = '$amt'),
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
                            color: const Color(0xFFF0F7FF),
                            borderRadius: BorderRadius.circular(21),
                          ),
                          child: Text('₹$amt', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF00B4D8), fontSize: 13)),
                        ),
                      ),
                    ),
                  ).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Enter Amount (₹)',
                    prefixText: '₹ ',
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: _processingPayment
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payment_rounded, color: Colors.white),
                    label: Text(_processingPayment ? 'Processing...' : 'Pay & Add',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                    onPressed: _processingPayment ? null : () {
                      final amount = double.tryParse(_amountController.text.trim());
                      if (amount == null || amount < 1) {
                        _showSnack('Enter a valid amount (min ₹1)');
                        return;
                      }
                      Navigator.pop(ctx);
                      _initiateAddMoney(amount);
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showPayToUserSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PayToUserSheet(
        walletBalance: _walletBalance,
        onSuccess: (amount) {
          _showSnack('₹${amount.toStringAsFixed(2)} sent successfully!', success: true);
          _fetchWalletData();
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
        onSuccess: (amount, {bool isTestMode = false}) {
          final msg = isTestMode
              ? '[Test] ₹${amount.toStringAsFixed(2)} simulated — balance deducted'
              : '₹${amount.toStringAsFixed(2)} withdrawal initiated!';
          _showSnack(msg, success: true);
          _fetchWalletData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      body: Stack(
        children: [
          // Header gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 260,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0096C7), Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
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
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('LenDen Wallet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('Store & send real money', style: TextStyle(fontSize: 12, color: Colors.white70)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _fetchWalletData,
                    ),
                  ]),
                ),

                // ── Scrollable body ───────────────────────────────────
                Expanded(child: RefreshIndicator(
                  onRefresh: _fetchWalletData,
                  color: const Color(0xFF00B4D8),
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
                        BoxShadow(color: const Color(0xFF00B4D8).withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFF8000), size: 20),
                            const SizedBox(width: 7),
                            const Text('LenDen Wallet Balance', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF00B4D8))),
                          ]),
                          const SizedBox(height: 10),
                          _loading
                            ? const CircularProgressIndicator(color: Color(0xFF00B4D8))
                            : Text(
                                '₹${_walletBalance.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF00B4D8)),
                              ),
                          const SizedBox(height: 4),
                          Text('Available to send or pay', style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                          const SizedBox(height: 20),
                          Row(children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00B4D8),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                icon: const Icon(Icons.add_rounded, color: Colors.white),
                                label: const Text('Add Money', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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
                                label: const Text('Pay User', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
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
                              label: const Text('Withdraw to Bank / UPI', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
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
                    _infoBadge(Icons.security_rounded, 'Secure Payments', const Color(0xFF00B4D8)),
                    const SizedBox(width: 10),
                    _infoBadge(Icons.flash_on_rounded, 'Instant Transfer', const Color(0xFFFF8000)),
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
                          color: const Color(0xFFFFF8F0),
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
                              const Text('Settle Quick Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF8000))),
                              Text('Pay off pending balances with real money', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00B4D8).withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.group_rounded, color: Color(0xFF00B4D8), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Group Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00B4D8))),
                              Text('Settle shared group expenses', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ]),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF00B4D8)),
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
                          color: const Color(0xFFF0FFF4),
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
                              const Text('Secure Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                              Text('Manage lend & borrow records', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
                          color: const Color(0xFFF5F0FF),
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
                              const Text('Go Premium', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9C27B0))),
                              Text('Subscribe using your wallet balance', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
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
                    const Text('Transaction History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (!_loading && _transactions.isNotEmpty)
                      Text('${_transactions.length} records', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
                ),
                const SizedBox(height: 10),

                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFF00B4D8))),
                  )
                else if (_transactions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.receipt_long_rounded, size: 64, color: Colors.grey[200]),
                      const SizedBox(height: 8),
                      Text('No transactions yet', style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 4),
                      Text('Add money to get started', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                    ]),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    itemCount: _transactions.length,
                    itemBuilder: (_, i) {
                            final t = _transactions[i];
                            final type = (t['type'] ?? 'credit').toString();
                            final isWithdrawal = type == 'withdrawal';
                            final isCredit = !isWithdrawal && (type == 'credit' || type == 'topup' || type == 'add' || type == 'receive');
                            final amount = ((t['amount'] ?? 0) as num).toDouble();
                            final balanceAfter = t['balanceAfter'] != null ? (t['balanceAfter'] as num).toDouble() : null;
                            final noteRaw = (t['note'] ?? t['description'] ?? '').toString();
                            final note = noteRaw.toLowerCase();
                            final fromEmail = (t['fromEmail'] ?? '').toString();
                            final toEmail = (t['toEmail'] ?? '').toString();
                            final hasRazorpay = t['razorpayPaymentId'] != null && t['razorpayPaymentId'].toString().isNotEmpty;
                            final date = (t['createdAt'] ?? '').toString();
                            final dateShort = date.length >= 10 ? date.substring(0, 10) : date;

                            // Determine transaction category for badge
                            String txLabel;
                            IconData txIcon;
                            Color txBadgeColor;
                            if (isWithdrawal) {
                              txLabel = 'Withdrawal';
                              txIcon = Icons.account_balance_rounded;
                              txBadgeColor = const Color(0xFF1B5E20);
                            } else if (type == 'topup') {
                              txLabel = 'Wallet Top-up';
                              txIcon = Icons.add_card_rounded;
                              txBadgeColor = const Color(0xFF2E7D32);
                            } else if (note.contains('subscription')) {
                              txLabel = 'Subscription';
                              txIcon = Icons.workspace_premium_rounded;
                              txBadgeColor = const Color(0xFF9C27B0);
                            } else if (note.contains('group expense') || note.contains('group repayment')) {
                              txLabel = 'Group Repayment';
                              txIcon = Icons.group_rounded;
                              txBadgeColor = const Color(0xFF1565C0);
                            } else if (note.contains('secure transaction')) {
                              txLabel = 'Secure Txn';
                              txIcon = Icons.verified_user_rounded;
                              txBadgeColor = const Color(0xFF6A1B9A);
                            } else if (hasRazorpay) {
                              txLabel = isCredit ? 'Razorpay Received' : 'Razorpay P2P';
                              txIcon = Icons.payment_rounded;
                              txBadgeColor = const Color(0xFF00B4D8);
                            } else {
                              txLabel = isCredit ? 'Wallet Received' : 'Wallet Transfer';
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
                                  color: Colors.white,
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
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                                          Text('Secured', style: TextStyle(fontSize: 10, color: Colors.green[700], fontWeight: FontWeight.w500)),
                                        ],
                                      ]),
                                      if (counterparty.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          Icon(
                                            isCredit ? Icons.person_rounded : Icons.send_rounded,
                                            size: 11, color: Colors.grey[400],
                                          ),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: Text(
                                              '${isCredit ? 'From' : 'To'}: $counterparty',
                                              style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ]),
                                      ],
                                      const SizedBox(height: 3),
                                      Row(children: [
                                        Icon(Icons.calendar_today_rounded, size: 11, color: Colors.grey[400]),
                                        const SizedBox(width: 4),
                                        Text(dateShort, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
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
                                        'Bal: ₹${balanceAfter.toStringAsFixed(2)}',
                                        style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.w500),
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

// Reusable static method to show a payment sheet from any transaction page.
// Checks if counterparty phone exists; if not, shows a prompt.
class _PayToUserSheet extends StatefulWidget {
  final double walletBalance;
  final void Function(double amount) onSuccess;

  const _PayToUserSheet({required this.walletBalance, required this.onSuccess});

  @override
  State<_PayToUserSheet> createState() => _PayToUserSheetState();
}

class _PayToUserSheetState extends State<_PayToUserSheet> {
  final _emailCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final to = _emailCtrl.text.trim();
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (to.isEmpty) { setState(() => _error = 'Enter email'); return; }
    if (amt == null || amt <= 0) { setState(() => _error = 'Enter a valid amount'); return; }
    if (amt > widget.walletBalance) {
      setState(() => _error = 'Insufficient balance (₹${widget.walletBalance.toStringAsFixed(2)})');
      return;
    }
    setState(() { _sending = true; _error = null; });
    try {
      final res = await ApiClient.post('/api/wallet/pay', body: {
        'to': to, 'amount': amt, 'note': _noteCtrl.text.trim(),
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        Navigator.pop(context);
        widget.onSuccess(amt);
      } else {
        final err = jsonDecode(res.body);
        setState(() { _sending = false; _error = err['error'] ?? 'Payment failed'; });
      }
    } catch (e) {
      if (mounted) setState(() { _sending = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              const Text('Pay to User', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
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
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00B4D8), size: 16),
                  const SizedBox(width: 6),
                  Text('Wallet Balance: ₹${widget.walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF00B4D8), fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.person_search_rounded),
                hintText: 'user@example.com',
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              decoration: InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                ),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: const Icon(Icons.note_alt_outlined),
                filled: true,
                fillColor: const Color(0xFFF5F7FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
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
                  backgroundColor: const Color(0xFF00B4D8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white),
                label: Text(_sending ? 'Sending...' : 'Send Money',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                onPressed: _sending ? null : _submit,
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
  final void Function(double amount, {bool isTestMode}) onSuccess;

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
    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt < 10) {
      setState(() => _error = 'Minimum withdrawal is ₹10');
      return;
    }
    if (amt > widget.walletBalance) {
      setState(() => _error = 'Insufficient balance (₹${widget.walletBalance.toStringAsFixed(2)})');
      return;
    }
    if (_mode == 'upi' && _upiCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter your UPI ID');
      return;
    }
    if (_mode == 'upi' && !_upiCtrl.text.trim().contains('@')) {
      setState(() => _error = 'Invalid UPI ID (e.g. name@bank)');
      return;
    }
    if (_mode == 'bank_account') {
      if (_holderCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter account holder name'); return; }
      if (_accountCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter account number'); return; }
      if (_ifscCtrl.text.trim().isEmpty) { setState(() => _error = 'Enter IFSC code'); return; }
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
        widget.onSuccess(amt, isTestMode: data['testMode'] == true);
      } else {
        final err = jsonDecode(res.body);
        setState(() { _loading = false; _error = err['error'] ?? 'Withdrawal failed'; });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Error: $e'; });
    }
  }

  InputDecoration _field(String label, {String? hint, Widget? prefix, Widget? prefixIcon}) => InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    prefix: prefix,
    filled: true,
    fillColor: const Color(0xFFF5F7FA),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF1B5E20), width: 1.5),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                  color: Colors.grey.shade300,
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
                const Text('Withdraw Money', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
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
                  Text('Available: ₹${widget.walletBalance.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 16),
              // Mode toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
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
                        Text('UPI', style: TextStyle(
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
                        Text('Bank Account', style: TextStyle(
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
              TextField(
                controller: _amountCtrl,
                decoration: _field('Amount (₹)', hint: 'Minimum ₹10', prefixIcon: const Icon(Icons.currency_rupee_rounded)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              // Mode-specific fields
              if (_mode == 'upi') ...[
                TextField(
                  controller: _upiCtrl,
                  decoration: _field('UPI ID', hint: 'name@bank', prefixIcon: const Icon(Icons.alternate_email_rounded)),
                  keyboardType: TextInputType.emailAddress,
                ),
              ] else ...[
                TextField(
                  controller: _holderCtrl,
                  decoration: _field('Account Holder Name', prefixIcon: const Icon(Icons.person_rounded)),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _accountCtrl,
                  decoration: _field('Account Number', prefixIcon: const Icon(Icons.credit_card_rounded)),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ifscCtrl,
                  decoration: _field('IFSC Code', hint: 'HDFC0001234', prefixIcon: const Icon(Icons.code_rounded)),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bankCtrl,
                  decoration: _field('Bank Name (optional)', prefixIcon: const Icon(Icons.business_rounded)),
                  textCapitalization: TextCapitalization.words,
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
              // Test mode notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFCC02), width: 1),
                ),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.science_rounded, color: Color(0xFFF57F17), size: 15),
                  SizedBox(width: 8),
                  Flexible(child: Text(
                    'Test Mode — wallet balance will be deducted but no real money is transferred. In production with live Razorpay X keys, funds go to your bank/UPI.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7B5800)),
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
                  label: Text(_loading ? 'Processing...' : 'Withdraw',
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
    if (!_isMobile) {
      setState(() => _error = 'Razorpay payments are only available on Android & iOS.');
      return;
    }
    if (!widget.hasPhone && _phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the phone number above to pay via Razorpay / UPI.');
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
        setState(() { _payingRazorpay = false; _error = err['error'] ?? 'Failed to create order'; });
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
      if (mounted) setState(() { _payingRazorpay = false; _error = 'Error: $e'; });
    }
  }

  Future<void> _payViaWallet() async {
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
        setState(() => _error = err['error'] ?? 'Payment failed');
      }
    } catch (e) {
      if (mounted) setState(() { _payingWallet = false; _error = 'Error: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
            const Text('Pay Now', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
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
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.person_outline, size: 16, color: Color(0xFF00B4D8)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(widget.counterpartyEmail, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
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
                    Icon(Icons.note_outlined, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Expanded(child: Text(widget.description, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
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
                  const Text("Phone number not found", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    "The other member's phone is not on LenDen. Enter it manually if you know it (for UPI), or pay via LenDen Wallet.",
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
                decoration: InputDecoration(
                  hintText: 'Enter phone number (optional, for UPI)',
                  prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF00B4D8), size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00B4D8))),
                  filled: true,
                  fillColor: const Color(0xFFF8FBFF),
                ),
                onChanged: (_) => setLocal(() {}),
              );
            }),
            const SizedBox(height: 14),
          ],

          // Test mode hint
          _testModeHint,
          const SizedBox(height: 14),

          // Razorpay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: _payingRazorpay
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payment_rounded, color: Colors.white),
              label: Text(_payingRazorpay ? 'Processing...' : 'Pay via Razorpay (UPI & more)',
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
                side: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _payingWallet
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4D8)))
                : const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00B4D8)),
              label: Text(_payingWallet ? 'Processing...' : 'Pay via LenDen Wallet',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF00B4D8))),
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
      setState(() => _error = 'Razorpay is only available on Android & iOS.');
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
        setState(() { _verifying = false; _error = 'Payment done but verification failed. Contact support.'; });
      }
    } catch (e) {
      if (mounted) setState(() { _verifying = false; _error = 'Verification error: $e'; });
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = response.message?.isNotEmpty == true ? response.message! : 'Payment cancelled or failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final amountRupees = ((widget.options['amount'] as num?) ?? 0) / 100;
    final description = widget.options['description']?.toString() ?? '';

    // Full-screen verifying overlay
    if (_verifying) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F7FF),
        body: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 52, height: 52,
              child: CircularProgressIndicator(color: Color(0xFF00B4D8), strokeWidth: 3)),
            SizedBox(height: 20),
            Text('Verifying payment...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF00B4D8))),
            SizedBox(height: 6),
            Text('Please wait, do not go back.', style: TextStyle(fontSize: 13, color: Colors.grey)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF00B4D8)),
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
                  boxShadow: [BoxShadow(color: const Color(0xFF00B4D8).withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 8))],
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payment_rounded, color: Color(0xFF00B4D8), size: 38),
                    ),
                    const SizedBox(height: 16),
                    const Text('Complete Your Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF00B4D8))),
                    const SizedBox(height: 14),
                    Text('₹${amountRupees.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Color(0xFFFF8000))),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(description, style: TextStyle(fontSize: 13, color: Colors.grey[500]), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 18),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.lock_outline, size: 13, color: Colors.grey[400]),
                      const SizedBox(width: 4),
                      Text('Secured by Razorpay', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
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
                    backgroundColor: const Color(0xFF00B4D8),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: _opening
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.open_in_new_rounded, color: Colors.white),
                  label: Text(
                    _opening ? 'Opening...' : (_error != null ? 'Retry Payment' : 'Open Razorpay  (UPI & more)'),
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
