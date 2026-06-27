import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/display_currency_helper.dart';
import '../../widgets/payment_success_page.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

// Models
class SubscriptionPlan {
  final String id;
  final String name;
  final double price;
  final int duration;
  final List<String> features;
  final bool isAvailable;
  final int discount;
  final int free;

  SubscriptionPlan(
      {required this.id,
      required this.name,
      required this.price,
      required this.duration,
      required this.features,
      required this.isAvailable,
      required this.discount,
      required this.free});

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['_id'],
      name: json['name'],
      price: json['price'].toDouble(),
      duration: json['duration'],
      features: List<String>.from(json['features']),
      isAvailable: json['isAvailable'],
      discount: json['discount'] ?? 0,
      free: json['free'] ?? 0,
    );
  }
}

class PremiumBenefit {
  final String id;
  final String text;

  PremiumBenefit({required this.id, required this.text});

  factory PremiumBenefit.fromJson(Map<String, dynamic> json) {
    return PremiumBenefit(
      id: json['_id'],
      text: json['text'],
    );
  }
}

class Faq {
  final String id;
  final String question;
  final String answer;

  Faq({required this.id, required this.question, required this.answer});

  factory Faq.fromJson(Map<String, dynamic> json) {
    return Faq(
      id: json['_id'],
      question: json['question'],
      answer: json['answer'],
    );
  }
}

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({Key? key}) : super(key: key);

  @override
  _SubscriptionsPageState createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  Widget get _razorpayTestHint {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCC02), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.science_rounded, size: 13, color: Color(0xFFF57F17)),
            const SizedBox(width: 6),
            Text(t('razorpay_test_mode_hint_label'),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF57F17))),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.credit_card_rounded, size: 12, color: Color(0xFF795548)),
            const SizedBox(width: 5),
            Text(t('card_colon_label'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF795548))),
            const Expanded(child: Text('4111 1111 1111 1111  |  12/28  |  CVV 123  |  OTP 1234',
              style: TextStyle(fontSize: 11, color: Color(0xFF795548)))),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.phone_android_rounded, size: 12, color: Color(0xFF795548)),
            const SizedBox(width: 5),
            Text(t('upi_colon_label'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF795548))),
            const Text('success@razorpay', style: TextStyle(fontSize: 11, color: Color(0xFF795548))),
          ]),
        ],
      ),
    );
  }

  String? _selectedPlan;
  String _searchQuery = '';
  String _filterOption = 'All'; // All, Active, Expired
  bool _showComparison = false;
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
  String? _displayCurrencyError;

  List<SubscriptionPlan> _plans = [];
  List<PremiumBenefit> _benefits = [];
  List<Faq> _faqs = [];

  bool _isLoadingPlans = false;
  bool _isLoadingBenefits = false;
  bool _isLoadingFaqs = false;
  bool _isProcessingPayment = false;
  bool _isPayingViaWallet = false;
  bool _showRenewalSection = false;
  double _walletBalance = 0;
  String? _pendingPlanId;

  Razorpay? _razorpay;

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Provider.of<SessionProvider>(context, listen: false)
        .checkSubscriptionStatus();
    _loadDisplayCurrencies();
    _fetchSubscriptionData();
    if (_isMobilePlatform) {
      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSubscriptionData() async {
    await Future.wait([_fetchPlans(), _fetchBenefits(), _fetchFaqs(), _fetchWalletBalance()]);
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final res = await ApiClient.get('/api/wallet/balance');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() => _walletBalance = (data['balance'] ?? 0).toDouble());
      }
    } catch (_) {}
  }

  Future<void> _loadDisplayCurrencies() async {
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = data;
        _displayCurrencyError = null;
        final exists = data.currencies.any(
          (item) => item['code'] == _selectedDisplayCurrency,
        );
        if (!exists) {
          _selectedDisplayCurrency = 'INR';
        }
      });
    } catch (_) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
        _displayCurrencyError = t('currency_conversion_unavailable_message');
      });
    }
  }

  bool _hasMissingPlanConversion() {
    if (_selectedDisplayCurrency.toUpperCase() == 'INR') return false;
    if (_displayCurrencyData == null) return true;
    return !_displayCurrencyData!.canConvert('INR', _selectedDisplayCurrency);
  }

  String _formatPlanAmount(double amountInInr) {
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final canConvert = _displayCurrencyData?.canConvert('INR', targetCurrency) ??
        (targetCurrency == 'INR');
    if (!canConvert) {
      return '₹${amountInInr.toStringAsFixed(2)}';
    }
    final converted = _displayCurrencyData?.convert(
          amountInInr,
          'INR',
          targetCurrency,
        ) ??
        amountInInr;
    final symbol =
        _displayCurrencyData?.symbolFor(targetCurrency) ??
            (targetCurrency == 'INR' ? '₹' : targetCurrency);
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  Widget _buildCurrencySelector() {
    final currencies = _displayCurrencyData?.currencies ??
        const <Map<String, String>>[
          {'code': 'INR', 'symbol': '₹', 'label': ''},
        ];
    return Container(
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedDisplayCurrency,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            borderRadius: BorderRadius.circular(16),
            dropdownColor: AppThemeColors.cardBg(context),
            items: currencies
                .map(
                  (currency) => DropdownMenuItem<String>(
                    value: currency['code'],
                    child: Text(
                      '${currency['symbol']} ${currency['code']}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(context)),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedDisplayCurrency = value;
              });
            },
          ),
        ),
      ),
    );
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoadingPlans = true;
    });
    final response = await ApiClient.get('/api/subscription/plans');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _plans = data.map((item) => SubscriptionPlan.fromJson(item)).toList();
        // Auto-select first available plan so user can pay immediately
        if (_selectedPlan == null && _plans.isNotEmpty) {
          _selectedPlan = _plans.first.name;
        }
      });
    } else {
      // Handle error
    }
    setState(() {
      _isLoadingPlans = false;
    });
  }

  Future<void> _fetchBenefits() async {
    setState(() {
      _isLoadingBenefits = true;
    });
    final response = await ApiClient.get('/api/subscription/benefits');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _benefits = data.map((item) => PremiumBenefit.fromJson(item)).toList();
      });
    } else {
      // Handle error
    }
    setState(() {
      _isLoadingBenefits = false;
    });
  }

  Future<void> _fetchFaqs() async {
    setState(() {
      _isLoadingFaqs = true;
    });
    final response = await ApiClient.get('/api/subscription/faqs');
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _faqs = data.map((item) => Faq.fromJson(item)).toList();
      });
    } else {
      // Handle error
    }
    setState(() {
      _isLoadingFaqs = false;
    });
  }

  Future<void> _startPayment() async {
    final t = AppLocalizations.of(context).t;
    if (_selectedPlan == null) {
      showSnack(context, t('please_select_a_plan_message'), isError: true);
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.token == null || session.user == null) {
      showSnack(context, t('please_login_to_subscribe_message'), isError: true);
      return;
    }

    if (!_isMobilePlatform) {
      showSnack(context, t('payment_only_supported_mobile_message'), isError: true);
      return;
    }

    final plan = _plans.firstWhere((p) => p.name == _selectedPlan);

    setState(() => _isProcessingPayment = true);

    try {
      // Step 1: Create order on backend
      final orderRes = await ApiClient.post(
        '/api/payment/create-order',
        body: {'planId': plan.id},
      );

      if (!mounted) return;

      if (orderRes.statusCode != 200) {
        final err = jsonDecode(orderRes.body);
        showSnack(context, err['error'] ?? t('failed_to_create_payment_order_message'), isError: true);
        setState(() => _isProcessingPayment = false);
        return;
      }

      final orderData = jsonDecode(orderRes.body);
      _pendingPlanId = orderData['plan']['id'];

      // Step 2: Open Razorpay checkout
      final user = session.user!;
      final options = {
        'key': orderData['keyId'],
        'amount': orderData['amount'],
        'currency': orderData['currency'] ?? 'INR',
        'name': 'LenDen App',
        'description': '${plan.name} Subscription',
        'order_id': orderData['orderId'],
        'prefill': {
          'email': user['email'] ?? '',
          'contact': user['phone'] ?? '',
          'name': user['name'] ?? '',
        },
        'theme': {'color': '#00B4D8'},
        'retry': {'enabled': true, 'max_count': 2},
      };

      _razorpay!.open(options);
      // Payment result arrives in _handlePaymentSuccess / _handlePaymentError
    } catch (e) {
      if (!mounted) return;
      showSnack(context, t('error_initiating_payment_message').replaceFirst('{error}', '$e'), isError: true);
      setState(() => _isProcessingPayment = false);
    }
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    // Step 3: Verify payment signature on backend
    try {
      final verifyRes = await ApiClient.post(
        '/api/payment/verify',
        body: {
          'razorpayOrderId': response.orderId,
          'razorpayPaymentId': response.paymentId,
          'razorpaySignature': response.signature,
          'planId': _pendingPlanId,
        },
      );

      if (!mounted) return;
      setState(() => _isProcessingPayment = false);

      if (verifyRes.statusCode == 200) {
        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.checkSubscriptionStatus();
        await session.fetchSubscriptionHistory();
        if (!mounted) return;
        _showSuccessDialog();
      } else {
        final err = jsonDecode(verifyRes.body);
        showSnack(context, t('payment_verification_failed_message').replaceFirst('{error}', err['error'] ?? ''), isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessingPayment = false);
      showSnack(context, t('payment_done_verification_error_message').replaceFirst('{error}', '$e'), isError: true);
    }
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    setState(() => _isProcessingPayment = false);
    final message = response.message ?? t('payment_failed_label');
    showSnack(context, t('payment_cancelled_or_failed_message').replaceFirst('{message}', message), isError: true);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    setState(() => _isProcessingPayment = false);
    showSnack(context, t('external_wallet_selected_message').replaceFirst('{wallet}', response.walletName ?? ''));
  }

  Future<void> _payViaWallet() async {
    final t = AppLocalizations.of(context).t;
    if (_selectedPlan == null) {
      showSnack(context, t('please_select_a_plan_message'), isError: true);
      return;
    }
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.token == null || session.user == null) {
      showSnack(context, t('please_login_to_subscribe_message'), isError: true);
      return;
    }
    final plan = _plans.firstWhere((p) => p.name == _selectedPlan);
    final actualPrice = plan.price * (1 - plan.discount / 100);
    if (_walletBalance < actualPrice) {
      showSnack(context, t('insufficient_wallet_balance_message')
          .replaceFirst('{needed}', actualPrice.toStringAsFixed(2))
          .replaceFirst('{available}', _walletBalance.toStringAsFixed(2)), isError: true);
      return;
    }
    setState(() => _isPayingViaWallet = true);
    try {
      final res = await ApiClient.post('/api/wallet/pay-subscription', body: {'planId': plan.id});
      if (!mounted) return;
      setState(() => _isPayingViaWallet = false);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() => _walletBalance = (data['balance'] ?? _walletBalance).toDouble());
        await session.checkSubscriptionStatus();
        await session.fetchSubscriptionHistory();
        if (!mounted) return;
        _showSuccessDialog();
      } else {
        final err = json.decode(res.body);
        showSnack(context, err['error'] ?? t('wallet_payment_failed_message'), isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPayingViaWallet = false);
        showSnack(context, t('error_colon_label').replaceFirst('{error}', '$e'), isError: true);
      }
    }
  }

  void _showSuccessDialog() {
    final t = AppLocalizations.of(context).t;
    double? planPrice;
    String planLabel = _selectedPlan ?? t('premium_label');
    try {
      final plan = _plans.firstWhere((p) => p.name == _selectedPlan!);
      planPrice = plan.price * (1 - plan.discount / 100);
      if (plan.discount > 0) planLabel = t('plan_with_discount_off_label')
          .replaceFirst('{plan}', plan.name)
          .replaceFirst('{discount}', '${plan.discount}');
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessPage(
          title: t('subscription_activated_label'),
          amount: planPrice,
          transactionType: t('subscription_em_dash_plan_label').replaceFirst('{plan}', planLabel),
          extraDetails: {t('status_label'): t('premium_member_check_label')},
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Color _getBenefitColor(int index) {
    final colors = [
      Color(0xFFFFF4E6), // Cream
      Color(0xFFE8F5E9), // Light green
      Color(0xFFFCE4EC), // Light pink
      Color(0xFFE3F2FD), // Light blue
      Color(0xFFFFF9C4), // Light yellow
      Color(0xFFF3E5F5), // Light purple
    ];
    return colors[index % colors.length];
  }

  List<Map<String, dynamic>> _getFilteredHistory(
      List<Map<String, dynamic>> history) {
    return history.where((sub) {
      // Search filter
      final matchesSearch = _searchQuery.isEmpty ||
          sub['subscriptionPlan']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());

      // Status filter
      bool matchesFilter = true;
      if (_filterOption == 'Active') {
        final endDate = DateTime.parse(sub['endDate']);
        matchesFilter =
            sub['status'] == 'active' && endDate.isAfter(DateTime.now());
      } else if (_filterOption == 'Expired') {
        final endDate = DateTime.parse(sub['endDate']);
        matchesFilter =
            sub['status'] == 'expired' || endDate.isBefore(DateTime.now());
      }

      return matchesSearch && matchesFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(t('go_premium_label'),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Consumer<SessionProvider>(
        builder: (context, session, child) {
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipPath(
                  clipper: TopWaveClipper(),
                  child: Container(
                    height: context.sh(156),
                    color: AppColors.cyan,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipPath(
                  clipper: BottomWaveClipper(),
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.13,
                    color: AppColors.cyan,
                  ),
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, context.sh(45), 20, 20),
                  child: Column(
                    children: [
                      if (session.subscriptionHistory != null &&
                          session.subscriptionHistory!.isNotEmpty)
                        _buildSubscriptionHistory(session.subscriptionHistory!),
                      session.isSubscribed
                          ? _buildSubscribedView(session)
                          : _buildSubscribeView(),
                      const SizedBox(height: 20),
                      _buildFAQSection(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _showAllHistory = false;

  Widget _buildSubscriptionHistory(List<Map<String, dynamic>> history) {
    final t = AppLocalizations.of(context).t;
    final filteredHistory = _getFilteredHistory(history);
    final itemsToShow =
        _showAllHistory ? filteredHistory : filteredHistory.take(3).toList();
    final filterLabels = {
      'All': t('all_label'),
      'Active': t('active_label'),
      'Expired': t('expired_label'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('subscription_history_label'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 15),

        // Search Bar
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                hintText: t('search_by_plan_name_hint'),
                border: InputBorder.none,
                icon: Icon(Icons.search, color: AppColors.cyan),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),

        const SizedBox(height: 15),

        // Filter Chips
        Wrap(
          spacing: 8,
          children: ['All', 'Active', 'Expired'].map((filter) {
            return FilterChip(
              label: Text(filterLabels[filter]!),
              selected: _filterOption == filter,
              onSelected: (selected) {
                setState(() {
                  _filterOption = filter;
                });
              },
              selectedColor: AppColors.cyan,
              backgroundColor: AppThemeColors.cardBg(context),
              labelStyle: TextStyle(
                color: _filterOption == filter ? Colors.white : AppThemeColors.primaryText(context),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 15),

        // History List
        if (itemsToShow.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                t('no_subscriptions_found_message'),
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          ...itemsToShow.map((sub) {
            final endDate = DateTime.parse(sub['endDate']);
            final isActive =
                sub['status'] == 'active' && endDate.isAfter(DateTime.now());
            final paymentMethod = (sub['paymentMethod'] ?? 'razorpay').toString();
            final actualPrice = ((sub['actualPrice'] ?? sub['price'] ?? 0) as num).toDouble();
            final duration = ((sub['duration'] ?? 0) as num).toInt();

            IconData pmIcon;
            String pmLabel;
            Color pmColor;
            if (paymentMethod == 'wallet') {
              pmIcon = Icons.account_balance_wallet_rounded;
              pmLabel = t('lenden_wallet_label');
              pmColor = AppColors.cyan;
            } else if (paymentMethod == 'admin') {
              pmIcon = Icons.admin_panel_settings_rounded;
              pmLabel = t('admin_label');
              pmColor = Colors.deepPurple;
            } else {
              pmIcon = Icons.payment_rounded;
              pmLabel = t('razorpay_label');
              pmColor = const Color(0xFF528FF5);
            }

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: isActive
                      ? [Colors.green, Colors.white, Colors.green]
                      : [Colors.grey, Colors.white, Colors.grey],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFE8F5E9) : Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Icon(
                    isActive ? Icons.check_circle : Icons.history,
                    color: isActive ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        sub['subscriptionPlan'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isActive
                            ? t('active_until_message').replaceFirst('{date}', endDate.toLocal().toString().substring(0, 10))
                            : t('expired_on_message').replaceFirst('{date}', endDate.toLocal().toString().substring(0, 10)),
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      if (isActive) ...[
                        const SizedBox(height: 3),
                        Builder(builder: (_) {
                          final daysLeft = endDate.difference(DateTime.now()).inDays;
                          final hoursLeft = endDate.difference(DateTime.now()).inHours % 24;
                          final label = daysLeft > 0
                              ? t('days_left_message').replaceFirst('{count}', '$daysLeft')
                              : hoursLeft > 0
                                  ? t('hours_left_message').replaceFirst('{count}', '$hoursLeft')
                                  : t('expiring_soon_label');
                          final color = daysLeft <= 3
                              ? Colors.orange
                              : AppColors.cyan;
                          return Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 12, color: color),
                              const SizedBox(width: 4),
                              Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 5),
                      Row(children: [
                        // Payment method badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: pmColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: pmColor.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(pmIcon, size: 10, color: pmColor),
                            const SizedBox(width: 3),
                            Text(pmLabel, style: TextStyle(fontSize: 10, color: pmColor, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        if (actualPrice > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '₹${actualPrice.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF8000)),
                          ),
                        ],
                        if (duration > 0) ...[
                          const SizedBox(width: 6),
                          Text(t('duration_days_count_message').replaceFirst('{duration}', '$duration'), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        ],
                      ]),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      isActive ? t('active_caps_label') : t('expired_caps_label'),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    backgroundColor: isActive ? Colors.green : Colors.grey,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ),
            );
          }),

        if (filteredHistory.length > 3)
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showAllHistory = !_showAllHistory;
                });
              },
              child: Text(_showAllHistory ? t('show_less_label') : t('view_all_label')),
            ),
          ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildSubscribedView(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final daysRemaining = session.subscriptionEndDate != null
        ? session.subscriptionEndDate!.difference(DateTime.now()).inDays
        : 0;
    final freeDaysRemaining =
        session.free != null && session.subscriptionEndDate != null
            ? session.free! -
                (DateTime.now().difference(session.subscriptionEndDate!).inDays)
            : 0;

    return Column(
      children: [
        // Stats Dashboard
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.cyan, Color(0xFF0096C7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  '🎉 ${t('premium_member_label')}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatCard(
                          Icons.calendar_today,
                          daysRemaining > 0
                              ? '$daysRemaining'
                              : (freeDaysRemaining > 0
                                  ? '$freeDaysRemaining'
                                  : t('expired_label')),
                          daysRemaining > 0
                              ? t('days_left_label')
                              : (freeDaysRemaining > 0
                                  ? t('free_days_left_label')
                                  : t('status_label'))),
                      SizedBox(width: 20),
                      _buildStatCard(
                          Icons.workspace_premium,
                          session.subscriptionPlan?.split(' ')[0] ?? t('na_label'),
                          t('plan_label')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Active Subscription Details
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE4EC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      t('subscription_details_label'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Icon(Icons.edit, color: AppColors.cyan),
                  ],
                ),
                const SizedBox(height: 20),
                _buildInfoRow(t('plan_colon_label'), session.subscriptionPlan ?? t('na_label')),
                const SizedBox(height: 10),
                _buildInfoRow(
                    t('expires_on_colon_label'),
                    session.subscriptionEndDate
                            ?.toLocal()
                            .toString()
                            .split(' ')[0] ??
                        t('na_label')),
                const SizedBox(height: 20),
                Text(
                  t('premium_features_colon_label'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                ..._benefits.asMap().entries.map((entry) {
                  int idx = entry.key;
                  PremiumBenefit benefit = entry.value;
                  return _buildBenefitItem(idx, Icons.check, benefit.text, '');
                }).toList(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _showRenewalSection = !_showRenewalSection),
            icon: Icon(
              _showRenewalSection ? Icons.keyboard_arrow_up_rounded : Icons.refresh_rounded,
              color: AppColors.cyan,
            ),
            label: Text(
              _showRenewalSection ? t('hide_renewal_options_label') : t('renew_extend_subscription_label'),
              style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.cyan, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        if (_showRenewalSection) _buildRenewalSection(),
      ],
    );
  }

  Widget _buildRenewalSection() {
    final t = AppLocalizations.of(context).t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('carry_over_renewal_message'),
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(t('select_a_plan_label'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        if (_isLoadingPlans)
          const Center(child: CircularProgressIndicator())
        else
          ..._plans.asMap().entries.map((e) => _buildPlanCard(e.value, e.key)),
        const SizedBox(height: 20),
        _razorpayTestHint,
        const SizedBox(height: 12),
        // Razorpay button
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: ElevatedButton.icon(
            onPressed: (_isProcessingPayment || _isPayingViaWallet) ? null : _startPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: _isProcessingPayment
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                : const Icon(Icons.payment, color: Colors.black),
            label: Text(
              _isProcessingPayment ? t('processing_ellipsis_label') : t('renew_via_razorpay_label'),
              style: const TextStyle(fontSize: 17, color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Expanded(child: Divider(thickness: 1.2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(t('or_label'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[500])),
          ),
          const Expanded(child: Divider(thickness: 1.2)),
        ]),
        const SizedBox(height: 14),
        // Wallet button
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cyan, width: 2),
          ),
          child: ElevatedButton.icon(
            onPressed: (_isProcessingPayment || _isPayingViaWallet) ? null : _payViaWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0F9FF),
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            icon: _isPayingViaWallet
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan))
                : const Icon(Icons.account_balance_wallet_rounded, color: AppColors.cyan),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPayingViaWallet ? t('processing_ellipsis_label') : t('renew_via_lenden_wallet_label'),
                  style: const TextStyle(fontSize: 17, color: AppColors.cyan, fontWeight: FontWeight.bold),
                ),
                if (!_isPayingViaWallet)
                  Text(t('balance_amount_message').replaceFirst('{amount}', _walletBalance.toStringAsFixed(2)), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 30),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(value, style: const TextStyle(color: Colors.black87)),
      ],
    );
  }

  Widget _buildSubscribeView() {
    final t = AppLocalizations.of(context).t;
    final showWarning =
        _displayCurrencyError != null || _hasMissingPlanConversion();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 60),

// Premium Illustration
        _buildPremiumIllustration(),

        // Benefits Section
        Text(
          t('premium_benefits_label'),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 15),
        if (_isLoadingBenefits)
          const Center(child: CircularProgressIndicator())
        else if (_benefits.isEmpty)
          Center(child: Text(t('loading_benefits_message')))
        else
          ..._benefits.asMap().entries.map((entry) {
            int idx = entry.key;
            PremiumBenefit benefit = entry.value;
            return _buildBenefitItem(idx, Icons.check, benefit.text, '');
          }).toList(),

        const SizedBox(height: 30),

        // Plan Comparison Toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t('select_a_plan_label'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showComparison = !_showComparison;
                });
              },
              icon: Icon(_showComparison ? Icons.grid_view : Icons.view_list),
              label: Text(_showComparison ? t('list_view_label') : t('compare_label')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              t('show_in_label'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
            ),
            const SizedBox(width: 10),
            _buildCurrencySelector(),
          ],
        ),
        if (showWarning) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFF6B6B)),
            ),
            child: Text(
              _displayCurrencyError ??
                  t('conversion_unavailable_subscription_message').replaceFirst('{currency}', _selectedDisplayCurrency),
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        const SizedBox(height: 15),

        // Plans Display
        _isLoadingPlans
            ? const Center(child: CircularProgressIndicator())
            : _plans.isEmpty
                ? Center(child: Text(t('loading_plans_message')))
                : _showComparison
                    ? _buildComparisonView()
                    : Column(
                        children: _plans.asMap().entries.map((entry) {
                          int idx = entry.key;
                          SubscriptionPlan plan = entry.value;
                          return _buildPlanCard(plan, idx);
                        }).toList(),
                      ),

        const SizedBox(height: 30),

        _razorpayTestHint,
        const SizedBox(height: 12),
        // Subscribe Button — Razorpay
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: (_isProcessingPayment || _isPayingViaWallet) ? null : _startPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            icon: _isProcessingPayment
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                : const Icon(Icons.payment, color: Colors.black),
            label: Text(
              _isProcessingPayment ? t('processing_ellipsis_label') : t('pay_via_razorpay_label'),
              style: const TextStyle(fontSize: 17, color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Divider OR
        Row(children: [
          const Expanded(child: Divider(thickness: 1.2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(t('or_label'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey[500])),
          ),
          const Expanded(child: Divider(thickness: 1.2)),
        ]),

        const SizedBox(height: 14),

        // Subscribe Button — LenDen Wallet
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cyan, width: 2),
          ),
          child: ElevatedButton.icon(
            onPressed: (_isProcessingPayment || _isPayingViaWallet) ? null : _payViaWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF0F9FF),
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            ),
            icon: _isPayingViaWallet
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan))
                : const Icon(Icons.account_balance_wallet_rounded, color: AppColors.cyan),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPayingViaWallet ? t('processing_ellipsis_label') : t('pay_via_lenden_wallet_label'),
                  style: const TextStyle(fontSize: 17, color: AppColors.cyan, fontWeight: FontWeight.bold),
                ),
                if (!_isPayingViaWallet)
                  Text(
                    t('balance_amount_message').replaceFirst('{amount}', _walletBalance.toStringAsFixed(2)),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Trust Badges
        _buildTrustBadges(),
      ],
    );
  }

  Widget _buildPremiumIllustration() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(seconds: 2),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF87CEEB), // Sky blue
                  Color(0xFFE0F6FF), // Light sky
                  Color(0xFFFFF8DC), // Cream (horizon)
                  Color(0xFFC8E6C9), // Light green (ground)
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.4, 0.7, 1.0],
              ),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Stack(
              children: [
                // Animated clouds
                Positioned(
                  left: 20 + (value * 10),
                  top: 20,
                  child: _buildCloud(30, 20),
                ),
                Positioned(
                  right: 30 - (value * 8),
                  top: 40,
                  child: _buildCloud(40, 25),
                ),
                Positioned(
                  left: MediaQuery.of(context).size.width * 0.3,
                  top: 15 + (value * 5),
                  child: _buildCloud(25, 15),
                ),

                // Animated parachute
                Transform.translate(
                  offset: Offset(0, -10 + (value * 10)),
                  child: Center(
                    child: CustomPaint(
                      size: Size(200, 280),
                      painter: EnhancedParachutePainter(animationValue: value),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCloud(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index) {
    final t = AppLocalizations.of(context).t;
    final isSelected = _selectedPlan == plan.name;
    final discountedPrice = plan.price * (1 - plan.discount / 100);
    // Mark the most popular plan: index 1 when 3+ plans, otherwise index 0
    final isPopular = _plans.length >= 3 ? index == 1 : (_plans.length == 2 ? index == 1 : index == 0);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = plan.name;
        });
      },
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? _getBenefitColor(index).withValues(alpha: 0.5)
                    : _getBenefitColor(index),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Radio<String>(
                        value: plan.name,
                        groupValue: _selectedPlan,
                        onChanged: (value) {
                          setState(() {
                            _selectedPlan = value;
                          });
                        },
                        activeColor: AppColors.cyan,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                if (plan.discount > 0)
                                  Text(
                                    _formatPlanAmount(plan.price),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                SizedBox(width: 8),
                                Text(
                                  _formatPlanAmount(discountedPrice),
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.cyan,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Text(
                              t('for_days_message').replaceFirst('{duration}', '${plan.duration}'),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                            if (plan.free > 0)
                              Row(
                                children: [
                                  Icon(Icons.star,
                                      color: Colors.orange, size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    t('free_days_message').replaceFirst('{count}', '${plan.free}'),
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  ...plan.features.map((feature) => Padding(
                        padding: const EdgeInsets.only(left: 50.0, bottom: 4.0),
                        child: Row(
                          children: [
                            Icon(Icons.check, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ),
          if (isPopular)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: Colors.white, size: 11),
                  const SizedBox(width: 3),
                  Text(t('most_popular_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ]),
              ),
            ),
          if (plan.discount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Text(
                  t('percent_off_message').replaceFirst('{discount}', '${plan.discount}'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComparisonView() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _plans.asMap().entries.map((entry) {
          int idx = entry.key;
          SubscriptionPlan plan = entry.value;
          final isSelected = _selectedPlan == plan.name;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPlan = plan.name;
              });
            },
            child: Container(
              width: 160,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [Colors.orange, Colors.white, Colors.green],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _getBenefitColor(idx).withValues(alpha: 0.5)
                      : _getBenefitColor(idx),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 12),
                    Text(
                      plan.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _formatPlanAmount(plan.price),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.cyan,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      t('for_days_message').replaceFirst('{duration}', '${plan.duration}'),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTrustBadges() {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBadge(Icons.security, t('secure_payment_label')),
          _buildBadge(Icons.support_agent, t('support_24_7_label')),
          _buildBadge(Icons.verified, t('money_back_guarantee_label')),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: AppColors.cyan, size: 30),
        SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildBenefitItem(
      int index, IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _getBenefitColor(index),
          borderRadius: BorderRadius.circular(15),
        ),
        child: ListTile(
          leading: Icon(icon, color: AppColors.cyan, size: 40),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
          subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(color: Colors.black87)) : null,
        ),
      ),
    );
  }

  Widget _buildFAQSection() {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: AppColors.cyan, size: 28),
              SizedBox(width: 10),
              Text(
                t('faqs_label'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
              ),
            ],
          ),
          SizedBox(height: 20),
          if (_isLoadingFaqs)
            const Center(child: CircularProgressIndicator())
          else if (_faqs.isEmpty)
            Center(child: Text(t('loading_faqs_message')))
          else
            ..._faqs.asMap().entries.map((entry) {
              int idx = entry.key;
              Faq faq = entry.value;
              return _buildFAQItem(faq.question, faq.answer, idx);
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer, int index) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _getBenefitColor(index),
          borderRadius: BorderRadius.circular(15),
        ),
        child: ExpansionTile(
          title: Text(
            question,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                answer,
                style: TextStyle(color: Colors.grey[700], fontSize: 13),
              ),
            ),
          ],
          tilePadding: EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.35);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.5,
        size.width * 0.5, size.height * 0.35);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.2, size.width, size.height * 0.35);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class EnhancedParachutePainter extends CustomPainter {
  final double animationValue;

  EnhancedParachutePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    final double centerX = size.width / 2;
    final double canopyTop = size.height * 0.1;
    final double canopyRadius = size.width * 0.35;

    // Draw umbrella-style parachute canopy with curve
    final int segments = 8;
    final double segmentAngle = 3.14159 / segments;

    // Draw curved parachute segments
    for (int i = 0; i < segments; i++) {
      Path segmentPath = Path();

      // Colors alternate between orange and dark blue
      if (i % 2 == 0) {
        paint.color = Colors.orange;
      } else {
        paint.color = Color(0xFF1E3A5F);
      }

      // Create curved segment
      double startAngle = 3.14159 + (i * segmentAngle);
      double endAngle = startAngle + segmentAngle;

      // Top arc
      segmentPath.moveTo(centerX, canopyTop);
      segmentPath.arcTo(
        Rect.fromCircle(
            center: Offset(centerX, canopyTop), radius: canopyRadius),
        startAngle,
        segmentAngle,
        false,
      );

      // Curved bottom (umbrella effect)
      double bottomCurveDepth = 15;
      double midX = centerX +
          canopyRadius * math.cos((startAngle + endAngle) / 2 - 3.14159);
      double midY = canopyTop +
          canopyRadius * math.sin((startAngle + endAngle) / 2 - 3.14159) +
          bottomCurveDepth;

      segmentPath.quadraticBezierTo(midX, midY + 10, centerX, canopyTop);

      canvas.drawPath(segmentPath, paint);
    }

    // Draw parachute outline with curve
    Paint outlinePaint = Paint()
      ..color = Color(0xFF1E3A5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    Path outlinePath = Path();
    outlinePath.moveTo(centerX - canopyRadius, canopyTop);

    // Curved umbrella outline
    for (int i = 0; i <= 20; i++) {
      double t = i / 20;
      double angle = 3.14159 + (t * 3.14159);
      double x = centerX + canopyRadius * math.cos(angle);
      double y = canopyTop + canopyRadius * math.sin(angle);

      // Add curve depth
      y += 15 * (0.5 - (t - 0.5).abs() * 2).abs();

      outlinePath.lineTo(x, y);
    }

    canvas.drawPath(outlinePath, outlinePaint);

    // Draw parachute strings
    Paint stringPaint = Paint()
      ..color = Colors.grey.shade600
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    double stringStartY = canopyTop + canopyRadius + 15;
    double boxTopY = size.height * 0.52;

    // Multiple strings with slight sway
    double sway = animationValue * 3;

    canvas.drawLine(
      Offset(centerX - canopyRadius * 0.85, stringStartY),
      Offset(centerX - size.width * 0.15 + sway, boxTopY),
      stringPaint,
    );

    canvas.drawLine(
      Offset(centerX - canopyRadius * 0.5, stringStartY - 10),
      Offset(centerX - size.width * 0.08 + sway, boxTopY),
      stringPaint,
    );

    canvas.drawLine(
      Offset(centerX + canopyRadius * 0.5, stringStartY - 10),
      Offset(centerX + size.width * 0.08 - sway, boxTopY),
      stringPaint,
    );

    canvas.drawLine(
      Offset(centerX + canopyRadius * 0.85, stringStartY),
      Offset(centerX + size.width * 0.15 - sway, boxTopY),
      stringPaint,
    );

    // Draw realistic gift box
    double boxWidth = size.width * 0.32;
    double boxHeight = size.height * 0.18;

    // Box shadow
    paint.color = Colors.black.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
            centerX - boxWidth / 2 + 3, boxTopY + 3, boxWidth, boxHeight),
        Radius.circular(8),
      ),
      paint,
    );

    // Main gift box (gradient effect)
    Path boxPath = Path();
    boxPath.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - boxWidth / 2, boxTopY, boxWidth, boxHeight),
        Radius.circular(8),
      ),
    );

    paint.shader = LinearGradient(
      colors: [Color(0xFFE53935), Color(0xFFC62828)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(
        Rect.fromLTWH(centerX - boxWidth / 2, boxTopY, boxWidth, boxHeight));

    canvas.drawPath(boxPath, paint);
    paint.shader = null;

    // Gold ribbon - vertical
    paint.color = Color(0xFFFFD700);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - boxWidth * 0.08, boxTopY - 8, boxWidth * 0.16,
            boxHeight + 16),
        Radius.circular(4),
      ),
      paint,
    );

    // Gold ribbon - horizontal
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - boxWidth / 2 - 8, boxTopY + boxHeight * 0.4,
            boxWidth + 16, boxHeight * 0.2),
        Radius.circular(4),
      ),
      paint,
    );

    // Ribbon shine effect
    paint.color = const Color(0xFFFFF59D).withValues(alpha: 0.5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(centerX - boxWidth * 0.04, boxTopY - 8, boxWidth * 0.08,
            boxHeight + 16),
        Radius.circular(2),
      ),
      paint,
    );

    // Draw decorative bow on top
    paint.color = Color(0xFFFFD700);

    // Left bow loop
    Path leftBow = Path();
    leftBow.moveTo(centerX - 8, boxTopY - 8);
    leftBow.quadraticBezierTo(
      centerX - 25,
      boxTopY - 25,
      centerX - 18,
      boxTopY - 12,
    );
    leftBow.quadraticBezierTo(
      centerX - 12,
      boxTopY - 8,
      centerX - 8,
      boxTopY - 8,
    );
    canvas.drawPath(leftBow, paint);

    // Right bow loop
    Path rightBow = Path();
    rightBow.moveTo(centerX + 8, boxTopY - 8);
    rightBow.quadraticBezierTo(
      centerX + 25,
      boxTopY - 25,
      centerX + 18,
      boxTopY - 12,
    );
    rightBow.quadraticBezierTo(
      centerX + 12,
      boxTopY - 8,
      centerX + 8,
      boxTopY - 8,
    );
    canvas.drawPath(rightBow, paint);

    // Bow center
    canvas.drawCircle(Offset(centerX, boxTopY - 8), 5, paint);

    // Add sparkles on box
    paint.color = Colors.white;
    canvas.drawCircle(Offset(centerX - 15, boxTopY + 15), 2, paint);
    canvas.drawCircle(Offset(centerX + 18, boxTopY + 25), 1.5, paint);
    canvas.drawCircle(
        Offset(centerX - 10, boxTopY + boxHeight - 10), 1.8, paint);

    // Draw people on ground
    double groundY = size.height * 0.85;

    // Person 1 (Male - left)
    _drawPerson(canvas, centerX - 60, groundY, Color(0xFF2196F3), true);

    // Person 2 (Female - right)
    _drawPerson(canvas, centerX + 50, groundY, Color(0xFFE91E63), false);

    // Draw ground line
    paint.color = Color(0xFF8BC34A);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawLine(
      Offset(0, groundY + 35),
      Offset(size.width, groundY + 35),
      paint,
    );

    // Add small grass elements
    for (int i = 0; i < 5; i++) {
      double x = (size.width / 6) * (i + 1);
      _drawGrass(canvas, x, groundY + 35);
    }
  }

  void _drawPerson(
      Canvas canvas, double x, double y, Color shirtColor, bool isMale) {
    Paint paint = Paint()..style = PaintingStyle.fill;

    // Head
    paint.color = Color(0xFFFFDBAC);
    canvas.drawCircle(Offset(x, y), 8, paint);

    // Hair
    paint.color = isMale ? Color(0xFF4A4A4A) : Color(0xFF8B4513);
    if (isMale) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x, y), radius: 8),
        3.14159,
        3.14159,
        true,
        paint,
      );
    } else {
      // Female with ponytail
      canvas.drawCircle(Offset(x, y - 8), 5, paint);
      canvas.drawCircle(Offset(x + 8, y - 6), 4, paint);
    }

    // Body (shirt)
    paint.color = shirtColor;
    Path body = Path();
    body.moveTo(x, y + 8);
    body.lineTo(x - 10, y + 25);
    body.lineTo(x + 10, y + 25);
    body.close();
    canvas.drawPath(body, paint);

    // Arms (waving)
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3;
    paint.strokeCap = StrokeCap.round;

    // Left arm
    canvas.drawLine(Offset(x - 8, y + 12), Offset(x - 15, y + 5), paint);

    // Right arm
    canvas.drawLine(Offset(x + 8, y + 12), Offset(x + 15, y + 5), paint);

    // Legs
    paint.color = Color(0xFF424242);
    canvas.drawLine(Offset(x - 5, y + 25), Offset(x - 5, y + 35), paint);
    canvas.drawLine(Offset(x + 5, y + 25), Offset(x + 5, y + 35), paint);

    // Add excited expression
    paint.style = PaintingStyle.fill;
    paint.color = Colors.black;
    canvas.drawCircle(Offset(x - 3, y - 2), 1.5, paint);
    canvas.drawCircle(Offset(x + 3, y - 2), 1.5, paint);

    // Smile
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    Path smile = Path();
    smile.moveTo(x - 3, y + 3);
    smile.quadraticBezierTo(x, y + 5, x + 3, y + 3);
    canvas.drawPath(smile, paint);
  }

  void _drawGrass(Canvas canvas, double x, double y) {
    Paint paint = Paint()
      ..color = Color(0xFF7CB342)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(x, y), Offset(x - 2, y - 5), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y - 6), paint);
    canvas.drawLine(Offset(x, y), Offset(x + 2, y - 5), paint);
  }

  @override
  bool shouldRepaint(EnhancedParachutePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
