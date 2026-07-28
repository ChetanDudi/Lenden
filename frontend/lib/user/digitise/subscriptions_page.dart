import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/currency_display.dart';
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
    with SingleTickerProviderStateMixin, CurrencyDisplayMixin<SubscriptionsPage> {
  late TabController _tabController;

  String? _selectedPlan;
  String _searchQuery = '';
  String _planSearchQuery = '';
  String _filterOption = 'All'; // All, Active, Expired
  bool _showComparison = false;
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
  bool _heroExpanded = false;
  bool _isPayingViaWallet = false;
  bool _isTogglingAutoRenew = false;
  bool _showRenewalSection = false;
  double _walletBalance = 0;

  // Tracks which subscription cards have their admin-event timeline expanded
  final Set<String> _expandedHistoryIds = {};

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _planSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    final session = Provider.of<SessionProvider>(context, listen: false);
    session.checkSubscriptionStatus();
    session.fetchSubscriptionHistory();
    loadCurrencies(onError: (_) {
      if (mounted) setState(() => _displayCurrencyError = AppLocalizations.of(context).t('currency_conversion_unavailable_message'));
    });
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

  bool _hasMissingPlanConversion() {
    if (selectedCurrency.toUpperCase() == 'INR') return false;
    if (currencyData == null) return true;
    return !currencyData!.canConvert('INR', selectedCurrency);
  }

  String _formatPlanAmount(double amountInInr) {
    final targetCurrency = selectedCurrency.toUpperCase();
    final canConvert =
        currencyData?.canConvert('INR', targetCurrency) ??
            (targetCurrency == 'INR');
    if (!canConvert) {
      return '₹${amountInInr.toStringAsFixed(2)}';
    }
    final converted = currencyData?.convert(
          amountInInr,
          'INR',
          targetCurrency,
        ) ??
        amountInInr;
    final symbol = currencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? '₹' : targetCurrency);
    return '$symbol${converted.toStringAsFixed(2)}';
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
      final isAdminDeactivated = sub['adminDeactivated'] == true;
      final isBridgingPaused = !isAdminDeactivated && sub['status'] == 'paused' && sub['pausedByBridging'] == true;
      if (_filterOption == 'Active') {
        final endDate = DateTime.parse(sub['endDate']);
        // Admin-paused and bridging-paused subs count as "active" — they have remaining days.
        matchesFilter = isAdminDeactivated || isBridgingPaused ||
            (sub['status'] == 'active' && endDate.isAfter(DateTime.now()));
      } else if (_filterOption == 'Expired') {
        final endDate = DateTime.parse(sub['endDate']);
        // Exclude admin-paused and bridging-paused from 'Expired'.
        matchesFilter = !isAdminDeactivated && !isBridgingPaused &&
            (sub['status'] == 'expired' || endDate.isBefore(DateTime.now()));
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

  String _fmtEventTime(DateTime dt) =>
      DateFormat('MMM d, yyyy h:mm a').format(dt.toLocal());

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
            final subId = sub['_id']?.toString() ?? '';
            final endDate = DateTime.parse(sub['endDate']);
            final adminDeactivated = sub['adminDeactivated'] == true;
            final isPausedBridging = !adminDeactivated && sub['status'] == 'paused' && sub['pausedByBridging'] == true;
            final isActive =
                !adminDeactivated && !isPausedBridging && sub['status'] == 'active' && endDate.isAfter(DateTime.now());
            final isExpired = !adminDeactivated && !isPausedBridging && !isActive;
            final deactivationReason = sub['deactivationReason']?.toString();
            // Build ordered event list merging all sources:
            //  • adminEvents array  — set by new code, one entry per cycle
            //  • deactivatedAt / reactivatedAt — old single fields; must be
            //    included when they represent events that predate the array
            final List<Map<String, dynamic>> adminEvents = () {
              final raw = sub['adminEvents'];
              final newEvents = (raw is List && raw.isNotEmpty)
                  ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
                  : <Map<String, dynamic>>[];

              if (newEvents.isEmpty) {
                // Pure old-code path: synthesize both old fields
                final synth = <Map<String, dynamic>>[];
                if (sub['deactivatedAt'] != null) {
                  synth.add({'type': 'deactivated', 'at': sub['deactivatedAt'], 'reason': sub['deactivationReason']});
                }
                if (sub['reactivatedAt'] != null) {
                  synth.add({'type': 'reactivated', 'at': sub['reactivatedAt'], 'reason': null});
                }
                synth.sort((a, b) => (a['at']?.toString() ?? '').compareTo(b['at']?.toString() ?? ''));
                return synth;
              }

              // Mixed path: adminEvents has new entries, but reactivatedAt may
              // hold an old-code reactivation that predates the array.
              final combined = List<Map<String, dynamic>>.from(newEvents);
              if (sub['reactivatedAt'] != null) {
                final oldReact = DateTime.tryParse(sub['reactivatedAt'].toString());
                final earliest = newEvents
                    .map((e) => DateTime.tryParse(e['at']?.toString() ?? ''))
                    .whereType<DateTime>()
                    .fold<DateTime?>(null, (acc, dt) =>
                        acc == null || dt.isBefore(acc) ? dt : acc);
                if (oldReact != null &&
                    (earliest == null || oldReact.isBefore(earliest))) {
                  combined.add({'type': 'reactivated', 'at': sub['reactivatedAt'], 'reason': null});
                }
              }
              combined.sort((a, b) => (a['at']?.toString() ?? '').compareTo(b['at']?.toString() ?? ''));
              return combined;
            }();
            final hasTimeline = adminDeactivated || adminEvents.isNotEmpty;
            final planName = (sub['subscriptionPlan'] ?? '').toString();
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

            final statusColor = adminDeactivated
                ? Colors.orange
                : isPausedBridging
                    ? Colors.deepPurple
                    : isActive
                        ? const Color(0xFF2E7D32)
                        : AppThemeColors.mutedText(context);

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
                        color: adminDeactivated
                            ? Colors.orange
                            : isPausedBridging
                                ? Colors.deepPurple
                                : isActive
                                    ? const Color(0xFF43A047)
                                    : AppThemeColors.divider(context),
                      ),
                      Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                adminDeactivated
                                    ? Icons.pause_circle_filled_rounded
                                    : isPausedBridging
                                        ? Icons.hourglass_top_rounded
                                        : isActive
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
                                              adminDeactivated
                                                  ? t('subscription_paused_label').toUpperCase()
                                                  : isPausedBridging
                                                      ? 'QUEUED'
                                                      : isActive
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
                                        adminDeactivated
                                            ? t('subscription_admin_paused_days_label')
                                                .replaceFirst('{days}',
                                                    '${((sub['deactivatedAt'] != null && sub['endDate'] != null) ? (DateTime.tryParse(sub['endDate'].toString())?.difference(DateTime.tryParse(sub['deactivatedAt'].toString()) ?? DateTime.now()).inDays ?? 0).clamp(0, 99999) : 0)}')
                                            : isPausedBridging
                                                ? 'Queued — resumes automatically (${sub['pausedRemainingDays'] ?? 0} days remaining)'
                                                : isActive
                                                    ? t('active_until_message').replaceFirst(
                                                        '{date}',
                                                        endDate.toLocal().toString().substring(0, 10))
                                                    : t('expired_on_message').replaceFirst(
                                                        '{date}',
                                                        endDate.toLocal().toString().substring(0, 10)),
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: adminDeactivated
                                                ? Colors.orange[700]
                                                : isPausedBridging
                                                    ? Colors.deepPurple[400]
                                                    : AppThemeColors.secondaryText(context)),
                                      ),
                                      if (adminDeactivated && deactivationReason != null && deactivationReason.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.info_outline_rounded,
                                                size: 11, color: Colors.orange[600]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${t('subscription_admin_paused_reason_label')}: $deactivationReason',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.orange[700],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
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
                                      // Admin-event timeline — collapsed by default,
                                      // expanded per-card when user taps the toggle.
                                      if (hasTimeline) ...[
                                        const SizedBox(height: 6),
                                        Divider(
                                            color: AppThemeColors.divider(context),
                                            height: 1,
                                            thickness: 0.8),
                                        GestureDetector(
                                          onTap: () => setState(() {
                                            if (_expandedHistoryIds.contains(subId)) {
                                              _expandedHistoryIds.remove(subId);
                                            } else {
                                              _expandedHistoryIds.add(subId);
                                            }
                                          }),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                            child: Row(
                                              children: [
                                                Icon(Icons.history_rounded,
                                                    size: 13,
                                                    color: AppColors.cyan),
                                                const SizedBox(width: 5),
                                                Text(
                                                  _expandedHistoryIds.contains(subId)
                                                      ? t('hide_admin_history_label')
                                                      : '${t('view_admin_history_label')} (${adminEvents.isEmpty ? 1 : adminEvents.length})',
                                                  style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: AppColors.cyan),
                                                ),
                                                const Spacer(),
                                                Icon(
                                                  _expandedHistoryIds.contains(subId)
                                                      ? Icons.keyboard_arrow_up_rounded
                                                      : Icons.keyboard_arrow_down_rounded,
                                                  size: 16,
                                                  color: AppColors.cyan,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (_expandedHistoryIds.contains(subId)) ...[
                                          if (adminEvents.isEmpty && adminDeactivated)
                                            Row(
                                              children: [
                                                Icon(Icons.pause_circle_outline_rounded,
                                                    size: 13, color: Colors.orange[600]),
                                                const SizedBox(width: 5),
                                                Text(
                                                  t('subscription_paused_label'),
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.orange[700]),
                                                ),
                                              ],
                                            ),
                                          ...adminEvents.asMap().entries.map((entry) {
                                            final idx = entry.key;
                                            final event = entry.value;
                                            final isPause = event['type'] == 'deactivated';
                                            final at = event['at'] != null
                                                ? DateTime.tryParse(event['at'].toString())
                                                : null;
                                            final evReason = event['reason']?.toString();
                                            return Padding(
                                              padding: EdgeInsets.only(top: idx == 0 ? 0 : 5),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    isPause
                                                        ? Icons.pause_circle_outline_rounded
                                                        : Icons.play_circle_outline_rounded,
                                                    size: 13,
                                                    color: isPause
                                                        ? Colors.orange[600]
                                                        : Colors.green[600],
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          '${t(isPause ? 'event_paused_on_label' : 'event_reactivated_on_label')}: ${at != null ? _fmtEventTime(at) : '—'}',
                                                          style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w600,
                                                              color: isPause
                                                                  ? Colors.orange[700]
                                                                  : Colors.green[700]),
                                                        ),
                                                        if (isPause &&
                                                            evReason != null &&
                                                            evReason.isNotEmpty)
                                                          Text(
                                                            evReason,
                                                            style: TextStyle(
                                                                fontSize: 10.5,
                                                                fontStyle: FontStyle.italic,
                                                                color: Colors.orange[600]),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 4),
                                        ],
                                      ],
                                      // Renew button for expired plans
                                      if (isExpired) ...[
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            icon: const Icon(
                                                Icons.refresh_rounded,
                                                size: 15),
                                            label: Text(t('renew_this_plan_label'),
                                                style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.bold)),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppColors.cyan,
                                              side: const BorderSide(
                                                  color: AppColors.cyan, width: 1.2),
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 8),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10)),
                                            ),
                                            onPressed: () {
                                              final matchedPlan = _plans
                                                  .where((p) => p.name == planName)
                                                  .isNotEmpty
                                                  ? _plans.firstWhere(
                                                      (p) => p.name == planName)
                                                  : null;
                                              if (matchedPlan != null) {
                                                setState(() =>
                                                    _selectedPlan = matchedPlan.name);
                                                _showManualPaymentSheet(matchedPlan);
                                              } else {
                                                _tabController.animateTo(0);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
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
              buildCurrencySelector(),
            ],
          ),
          if (showWarning) ...[
            const SizedBox(height: 12),
            _buildWarningBanner(
              _displayCurrencyError ??
                  t('conversion_unavailable_subscription_message')
                      .replaceFirst('{currency}', selectedCurrency),
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
        // Primary: LenDen Wallet (gradient)
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
            onPressed: onWallet,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: _isPayingViaWallet
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.account_balance_wallet_rounded, color: Colors.white),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isPayingViaWallet ? t('processing_ellipsis_label') : walletLabel,
                  style: const TextStyle(
                      fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                if (!_isPayingViaWallet)
                  Text(
                    t('balance_amount_message')
                        .replaceFirst('{amount}', _walletBalance.toStringAsFixed(2)),
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
              ],
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
        // Secondary: Razorpay (outlined)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cyan, width: 1.5),
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
            icon: const Icon(Icons.payment_rounded, color: AppColors.cyan),
            label: Text(
              razorpayLabel,
              style: const TextStyle(
                  fontSize: 16, color: AppColors.cyan, fontWeight: FontWeight.bold),
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
              padding: const EdgeInsets.only(top: 32),
              child: Column(
                children: [
                  if (session.subscriptionAdminDeactivated) ...[
                    _buildAdminDeactivatedBanner(session, t),
                    const SizedBox(height: 28),
                  ],
                  if (!session.subscriptionAdminDeactivated) ...[
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
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
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
            if (daysRemaining >= 0 && daysRemaining <= 3) ...[
              const SizedBox(height: 16),
              _buildExpiringSoonBanner(session, daysRemaining),
            ],
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
            _buildAutoRenewCard(session),
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

  Widget _buildAdminDeactivatedBanner(SessionProvider session, String Function(String) t) {
    final isDark = AppThemeColors.isDark(context);
    final reason = session.subscriptionDeactivationReason;
    final days = session.subscriptionRemainingDays ?? 0;
    final plan = session.subscriptionPlan;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A2000) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: isDark ? 0.6 : 1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: isDark ? 0.1 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_filled_rounded,
                  color: isDark ? Colors.orange[300] : Colors.orange[800], size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t('subscription_admin_paused_title'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.orange[300] : Colors.orange[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t('subscription_admin_paused_body'),
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.orange[200] : Colors.orange[900],
            ),
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 15, color: isDark ? Colors.orange[300] : Colors.orange[800]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '${t('subscription_admin_paused_reason_label')}: ',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.orange[300] : Colors.orange[900],
                            ),
                          ),
                          TextSpan(
                            text: reason,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? Colors.orange[200] : Colors.orange[800],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (days > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 14, color: isDark ? Colors.orange[300] : Colors.orange[800]),
                const SizedBox(width: 6),
                Text(
                  t('subscription_admin_paused_days_label').replaceFirst('{days}', '$days'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.orange[300] : Colors.orange[800],
                  ),
                ),
              ],
            ),
          ],
          if (plan != null && plan.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.card_membership_rounded,
                    size: 14, color: isDark ? Colors.orange[300] : Colors.orange[800]),
                const SizedBox(width: 6),
                Text(
                  plan,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.orange[200] : Colors.orange[700],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(color: Colors.orange.withValues(alpha: 0.3), height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.support_agent_rounded,
                  size: 14, color: isDark ? Colors.orange[400] : Colors.orange[700]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  t('subscription_admin_paused_contact'),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.orange[400] : Colors.orange[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpiringSoonBanner(SessionProvider session, int daysRemaining) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    final message = session.autoRenew
        ? (daysRemaining == 0
            ? t('expiring_today_auto_renew_message')
            : t('expiring_soon_auto_renew_message').replaceFirst('{days}', '$daysRemaining'))
        : (daysRemaining == 0
            ? t('expiring_today_message')
            : t('expiring_soon_message').replaceFirst('{days}', '$daysRemaining'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFFFF8E1), dark: const Color(0xFF3A2F12)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: isDark ? 0.5 : 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_bottom_rounded,
              color: isDark ? const Color(0xFFFFD54F) : Colors.orange[800], size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFFFD54F) : Colors.orange[900]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoRenewCard(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final isDark = AppThemeColors.isDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.cyan.withValues(alpha: isDark ? 0.22 : 0.12)),
            child: const Icon(Icons.autorenew_rounded, color: AppColors.cyan, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('auto_renew_label'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 2),
                Text(t('auto_renew_description'),
                    style: TextStyle(fontSize: 11.5, color: AppThemeColors.secondaryText(context))),
              ],
            ),
          ),
          _isTogglingAutoRenew
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.cyan))
              : Switch(
                  value: session.autoRenew,
                  activeColor: AppColors.cyan,
                  onChanged: (value) async {
                    setState(() => _isTogglingAutoRenew = true);
                    final ok = await session.setAutoRenew(value);
                    if (!mounted) return;
                    setState(() => _isTogglingAutoRenew = false);
                    if (ok) {
                      showSnack(
                          context,
                          value
                              ? t('auto_renew_enabled_message')
                              : t('auto_renew_disabled_message'));
                    } else {
                      showSnack(context, t('failed_to_update_auto_renew_message'), isError: true);
                    }
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(SessionProvider session) {
    final t = AppLocalizations.of(context).t;
    final history = session.subscriptionHistory;
    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: () async {
        await Future.wait([
          session.checkSubscriptionStatus(),
          session.fetchSubscriptionHistory(),
        ]);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
    const featureColors = {
      'quick_transactions':  Color(0xFFFFA000),
      'secure_transactions': Color(0xFF00897B),
      'group_creation':      Color(0xFF1E88E5),
      'group_expenses':      Color(0xFFE53935),
      'private_chat':        Color(0xFF8E24AA),
      'group_chat':          Color(0xFF3949AB),
      'discover':            Color(0xFF00ACC1),
      'view_rankings':       Color(0xFF43A047),
      'reports':             Color(0xFFD81B60),
      'budget_planning':     Color(0xFF6D4C41),
      'smart_insights':      Color(0xFF5E35B1),
    };
    final visible = _heroExpanded ? kSubscriptionFeatures : kSubscriptionFeatures.take(4).toList();
    final remaining = kSubscriptionFeatures.length - 4;

    final isDark = AppThemeColors.isDark(context);
    final cardBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white70 : Colors.black54;

    Widget featureTile(f) {
      final color = featureColors[f.key] ?? AppColors.cyan;
      final label = t(f.labelKey).split(' ').take(2).join('\n');
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(f.icon, size: 24, color: color),
        ),
        const SizedBox(height: 6),
        Text(label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9, height: 1.2,
            color: textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
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
              color: AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.workspace_premium_rounded, color: AppColors.cyan, size: 28),
          ),
          const SizedBox(height: 14),
          Text(t('unlock_premium_title'),
              style: TextStyle(color: textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(t('unlock_premium_subtitle'),
              style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
            children: visible.map((f) => featureTile(f)).toList(),
          ),
          if (!_heroExpanded) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _heroExpanded = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('+$remaining more features',
                    style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.cyan, size: 18),
                ]),
              ),
            ),
          ] else ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => setState(() => _heroExpanded = false),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Show less',
                  style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_up_rounded, color: textSecondary, size: 16),
              ]),
            ),
          ],
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
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: plan.allowedFeatures.isEmpty
                        ? null
                        : () => _showUserFeaturesSheet(context, plan, t),
                    child: Container(
                      margin: const EdgeInsets.only(left: 38),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.92)
                            : AppColors.cyan.withValues(alpha: isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white
                              : AppColors.cyan.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(children: [
                        Icon(Icons.apps_rounded, size: 14, color: AppColors.cyan),
                        const SizedBox(width: 6),
                        Text(
                          plan.allowedFeatures.isEmpty
                              ? t('no_features_selected_message')
                              : '${plan.allowedFeatures.length} features included',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.cyan,
                          ),
                        ),
                        const Spacer(),
                        if (plan.allowedFeatures.isNotEmpty)
                          const Icon(Icons.chevron_right_rounded, size: 14,
                              color: AppColors.cyan),
                      ]),
                    ),
                  ),
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

  void _showUserFeaturesSheet(BuildContext context, SubscriptionPlan plan, String Function(String) t) {
    const featureColors = {
      'quick_transactions':  Color(0xFFFFA000),
      'secure_transactions': Color(0xFF00897B),
      'group_creation':      Color(0xFF1E88E5),
      'group_expenses':      Color(0xFFE53935),
      'private_chat':        Color(0xFF8E24AA),
      'group_chat':          Color(0xFF3949AB),
      'discover':            Color(0xFF00ACC1),
      'view_rankings':       Color(0xFF43A047),
      'reports':             Color(0xFFD81B60),
      'budget_planning':     Color(0xFF6D4C41),
      'smart_insights':      Color(0xFF5E35B1),
    };

    final included = kSubscriptionFeatures
        .where((f) => plan.allowedFeatures.contains(f.key))
        .toList();
    if (included.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.65),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              decoration: BoxDecoration(
                color: AppThemeColors.divider(ctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(children: [
                const Icon(Icons.workspace_premium_rounded, size: 20, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(plan.name,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(ctx))),
                    Text('${included.length} premium feature${included.length == 1 ? '' : 's'} unlocked',
                        style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFFFB300), Color(0xFFFF8F00)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${included.length} / ${kSubscriptionFeatures.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
            const Divider(height: 16),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 14,
                  children: included.map((f) {
                    final color = featureColors[f.key] ?? AppColors.cyan;
                    return Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35),
                              blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Icon(f.icon, size: 26, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        t(f.labelKey).split(' ').take(2).join('\n'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5, height: 1.25, fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(ctx),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem(int index, String text) {
    final accent = _accentColor(index);
    final isDark = AppThemeColors.isDark(context);
    final num = '${index + 1}'.padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.18 : 0.10),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Left accent stripe
            Container(
              width: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.45)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Card body
            Expanded(
              child: Container(
                color: AppThemeColors.cardBg(context),
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(children: [
                  // Number badge
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                    ),
                    child: Center(
                      child: Text(num,
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold, color: accent)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                            color: AppThemeColors.primaryText(context))),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.workspace_premium_rounded, size: 17, color: Colors.amber.shade600),
                ]),
              ),
            ),
          ]),
        ),
      ),
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
