import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/display_currency_helper.dart';
import '../../widgets/payment_success_page.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart' show MediumTopWaveClipper;
import '../support/help_support_page.dart';
import '../support/contact_page.dart';
import '../../utils/subscription_feature_catalog.dart';

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
  final List<String> allowedFeatures;

  SubscriptionPlan(
      {required this.id,
      required this.name,
      required this.price,
      required this.duration,
      required this.features,
      required this.isAvailable,
      required this.discount,
      required this.free,
      this.allowedFeatures = const []});

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
      allowedFeatures: List<String>.from(json['allowedFeatures'] ?? []),
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

class _SubscriptionsPageState extends State<SubscriptionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedPlan;
  String _searchQuery = '';
  String _planSearchQuery = '';
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
  String? _plansError;
  String? _benefitsError;
  String? _faqsError;
  bool _isPayingViaWallet = false;
  bool _showRenewalSection = false;
  double _walletBalance = 0;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _planSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    Provider.of<SessionProvider>(context, listen: false)
        .checkSubscriptionStatus();
    _loadDisplayCurrencies();
    _fetchSubscriptionData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _planSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSubscriptionData() async {
    await Future.wait([
      _fetchPlans(),
      _fetchBenefits(),
      _fetchFaqs(),
      _fetchWalletBalance(),
      _fetchPaymentConfig(),
    ]);
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final res = await ApiClient.get('/api/wallet/balance');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted)
          setState(() => _walletBalance = (data['balance'] ?? 0).toDouble());
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
    final canConvert =
        _displayCurrencyData?.canConvert('INR', targetCurrency) ??
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
    final symbol = _displayCurrencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? '₹' : targetCurrency);
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  Widget _buildCurrencySelector() {
    final currencies = _displayCurrencyData?.currencies ??
        const <Map<String, String>>[
          {'code': 'INR', 'symbol': '₹', 'label': ''},
        ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedDisplayCurrency,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppThemeColors.secondaryText(context)),
          borderRadius: BorderRadius.circular(14),
          dropdownColor: AppThemeColors.cardBg(context),
          items: currencies
              .map(
                (currency) => DropdownMenuItem<String>(
                  value: currency['code'],
                  child: Text(
                    '${currency['symbol']} ${currency['code']}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppThemeColors.primaryText(context)),
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
    );
  }

  Future<void> _fetchPlans() async {
    setState(() {
      _isLoadingPlans = true;
      _plansError = null;
    });
    try {
      final response = await ApiClient.get('/api/subscription/plans');
      if (!mounted) return;
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
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() => _plansError =
            (body?['message'] ?? t('failed_to_load_plans_message'))
                .toString());
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() => _plansError = '${t('error_prefix')} $e');
    } finally {
      if (mounted) setState(() => _isLoadingPlans = false);
    }
  }

  Future<void> _fetchBenefits() async {
    setState(() {
      _isLoadingBenefits = true;
      _benefitsError = null;
    });
    try {
      final response = await ApiClient.get('/api/subscription/benefits');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _benefits =
              data.map((item) => PremiumBenefit.fromJson(item)).toList();
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() => _benefitsError =
            (body?['message'] ?? t('failed_to_load_benefits_message'))
                .toString());
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() => _benefitsError = '${t('error_prefix')} $e');
    } finally {
      if (mounted) setState(() => _isLoadingBenefits = false);
    }
  }

  Future<void> _fetchFaqs() async {
    setState(() {
      _isLoadingFaqs = true;
      _faqsError = null;
    });
    try {
      final response = await ApiClient.get('/api/subscription/faqs');
      if (!mounted) return;
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _faqs = data.map((item) => Faq.fromJson(item)).toList();
        });
      } else {
        final t = AppLocalizations.of(context).t;
        final body =
            response.body.isNotEmpty ? json.decode(response.body) : null;
        setState(() => _faqsError =
            (body?['message'] ?? t('failed_to_load_faqs_message'))
                .toString());
      }
    } catch (e) {
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      setState(() => _faqsError = '${t('error_prefix')} $e');
    } finally {
      if (mounted) setState(() => _isLoadingFaqs = false);
    }
  }

  String? _razorpayPaymentLink;

  Future<void> _fetchPaymentConfig() async {
    try {
      final res = await ApiClient.get('/api/payment/config');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() => _razorpayPaymentLink = data['razorpayPaymentLink']);
        }
      }
    } catch (_) {}
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

    if (_razorpayPaymentLink == null) {
      showSnack(context, t('payment_config_unavailable_message'), isError: true);
      _fetchPaymentConfig();
      return;
    }

    final plan = _plans.firstWhere((p) => p.name == _selectedPlan);
    _showManualPaymentSheet(plan);
  }

  double _actualPriceFor(SubscriptionPlan plan) =>
      plan.price - (plan.price * (plan.discount / 100));

  Future<void> _openManualPaymentLink(double amount) async {
    if (_razorpayPaymentLink == null) return;
    // razorpay.me Payment Handle pages don't support an amount query param —
    // passing one breaks the page with a generic error, so the payer must
    // type the amount in themselves on Razorpay's page.
    final uri = Uri.parse(_razorpayPaymentLink!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showManualPaymentSheet(SubscriptionPlan plan) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    final actualPrice = _actualPriceFor(plan);
    final paymentIdController = TextEditingController();
    bool verifying = false;
    String? errorText;
    bool hasClickedPayNow = false;
    bool hasAttemptedVerify = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            bool canClose() => !hasClickedPayNow || hasAttemptedVerify;

            void tryClose() {
              if (canClose()) {
                Navigator.of(sheetContext).pop();
              } else {
                showSnack(
                    sheetContext, t('enter_payment_id_before_closing_message'),
                    isError: true);
              }
            }

            Future<void> verify() async {
              final paymentId = paymentIdController.text.trim();
              if (paymentId.isEmpty) {
                setSheetState(
                    () => errorText = t('please_enter_payment_id_message'));
                return;
              }
              setSheetState(() {
                verifying = true;
                hasAttemptedVerify = true;
                errorText = null;
              });
              try {
                final res =
                    await ApiClient.post('/api/payment/verify-manual', body: {
                  'paymentId': paymentId,
                  'planId': plan.id,
                });
                if (res.statusCode == 200) {
                  if (!mounted) return;
                  Navigator.of(sheetContext).pop();
                  final session =
                      Provider.of<SessionProvider>(context, listen: false);
                  await session.checkSubscriptionStatus();
                  await session.fetchSubscriptionHistory();
                  if (!mounted) return;
                  _showSuccessDialog();
                } else {
                  final err = jsonDecode(res.body);
                  setSheetState(() {
                    verifying = false;
                    errorText = err['error'] ??
                        t('payment_verification_failed_generic_message');
                  });
                }
              } catch (e) {
                setSheetState(() {
                  verifying = false;
                  errorText = '$e';
                });
              }
            }

            return PopScope(
              canPop: canClose(),
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  showSnack(sheetContext,
                      t('enter_payment_id_before_closing_message'),
                      isError: true);
                }
              },
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 20,
                  bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('pay_for_plan_label')
                                .replaceFirst('{plan}', plan.name),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color: AppThemeColors.secondaryText(context)),
                          onPressed: tryClose,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('amount_to_pay_colon_label').replaceFirst(
                          '{amount}', '₹${actualPrice.toStringAsFixed(2)}'),
                      style: TextStyle(
                          fontSize: 15,
                          color: AppThemeColors.secondaryText(context)),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
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
                              t('pay_exact_amount_warning_message')
                                  .replaceFirst('{amount}',
                                      '₹${actualPrice.toStringAsFixed(2)}'),
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
                              Text(
                                t('before_you_pay_label'),
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? const Color(0xFF64B5F6)
                                        : const Color(0xFF1565C0)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t('save_payment_id_and_receipt_message'),
                            style: TextStyle(
                                fontSize: 12.5,
                                color: isDark
                                    ? const Color(0xFF64B5F6)
                                    : const Color(0xFF1565C0)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        setSheetState(() => hasClickedPayNow = true);
                        _openManualPaymentLink(actualPrice);
                      },
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
                      controller: paymentIdController,
                      enabled: !verifying,
                      decoration: InputDecoration(
                        hintText: 'pay_XXXXXXXXXXXXXX',
                        errorText: errorText,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: verifying ? null : verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: verifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(t('verify_and_activate_label')),
                    ),
                    if (errorText != null && !verifying) ...[
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
                                      builder: (_) => HelpSupportPage())),
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
                                  MaterialPageRoute(
                                      builder: (_) => ContactPage())),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      showSnack(
          context,
          t('insufficient_wallet_balance_message')
              .replaceFirst('{needed}', actualPrice.toStringAsFixed(2))
              .replaceFirst('{available}', _walletBalance.toStringAsFixed(2)),
          isError: true);
      return;
    }
    setState(() => _isPayingViaWallet = true);
    try {
      final res = await ApiClient.post('/api/wallet/pay-subscription',
          body: {'planId': plan.id});
      if (!mounted) return;
      setState(() => _isPayingViaWallet = false);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() =>
            _walletBalance = (data['balance'] ?? _walletBalance).toDouble());
        await session.checkSubscriptionStatus();
        await session.fetchSubscriptionHistory();
        if (!mounted) return;
        _showSuccessDialog();
      } else {
        final err = json.decode(res.body);
        showSnack(context, err['error'] ?? t('wallet_payment_failed_message'),
            isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPayingViaWallet = false);
        showSnack(context, t('error_colon_label').replaceFirst('{error}', '$e'),
            isError: true);
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
      if (plan.discount > 0)
        planLabel = t('plan_with_discount_off_label')
            .replaceFirst('{plan}', plan.name)
            .replaceFirst('{discount}', '${plan.discount}');
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessPage(
          title: t('subscription_activated_label'),
          amount: planPrice,
          transactionType: t('subscription_em_dash_plan_label')
              .replaceFirst('{plan}', planLabel),
          extraDetails: {t('status_label'): t('premium_member_check_label')},
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  static const List<Color> _accentHues = [
    Color(0xFFFB8C00), // orange
    Color(0xFF43A047), // green
    Color(0xFFD81B60), // pink
    Color(0xFF1E88E5), // blue
    Color(0xFFF9A825), // amber
    Color(0xFF8E24AA), // purple
  ];

  Color _accentColor(int index) => _accentHues[index % _accentHues.length];

  List<SubscriptionPlan> _getFilteredPlans() {
    final query = _planSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _plans;
    final t = AppLocalizations.of(context).t;
    return _plans.where((plan) {
      final haystack = <String>[
        plan.name,
        plan.price.toStringAsFixed(2),
        '${plan.duration}',
        '${plan.discount}',
        '${plan.free}',
        ...plan.features,
        ...kSubscriptionFeatures
            .where((f) => plan.allowedFeatures.contains(f.key))
            .map((f) => t(f.labelKey)),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
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
    final isDark = AppThemeColors.isDark(context);
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(t('go_premium_label'),
            style: TextStyle(
                color: AppThemeColors.primaryText(context),
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.07),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                indicator: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(20),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.symmetric(vertical: 6),
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(20),
                labelColor: Colors.white,
                unselectedLabelColor: AppThemeColors.secondaryText(context),
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12.5),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 12.5),
                tabs: [
                  Tab(
                      text: t('plans_tab'),
                      icon: const Icon(Icons.card_membership_rounded,
                          size: 18)),
                  Tab(
                      text: t('benefits_tab'),
                      icon: const Icon(Icons.star_rounded, size: 18)),
                  Tab(
                      text: t('faqs_tab'),
                      icon: const Icon(Icons.help_outline_rounded, size: 18)),
                  Tab(
                      text: t('active_plan_tab'),
                      icon: const Icon(Icons.workspace_premium_rounded,
                          size: 18)),
                  Tab(
                      text: t('history_tab'),
                      icon: const Icon(Icons.history_rounded, size: 18)),
                ],
              ),
            ),
          ),
        ),
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
                  clipper: const MediumTopWaveClipper(),
                  child: Container(
                    height: context.sh(156),
                    color: AppThemeColors.waveSolid(context),
                  ),
                ),
              ),
              SafeArea(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPlansTab(session),
                    _buildBenefitsTab(),
                    _buildFaqsTab(),
                    _buildActivePlanTab(session),
                    _buildHistoryTab(session),
                  ],
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
    final isDark = AppThemeColors.isDark(context);
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
          style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppThemeColors.divider(context)),
          ),
          child: TextField(
            controller: _searchController,
            style:
                TextStyle(color: AppThemeColors.primaryText(context), fontSize: 14),
            decoration: InputDecoration(
              hintText: t('search_by_plan_name_hint'),
              hintStyle:
                  TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.cyan, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          size: 18, color: AppThemeColors.mutedText(context)),
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
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: ['All', 'Active', 'Expired'].map((filter) {
            final selected = _filterOption == filter;
            return ChoiceChip(
              label: Text(filterLabels[filter]!),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  _filterOption = filter;
                });
              },
              selectedColor: AppColors.cyan,
              backgroundColor: AppThemeColors.surfaceBg(context),
              side: BorderSide(
                  color: selected ? AppColors.cyan : AppThemeColors.divider(context)),
              labelStyle: TextStyle(
                color: selected ? Colors.white : AppThemeColors.secondaryText(context),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (itemsToShow.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                t('no_subscriptions_found_message'),
                style: TextStyle(color: AppThemeColors.mutedText(context)),
              ),
            ),
          )
        else
          ...itemsToShow.map((sub) {
            final endDate = DateTime.parse(sub['endDate']);
            final isActive =
                sub['status'] == 'active' && endDate.isAfter(DateTime.now());
            final paymentMethod =
                (sub['paymentMethod'] ?? 'razorpay').toString();
            final actualPrice =
                ((sub['actualPrice'] ?? sub['price'] ?? 0) as num).toDouble();
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

            final statusColor =
                isActive ? const Color(0xFF2E7D32) : AppThemeColors.mutedText(context);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppThemeColors.divider(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 5,
                        color:
                            isActive ? const Color(0xFF43A047) : AppThemeColors.divider(context),
                      ),
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isActive
                                    ? Icons.check_circle_rounded
                                    : Icons.history_rounded,
                                color: statusColor,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              sub['subscriptionPlan'] ?? '',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: AppThemeColors.primaryText(
                                                      context)),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              isActive
                                                  ? t('active_caps_label')
                                                  : t('expired_caps_label'),
                                              style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                  color: statusColor),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isActive
                                            ? t('active_until_message').replaceFirst(
                                                '{date}',
                                                endDate
                                                    .toLocal()
                                                    .toString()
                                                    .substring(0, 10))
                                            : t('expired_on_message').replaceFirst(
                                                '{date}',
                                                endDate
                                                    .toLocal()
                                                    .toString()
                                                    .substring(0, 10)),
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppThemeColors.secondaryText(context)),
                                      ),
                                      if (isActive) ...[
                                        const SizedBox(height: 4),
                                        Builder(builder: (_) {
                                          final daysLeft = endDate
                                              .difference(DateTime.now())
                                              .inDays;
                                          final hoursLeft = endDate
                                                  .difference(DateTime.now())
                                                  .inHours %
                                              24;
                                          final label = daysLeft > 0
                                              ? t('days_left_message')
                                                  .replaceFirst('{count}', '$daysLeft')
                                              : hoursLeft > 0
                                                  ? t('hours_left_message').replaceFirst(
                                                      '{count}', '$hoursLeft')
                                                  : t('expiring_soon_label');
                                          final color = daysLeft <= 3
                                              ? Colors.orange
                                              : AppColors.cyan;
                                          return Row(
                                            children: [
                                              Icon(Icons.timer_outlined,
                                                  size: 12, color: color),
                                              const SizedBox(width: 4),
                                              Text(
                                                label,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: color,
                                                ),
                                              ),
                                            ],
                                          );
                                        }),
                                      ],
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: pmColor.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: pmColor.withValues(alpha: 0.4),
                                                  width: 0.8),
                                            ),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(pmIcon, size: 10, color: pmColor),
                                                  const SizedBox(width: 3),
                                                  Text(pmLabel,
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: pmColor,
                                                          fontWeight: FontWeight.w600)),
                                                ]),
                                          ),
                                          if (actualPrice > 0)
                                            Text(
                                              '₹${actualPrice.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFFFF8000)),
                                            ),
                                          if (duration > 0)
                                            Text(
                                                t('duration_days_count_message')
                                                    .replaceFirst(
                                                        '{duration}', '$duration'),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppThemeColors.mutedText(
                                                        context))),
                                        ],
                                      ),
                                    ]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
              child: Text(
                  _showAllHistory ? t('show_less_label') : t('view_all_label'),
                  style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, size: 46, color: Colors.red[300]),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t('retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 58, color: AppThemeColors.mutedText(context)),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 6),
          Text(subtitle,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context))),
        ],
      ),
    );
  }

  Widget _buildPlansTab(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final showWarning =
        _displayCurrencyError != null || _hasMissingPlanConversion();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, context.sh(16), 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!session.isSubscribed) ...[
            _buildPremiumHero(),
            const SizedBox(height: 20),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t('select_a_plan_label'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context)),
              ),
              _buildViewToggle(),
            ],
          ),
          const SizedBox(height: 14),
          _buildPlanSearchField(),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.currency_exchange_rounded,
                  size: 16, color: AppThemeColors.secondaryText(context)),
              const SizedBox(width: 6),
              Text(
                t('show_in_label'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(context)),
              ),
              const SizedBox(width: 10),
              _buildCurrencySelector(),
            ],
          ),
          if (showWarning) ...[
            const SizedBox(height: 12),
            _buildWarningBanner(
              _displayCurrencyError ??
                  t('conversion_unavailable_subscription_message')
                      .replaceFirst('{currency}', _selectedDisplayCurrency),
            ),
          ],
          const SizedBox(height: 18),
          _isLoadingPlans
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()))
              : _plansError != null
                  ? _buildErrorState(_plansError!, _fetchPlans)
                  : _plans.isEmpty
                      ? _buildEmptyState(
                          t('nothing_here'), t('add_first_subscription_plan'))
                      : Builder(builder: (context) {
                          final filteredPlans = _getFilteredPlans();
                          if (filteredPlans.isEmpty) {
                            return _buildEmptyState(
                                t('nothing_here'), t('no_plans_match_search_message'));
                          }
                          return _showComparison
                              ? _buildComparisonView(filteredPlans)
                              : Column(
                                  children:
                                      filteredPlans.asMap().entries.map((entry) {
                                    int idx = entry.key;
                                    SubscriptionPlan plan = entry.value;
                                    return _buildPlanCard(plan, idx);
                                  }).toList(),
                                );
                        }),
          const SizedBox(height: 24),
          if (!session.isSubscribed) ...[
            _buildPaymentActions(
              razorpayLabel: t('pay_via_razorpay_label'),
              walletLabel: t('pay_via_lenden_wallet_label'),
              onRazorpay: _isPayingViaWallet ? null : _startPayment,
              onWallet: _isPayingViaWallet ? null : _payViaWallet,
            ),
            const SizedBox(height: 20),
            _buildTrustBadges(),
          ] else
            _buildAlreadySubscribedCard(),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppThemeColors.surfaceBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleIconButton(Icons.view_agenda_rounded, !_showComparison,
              () => setState(() => _showComparison = false)),
          _toggleIconButton(Icons.view_column_rounded, _showComparison,
              () => setState(() => _showComparison = true)),
        ],
      ),
    );
  }

  Widget _toggleIconButton(IconData icon, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon,
            size: 18,
            color: selected ? Colors.white : AppThemeColors.secondaryText(context)),
      ),
    );
  }

  Widget _buildPlanSearchField() {
    final t = AppLocalizations.of(context).t;
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: TextField(
        controller: _planSearchController,
        style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 14),
        decoration: InputDecoration(
          hintText: t('search_plans_hint'),
          hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.cyan, size: 20),
          suffixIcon: _planSearchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded,
                      size: 18, color: AppThemeColors.mutedText(context)),
                  onPressed: () {
                    setState(() {
                      _planSearchController.clear();
                      _planSearchQuery = '';
                    });
                  },
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _planSearchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildWarningBanner(String message) {
    final isDark = AppThemeColors.isDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A1F1F) : const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6B6B).withValues(alpha: isDark ? 0.5 : 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFE53935), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: Color(0xFFE57373), fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentActions({
    required String razorpayLabel,
    required String walletLabel,
    required VoidCallback? onRazorpay,
    required VoidCallback? onWallet,
  }) {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.cyan, AppColors.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: onRazorpay,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.payment_rounded, color: Colors.white),
            label: Text(
              razorpayLabel,
              style: const TextStyle(
                  fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: Divider(thickness: 1, color: AppThemeColors.divider(context))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(t('or_label'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.mutedText(context))),
          ),
          Expanded(child: Divider(thickness: 1, color: AppThemeColors.divider(context))),
        ]),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cyan, width: 1.5),
          ),
          child: ElevatedButton.icon(
            onPressed: onWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: _isPayingViaWallet
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan))
                : const Icon(Icons.account_balance_wallet_rounded, color: AppColors.cyan),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPayingViaWallet ? t('processing_ellipsis_label') : walletLabel,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.cyan, fontWeight: FontWeight.bold),
                ),
                if (!_isPayingViaWallet)
                  Text(
                    t('balance_amount_message')
                        .replaceFirst('{amount}', _walletBalance.toStringAsFixed(2)),
                    style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlreadySubscribedCard() {
    final t = AppLocalizations.of(context).t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF0F9FF), dark: const Color(0xFF11303D)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.cyan, size: 32),
          const SizedBox(height: 10),
          Text(
            t('already_subscribed_browse_plans_message'),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13.5),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _tabController.animateTo(3),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.cyan,
              side: const BorderSide(color: AppColors.cyan),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            label: Text(t('go_to_other_details_label')),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitsTab() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, context.sh(16), 16, 20),
      child: _isLoadingBenefits
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()))
          : _benefitsError != null
              ? _buildErrorState(_benefitsError!, _fetchBenefits)
              : _benefits.isEmpty
                  ? _buildEmptyState(
                      t('nothing_here'), t('no_benefits_listed_message'))
                  : Column(
                      children: _benefits.asMap().entries.map((entry) {
                        return _buildBenefitItem(entry.key, entry.value.text);
                      }).toList(),
                    ),
    );
  }

  Widget _buildFaqsTab() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, context.sh(16), 16, 20),
      child: _isLoadingFaqs
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()))
          : _faqsError != null
              ? _buildErrorState(_faqsError!, _fetchFaqs)
              : _faqs.isEmpty
                  ? _buildEmptyState(t('nothing_here'), t('no_faqs_listed_message'))
                  : Column(
                      children: _faqs.asMap().entries.map((entry) {
                        return _buildFAQItem(
                            entry.value.question, entry.value.answer, entry.key);
                      }).toList(),
                    ),
    );
  }

  Widget _buildActivePlanTab(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    final daysRemaining = session.subscriptionEndDate != null
        ? session.subscriptionEndDate!.difference(DateTime.now()).inDays
        : 0;
    final freeDaysRemaining =
        session.free != null && session.subscriptionEndDate != null
            ? session.free! -
                (DateTime.now().difference(session.subscriptionEndDate!).inDays)
            : 0;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, context.sh(16), 16, 20),
      child: Column(
        children: [
          if (!session.isSubscribed)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      size: 72, color: AppThemeColors.divider(context)),
                  const SizedBox(height: 16),
                  Text(t('not_subscribed_yet_message'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _tabController.animateTo(0),
                    icon: const Icon(Icons.card_membership_rounded),
                    label: Text(t('view_plans_label')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          if (session.isSubscribed) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.cyan, AppColors.blue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.celebration_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        t('premium_member_label'),
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard(
                            Icons.calendar_today_rounded,
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
                        const SizedBox(width: 16),
                        _buildStatCard(
                            Icons.workspace_premium_rounded,
                            session.subscriptionPlan?.split(' ')[0] ?? t('na_label'),
                            t('plan_label')),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppThemeColors.divider(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: AppColors.cyan, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        t('subscription_details_label'),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow(t('plan_colon_label'),
                      session.subscriptionPlan ?? t('na_label')),
                  const SizedBox(height: 10),
                  Divider(color: AppThemeColors.divider(context), height: 1),
                  const SizedBox(height: 10),
                  _buildInfoRow(
                      t('expires_on_colon_label'),
                      session.subscriptionEndDate
                              ?.toLocal()
                              .toString()
                              .split(' ')[0] ??
                          t('na_label')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _showRenewalSection = !_showRenewalSection),
                icon: Icon(
                  _showRenewalSection
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.refresh_rounded,
                  color: AppColors.cyan,
                ),
                label: Text(
                  _showRenewalSection
                      ? t('hide_renewal_options_label')
                      : t('renew_extend_subscription_label'),
                  style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.cyan, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            if (_showRenewalSection) _buildRenewalSection(),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 16),
          _buildTrustBadges(),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final history = session.subscriptionHistory;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, context.sh(16), 16, 20),
      child: history != null && history.isNotEmpty
          ? _buildSubscriptionHistory(history)
          : Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Column(
                children: [
                  Icon(Icons.history_rounded,
                      size: 72, color: AppThemeColors.divider(context)),
                  const SizedBox(height: 16),
                  Text(t('no_subscription_history_yet_message'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 15,
                          color: AppThemeColors.secondaryText(context))),
                ],
              ),
            ),
    );
  }

  Widget _buildRenewalSection() {
    final t = AppLocalizations.of(context).t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFE8F5E9), dark: const Color(0xFF1B3A26)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                t('carry_over_renewal_message'),
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 18),
        Text(t('select_a_plan_label'),
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 12),
        if (_isLoadingPlans)
          const Center(child: CircularProgressIndicator())
        else
          ..._plans.asMap().entries.map((e) => _buildPlanCard(e.value, e.key)),
        const SizedBox(height: 18),
        _buildPaymentActions(
          razorpayLabel: t('renew_via_razorpay_label'),
          walletLabel: t('renew_via_lenden_wallet_label'),
          onRazorpay: _isPayingViaWallet ? null : _startPayment,
          onWallet: _isPayingViaWallet ? null : _payViaWallet,
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
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
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppThemeColors.secondaryText(context))),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
                color: AppThemeColors.primaryText(context))),
      ],
    );
  }

  Widget _buildPremiumHero() {
    final t = AppLocalizations.of(context).t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.cyan, AppColors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(t('unlock_premium_title'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(t('unlock_premium_subtitle'),
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSubscriptionFeatures.take(4).map((f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(f.icon, size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(t(f.labelKey),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    final isSelected = _selectedPlan == plan.name;
    final discountedPrice = plan.price * (1 - plan.discount / 100);
    // Mark the most popular plan: index 1 when 3+ plans, otherwise index 0
    final isPopular = _plans.length >= 3
        ? index == 1
        : (_plans.length == 2 ? index == 1 : index == 0);
    final accent = _accentColor(index);
    final hasRibbon = isPopular || plan.discount > 0;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = plan.name;
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.cyan.withValues(alpha: isDark ? 0.16 : 0.07)
              : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.cyan : AppThemeColors.divider(context),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, hasRibbon ? 26 : 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? AppColors.cyan
                              : accent.withValues(alpha: isDark ? 0.22 : 0.14),
                        ),
                        child: Icon(
                          isSelected ? Icons.check_rounded : Icons.workspace_premium_rounded,
                          size: 15,
                          color: isSelected ? Colors.white : accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan.name,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              children: [
                                Text(
                                  _formatPlanAmount(discountedPrice),
                                  style: const TextStyle(
                                    fontSize: 23,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.cyan,
                                  ),
                                ),
                                if (plan.discount > 0)
                                  Text(
                                    _formatPlanAmount(plan.price),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppThemeColors.mutedText(context),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                Text(
                                  t('for_days_message')
                                      .replaceFirst('{duration}', '${plan.duration}'),
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppThemeColors.secondaryText(context),
                                  ),
                                ),
                              ],
                            ),
                            if (plan.free > 0) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.celebration_rounded,
                                      color: Colors.orange, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    t('free_days_message')
                                        .replaceFirst('{count}', '${plan.free}'),
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (plan.features.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.only(left: 38),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: plan.features
                            .map((feature) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.check_rounded,
                                          color: AppColors.cyan, size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          feature,
                                          style: TextStyle(
                                            color: AppThemeColors.secondaryText(context),
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                  if (plan.allowedFeatures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(left: 38),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: kSubscriptionFeatures
                            .where((f) => plan.allowedFeatures.contains(f.key))
                            .map((f) => Container(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan.withValues(alpha: isDark ? 0.18 : 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(f.icon, size: 11, color: AppColors.cyan),
                                    const SizedBox(width: 4),
                                    Text(t(f.labelKey),
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.cyan,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isPopular)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: const BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomRight: Radius.circular(14),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded, color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Text(t('most_popular_label'),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  ]),
                ),
              ),
            if (plan.discount > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                  child: Text(
                    t('percent_off_message').replaceFirst('{discount}', '${plan.discount}'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonView(List<SubscriptionPlan> plans) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: plans.asMap().entries.map((entry) {
          final idx = entry.key;
          final plan = entry.value;
          final isSelected = _selectedPlan == plan.name;
          final accent = _accentColor(idx);

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedPlan = plan.name;
              });
            },
            child: Container(
              width: 168,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.cyan.withValues(alpha: isDark ? 0.16 : 0.07)
                    : AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? AppColors.cyan : AppThemeColors.divider(context),
                  width: isSelected ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withValues(alpha: isDark ? 0.22 : 0.14)),
                    child: Icon(Icons.workspace_premium_rounded, size: 16, color: accent),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    plan.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatPlanAmount(plan.price * (1 - plan.discount / 100)),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('for_days_message').replaceFirst('{duration}', '${plan.duration}'),
                    style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      fontSize: 11.5,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 10),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.cyan, size: 14),
                      const SizedBox(width: 4),
                      Text(t('selected_label'),
                          style: const TextStyle(
                              color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ],
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBadge(Icons.security_rounded, t('secure_payment_label')),
          _buildBadge(Icons.support_agent_rounded, t('support_24_7_label')),
          _buildBadge(Icons.verified_rounded, t('money_back_guarantee_label')),
        ],
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: AppColors.cyan, size: 28),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppThemeColors.secondaryText(context)),
        ),
      ],
    );
  }

  Widget _buildBenefitItem(int index, String text) {
    final accent = _accentColor(index);
    final isDark = AppThemeColors.isDark(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.divider(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: accent.withValues(alpha: isDark ? 0.22 : 0.14)),
          child: Icon(Icons.check_rounded, color: accent, size: 19),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.primaryText(context))),
        ),
      ]),
    );
  }

  Widget _buildFAQItem(String question, String answer, int index) {
    final isDark = AppThemeColors.isDark(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.divider(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.cyan.withValues(alpha: isDark ? 0.2 : 0.12)),
            child: const Icon(Icons.question_mark_rounded, color: AppColors.cyan, size: 16),
          ),
          title: Text(
            question,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                color: AppThemeColors.primaryText(context)),
          ),
          iconColor: AppColors.cyan,
          collapsedIconColor: AppThemeColors.secondaryText(context),
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              child: Text(
                answer,
                style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
