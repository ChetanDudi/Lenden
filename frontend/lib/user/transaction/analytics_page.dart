import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../settings/privacy_settings_page.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../widgets/currency_display.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import 'quick_transactions/quick_transactions_page.dart';
import 'secure_transactions/view_secure_transactions_page.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';
import './widgets/analytics_models.dart';
import './widgets/analytics_detail_page.dart';

class AnalyticsPage extends StatefulWidget {
  final List<dynamic>? transactions;

  const AnalyticsPage({Key? key, this.transactions}) : super(key: key);

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin, CurrencyDisplayMixin<AnalyticsPage> {
  late final TabController _tabController;
  Map<String, dynamic>? _secureAnalytics;
  Map<String, dynamic>? _quickAnalytics;
  Map<String, dynamic>? _groupAnalytics;
  bool _secureLoading = true;
  bool _quickLoading = true;
  bool _groupLoading = true;
  bool _quickTransactionsLoading = true;
  bool _secureTransactionsLoading = true;
  String? _secureError;
  String? _quickError;
  String? _groupError;
  String? _quickTransactionsError;
  String? _secureTransactionsError;
  bool? analyticsSharing;
  List<Map<String, dynamic>> _quickTransactions = [];
  List<Map<String, dynamic>> _secureTransactions = [];
  String? _displayCurrencyError;
  bool _secureTabLoaded = false;
  bool _quickTabLoaded = false;
  bool _groupTabLoaded = false;
  bool _quickDetailsLoaded = false;
  bool _secureDetailsLoaded = false;
  List<dynamic> _userGroups = [];
  bool _groupDetailsLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    loadCurrencies(onError: (_) {
      if (mounted) setState(() => _displayCurrencyError = AppLocalizations.of(context).t('currency_conversion_unavailable_message'));
    });
    _ensureTabLoaded(0); // Overview — loads everything
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _ensureTabLoaded(_tabController.index);
  }

  Future<void> _ensureTabLoaded(int index, {bool force = false}) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final email = session.user?['email'];

    if (email == null) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _secureLoading = false;
        _quickLoading = false;
        _groupLoading = false;
        _secureError = t('user_email_not_found_message');
        _quickError = t('user_email_not_found_message');
        _groupError = t('user_email_not_found_message');
      });
      return;
    }

    // Tab 0 = Overview: load everything at once
    if (index == 0) {
      await Future.wait([
        if (force || !_secureTabLoaded || !_secureDetailsLoaded) ...[
          _fetchSecureAnalytics(email),
          _fetchSecureTransactions(email: email),
        ],
        if (force || !_quickTabLoaded || !_quickDetailsLoaded) ...[
          _fetchQuickAnalytics(email),
          _fetchQuickTransactions(),
        ],
        if (force || !_groupTabLoaded) ...[
          _fetchGroupAnalytics(email),
          _fetchUserGroups(),
        ],
      ]);
      _secureTabLoaded = true;
      _secureDetailsLoaded = true;
      _quickTabLoaded = true;
      _quickDetailsLoaded = true;
      _groupTabLoaded = true;
      return;
    }

    if (index == 1) { // Secure
      if (!force && _secureTabLoaded && _secureDetailsLoaded) return;
      await Future.wait([
        _fetchSecureAnalytics(email),
        _fetchSecureTransactions(email: email),
      ]);
      _secureTabLoaded = true;
      _secureDetailsLoaded = true;
      return;
    }

    if (index == 2) { // Quick
      if (!force && _quickTabLoaded && _quickDetailsLoaded) return;
      await Future.wait([
        _fetchQuickAnalytics(email),
        _fetchQuickTransactions(),
      ]);
      _quickTabLoaded = true;
      _quickDetailsLoaded = true;
      return;
    }

    // Tab 3 = Group
    if (!force && _groupTabLoaded) return;
    await Future.wait([
      _fetchGroupAnalytics(email),
      _fetchUserGroups(),
    ]);
    _groupTabLoaded = true;
  }

  Future<void> _refreshActiveTab() async {
    await loadCurrencies(onError: (_) {
      if (mounted) setState(() => _displayCurrencyError = AppLocalizations.of(context).t('currency_conversion_unavailable_message'));
    });
    await _ensureTabLoaded(_tabController.index, force: true);
  }

  Future<void> _fetchSecureAnalytics(String email) async {
    setState(() {
      _secureLoading = true;
      _secureError = null;
    });
    try {
      final res = await ApiClient.get('/api/analytics/secure?email=$email');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['analyticsSharing'] == false) {
          setState(() {
            analyticsSharing = false;
            _secureAnalytics = null;
            _secureLoading = false;
          });
          return;
        }

        setState(() {
          analyticsSharing = true;
          _secureAnalytics = data;
          _secureLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _secureError = t('failed_to_fetch_secure_analytics_message');
          _secureLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _secureError = t('unable_to_connect_check_internet_message');
        _secureLoading = false;
      });
    }
  }

  Future<void> _fetchGroupAnalytics(String email) async {
    setState(() {
      _groupLoading = true;
      _groupError = null;
    });
    try {
      final res = await ApiClient.get('/api/analytics/groups?email=$email');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['analyticsSharing'] == false) {
          setState(() {
            analyticsSharing = false;
            _groupAnalytics = null;
            _groupLoading = false;
          });
          return;
        }

        setState(() {
          analyticsSharing = true;
          _groupAnalytics = data;
          _groupLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _groupError = t('failed_to_fetch_group_analytics_message');
          _groupLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _groupError = t('unable_to_connect_check_internet_message');
        _groupLoading = false;
      });
    }
  }

  Future<void> _fetchUserGroups() async {
    setState(() => _groupDetailsLoading = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _userGroups = List<dynamic>.from(data['groups'] ?? []);
          _groupDetailsLoading = false;
        });
      } else {
        if (mounted) setState(() => _groupDetailsLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _groupDetailsLoading = false);
    }
  }

  // â”€â”€ Group insight helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Map<String, double> _computeMemberContributions() {
    final Map<String, double> contrib = {};
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        final by = (e['addedBy'] ?? '').toString();
        if (!by.contains('@')) continue;
        final amt = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        contrib[by] = (contrib[by] ?? 0) + amt;
      }
    }
    return contrib;
  }

  Map<String, double> _computeCategoryTotals() {
    final Map<String, double> cats = {};
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        final cat = (e['category'] ?? 'other').toString();
        final amt = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        cats[cat] = (cats[cat] ?? 0) + amt;
      }
    }
    return cats;
  }

  String _fmtGroupAmt(double amtInr) {
    final target = selectedCurrency.toUpperCase();
    if (target != 'INR' &&
        !(currencyData?.canConvert('INR', target) ?? false)) {
      return 'â‚¹${amtInr.toStringAsFixed(0)}';
    }
    final converted =
        currencyData?.convert(amtInr, 'INR', target) ?? amtInr;
    final sym = currencyData?.symbolFor(target) ?? 'â‚¹';
    return '$sym${converted.toStringAsFixed(0)}';
  }

  static const _kCategoryMeta = {
    'food':          {'label': 'Food',          'color': Color(0xFFFF7043)},
    'transport':     {'label': 'Transport',     'color': Color(0xFF42A5F5)},
    'accommodation': {'label': 'Stay',          'color': Color(0xFF7E57C2)},
    'entertainment': {'label': 'Fun',           'color': Color(0xFFEC407A)},
    'shopping':      {'label': 'Shopping',      'color': Color(0xFFFF7043)},
    'utilities':     {'label': 'Utilities',     'color': Color(0xFF26A69A)},
    'medical':       {'label': 'Medical',       'color': Color(0xFFEF5350)},
    'education':     {'label': 'Education',     'color': Color(0xFF66BB6A)},
    'other':         {'label': 'Other',         'color': Color(0xFF90A4AE)},
  };

  String _categoryDisplayLabel(String key, String Function(String) t) {
    switch (key) {
      case 'food':
        return t('category_food_label');
      case 'transport':
        return t('category_transport_label');
      case 'accommodation':
        return t('category_stay_label');
      case 'entertainment':
        return t('category_fun_label');
      case 'shopping':
        return t('category_shopping_label');
      case 'utilities':
        return t('category_utilities_label');
      case 'medical':
        return t('category_medical_label');
      case 'education':
        return t('category_education_label');
      default:
        return t('other');
    }
  }

  String _attentionItemDisplayLabel(String key, String Function(String) t) {
    switch (key) {
      case 'Overdue Interest':
        return t('overdue_interest_label');
      case 'Partially Cleared':
        return t('partially_cleared_label');
      case 'Missing Proof Files':
        return t('missing_proof_files_label');
      default:
        return key;
    }
  }

  Widget _buildGroupInsights() {
    final t = AppLocalizations.of(context).t;
    if (_groupDetailsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: AppColors.cyan)),
      );
    }
    if (_userGroups.isEmpty) return const SizedBox.shrink();

    final contrib = _computeMemberContributions();
    final cats = _computeCategoryTotals();
    if (contrib.isEmpty && cats.isEmpty) return const SizedBox.shrink();

    final sortedContrib = contrib.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedCats = cats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxContrib =
        sortedContrib.isEmpty ? 1.0 : sortedContrib.first.value;
    final maxCat = sortedCats.isEmpty ? 1.0 : sortedCats.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        // Member contributions
        Text(t('member_contributions_label'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 4),
        Text(t('who_paid_into_group_message'),
            style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 12),
        ...sortedContrib.take(8).map((entry) {
          final pct = maxContrib > 0 ? entry.value / maxContrib : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key.split('@').first,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _fmtGroupAmt(entry.value),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: AppThemeColors.border(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2E7D32)),
                  ),
                ),
              ],
            ),
          );
        }),

        if (sortedCats.isNotEmpty) ...[
          const SizedBox(height: 28),
          // Top categories
          Text(t('spending_by_category_label'),
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 4),
          Text(t('across_all_group_expenses_message'),
              style:
                  TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 12),
          ...sortedCats.map((entry) {
            final meta = _kCategoryMeta[entry.key] ??
                _kCategoryMeta['other']!;
            final pct = maxCat > 0 ? entry.value / maxCat : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: meta['color'] as Color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _categoryDisplayLabel(entry.key, t),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        _fmtGroupAmt(entry.value),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 7,
                      backgroundColor: AppThemeColors.border(context),
                      valueColor: AlwaysStoppedAnimation<Color>(
                          meta['color'] as Color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Future<void> _fetchQuickAnalytics(String email) async {
    setState(() {
      _quickLoading = true;
      _quickError = null;
    });
    try {
      final res = await ApiClient.get('/api/analytics/quick?email=$email');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['analyticsSharing'] == false) {
          setState(() {
            analyticsSharing = false;
            _quickAnalytics = null;
            _quickLoading = false;
          });
          return;
        }

        setState(() {
          analyticsSharing = true;
          _quickAnalytics = data;
          _quickLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _quickError = t('failed_to_fetch_quick_analytics_message');
          _quickLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _quickError = t('unable_to_connect_check_internet_message');
        _quickLoading = false;
      });
    }
  }

  Future<void> _fetchQuickTransactions() async {
    setState(() {
      _quickTransactionsLoading = true;
      _quickTransactionsError = null;
    });
    try {
      final res = await ApiClient.get('/api/quick-transactions');
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final rawTransactions = body['quickTransactions'];
        final fetchedTransactions = rawTransactions is List
            ? rawTransactions.map((transaction) {
                return Map<String, dynamic>.from(
                  transaction is Map ? transaction : {},
                );
              }).toList()
            : <Map<String, dynamic>>[];
        setState(() {
          _quickTransactions = fetchedTransactions;
          _quickTransactionsLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _quickTransactionsError = t('failed_to_load_quick_transactions_message');
          _quickTransactionsLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _quickTransactionsError = t('error_colon_label').replaceFirst('{error}', '$e');
        _quickTransactionsLoading = false;
      });
    }
  }

  Future<void> _fetchSecureTransactions({String? email}) async {
    setState(() {
      _secureTransactionsLoading = true;
      _secureTransactionsError = null;
    });

    try {
      final resolvedEmail = email ??
          Provider.of<SessionProvider>(context, listen: false).user?['email'];
      if (resolvedEmail == null) {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _secureTransactionsError = t('user_email_not_found_message');
          _secureTransactionsLoading = false;
        });
        return;
      }

      final res = await ApiClient.get(
        '/api/transactions/user?email=${Uri.encodeComponent(resolvedEmail)}',
      );
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final lending = List<Map<String, dynamic>>.from(body['lending'] ?? []);
        final borrowing =
            List<Map<String, dynamic>>.from(body['borrowing'] ?? []);
        setState(() {
          _secureTransactions = [...lending, ...borrowing];
          _secureTransactionsLoading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          _secureTransactionsError = t('failed_to_load_secure_transactions_message');
          _secureTransactionsLoading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        _secureTransactionsError = t('error_colon_label').replaceFirst('{error}', '$e');
        _secureTransactionsLoading = false;
      });
    }
  }

  bool _hasMissingAnalyticsConversion() {
    if (selectedCurrency.toUpperCase() == 'INR') return false;
    if (currencyData == null) return true;
    return !currencyData!.canConvert('INR', selectedCurrency);
  }

  String _formatAmount(double value, {String originalCurrency = 'INR'}) {
    final sourceCurrency = originalCurrency.toUpperCase();
    final targetCurrency = selectedCurrency.toUpperCase();
    final canConvert = currencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency == targetCurrency);
    if (!canConvert) {
      final sourceSymbol = currencyData?.symbolFor(sourceCurrency) ??
          (sourceCurrency == 'INR' ? 'â‚¹' : sourceCurrency);
      return '$sourceSymbol${value.toStringAsFixed(2)}';
    }

    final converted = currencyData?.convert(
          value,
          sourceCurrency,
          targetCurrency,
        ) ??
        value;
    final symbol = currencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? 'â‚¹' : targetCurrency);
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  String _currentUserEmail() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    return session.user?['email']?.toString().toLowerCase().trim() ?? '';
  }

  bool _isCurrentUserCreator(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final creatorEmail =
        (transaction['creatorEmail'] ?? '').toString().toLowerCase().trim();
    return currentUserEmail.isNotEmpty && creatorEmail == currentUserEmail;
  }

  String _roleForViewer(Map<String, dynamic> transaction) {
    final storedRole =
        (transaction['role'] ?? 'lender').toString().toLowerCase();
    if (_isCurrentUserCreator(transaction)) {
      return storedRole;
    }
    return storedRole == 'lender' ? 'borrower' : 'lender';
  }

  String _formatSelectedCurrencyValue(num value) {
    final targetCurrency = selectedCurrency.toUpperCase();
    final symbol = currencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? 'â‚¹' : targetCurrency);
    return '$symbol${value.toStringAsFixed(2)}';
  }

  double _displayAmountForTransaction(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toDouble() ??
        double.tryParse('${transaction['amount']}') ??
        0.0;
    final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
    final targetCurrency = selectedCurrency.toUpperCase();
    final canConvert = currencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency.toUpperCase() == targetCurrency);
    return canConvert
        ? (currencyData?.convert(
                amount, sourceCurrency, targetCurrency) ??
            amount)
        : amount;
  }

  Map<String, String> _buildQuickInsights() {
    final t = AppLocalizations.of(context).t;
    final a = _quickAnalytics;
    if (a == null || (a['total'] ?? 0) == 0) {
      return {
        'biggestPending': _formatSelectedCurrencyValue(0),
        'mostFrequentCounterparty': t('no_data_label'),
        'thisMonthNetFlow': _formatSelectedCurrencyValue(0),
        'averageQuickAmount': _formatSelectedCurrencyValue(0),
      };
    }
    final biggestInr = (a['biggestPendingAmountInr'] as num?)?.toDouble() ?? 0.0;
    final netFlowInr = (a['thisMonthNetFlowInr'] as num?)?.toDouble() ?? 0.0;
    final avgInr    = (a['averageAmountInr'] as num?)?.toDouble() ?? 0.0;
    final cp        = (a['mostFrequentCounterparty'] as String?) ?? t('no_data_label');
    return {
      'biggestPending': _formatAmount(biggestInr),
      'mostFrequentCounterparty': cp,
      'thisMonthNetFlow': '${netFlowInr >= 0 ? '+' : ''}${_formatAmount(netFlowInr.abs())}',
      'averageQuickAmount': _formatAmount(avgInr),
    };
  }

  List<Map<String, dynamic>> _buildQuickBreakdown() {
    final t = AppLocalizations.of(context).t;
    final a = _quickAnalytics;
    return [
      {'title': t('lent_label'),     'value': (a?['lentCount']     as num?)?.toDouble() ?? 0.0},
      {'title': t('borrowed_label'), 'value': (a?['borrowedCount'] as num?)?.toDouble() ?? 0.0},
      {'title': t('cleared_label'),  'value': (a?['cleared']       as num?)?.toDouble() ?? 0.0},
      {'title': t('pending_label'),  'value': (a?['uncleared']     as num?)?.toDouble() ?? 0.0},
    ];
  }

  double _secureDisplayAmount(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toDouble() ??
        double.tryParse('${transaction['amount']}') ??
        0.0;
    final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
    final targetCurrency = selectedCurrency.toUpperCase();
    final canConvert = currencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency.toUpperCase() == targetCurrency);
    return canConvert
        ? (currencyData?.convert(amount, sourceCurrency, targetCurrency) ??
            amount)
        : amount;
  }

  String _secureViewerRole(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final userEmail = (transaction['userEmail'] ?? '').toString().toLowerCase().trim();
    final storedRole = (transaction['role'] ?? 'lender').toString().toLowerCase();
    if (currentUserEmail == userEmail) return storedRole;
    return storedRole == 'lender' ? 'borrower' : 'lender';
  }

  String _secureCounterpartyLabel(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final userEmail = (transaction['userEmail'] ?? '').toString().trim();
    final counterpartyEmail =
        (transaction['counterpartyEmail'] ?? '').toString().trim();

    if (currentUserEmail.isEmpty) {
      return counterpartyEmail.isNotEmpty ? counterpartyEmail : userEmail;
    }
    if (userEmail.toLowerCase() == currentUserEmail) {
      return counterpartyEmail.isNotEmpty ? counterpartyEmail : userEmail;
    }
    if (counterpartyEmail.toLowerCase() == currentUserEmail) {
      return userEmail.isNotEmpty ? userEmail : counterpartyEmail;
    }
    return counterpartyEmail.isNotEmpty ? counterpartyEmail : userEmail;
  }

  Map<String, String> _buildSecureInsights() {
    final t = AppLocalizations.of(context).t;
    if (_secureTransactions.isEmpty) {
      return {
        'largestPending': _formatSelectedCurrencyValue(0),
        'averageRepayment': t('no_data_label'),
        'topCounterparty': t('no_data_label'),
        'interestMix': t('interest_mix_count_label').replaceFirst('{withCount}', '0').replaceFirst('{withoutCount}', '0'),
      };
    }

    Map<String, dynamic>? largestPending;
    final counterpartyCounts = <String, int>{};
    int repaymentSamples = 0;
    int totalRepaymentDays = 0;
    int withInterest = 0;

    for (final transaction in _secureTransactions) {
      final fullyCleared =
          transaction['userCleared'] == true && transaction['counterpartyCleared'] == true;
      if (!fullyCleared) {
        if (largestPending == null ||
            _secureDisplayAmount(transaction) > _secureDisplayAmount(largestPending)) {
          largestPending = transaction;
        }
      }

      final counterparty = _secureCounterpartyLabel(transaction);
      if (counterparty.isNotEmpty) {
        counterpartyCounts[counterparty] = (counterpartyCounts[counterparty] ?? 0) + 1;
      }

      final expectedReturnDate =
          DateTime.tryParse((transaction['expectedReturnDate'] ?? '').toString());
      final startDate = DateTime.tryParse((transaction['date'] ?? '').toString());
      if (expectedReturnDate != null && startDate != null) {
        totalRepaymentDays += expectedReturnDate.difference(startDate).inDays.abs();
        repaymentSamples += 1;
      }

      final interestType = (transaction['interestType'] ?? 'none').toString().toLowerCase();
      if (interestType != 'none' && interestType.isNotEmpty) {
        withInterest += 1;
      }
    }

    final topCounterparty = counterpartyCounts.isEmpty
        ? t('no_data_label')
        : counterpartyCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final averageRepayment = repaymentSamples == 0
        ? t('no_data_label')
        : t('days_avg_label').replaceFirst('{days}', '${(totalRepaymentDays / repaymentSamples).round()}');
    final noInterest = _secureTransactions.length - withInterest;

    return {
      'largestPending': largestPending == null
          ? _formatSelectedCurrencyValue(0)
          : _formatSelectedCurrencyValue(_secureDisplayAmount(largestPending)),
      'averageRepayment': averageRepayment,
      'topCounterparty': topCounterparty,
      'interestMix': t('interest_mix_count_label').replaceFirst('{withCount}', '$withInterest').replaceFirst('{withoutCount}', '$noInterest'),
    };
  }

  List<Map<String, dynamic>> _buildSecureAttentionItems() {
    final now = DateTime.now();
    final overdue = _secureTransactions.where((transaction) {
      final expected = DateTime.tryParse((transaction['expectedReturnDate'] ?? '').toString());
      final fullyCleared =
          transaction['userCleared'] == true && transaction['counterpartyCleared'] == true;
      final interestType =
          (transaction['interestType'] ?? 'none').toString().toLowerCase();
      return expected != null &&
          expected.isBefore(now) &&
          !fullyCleared &&
          interestType != 'none';
    }).length;
    final partiallyCleared = _secureTransactions.where((transaction) {
      final userCleared = transaction['userCleared'] == true;
      final counterpartyCleared = transaction['counterpartyCleared'] == true;
      return userCleared != counterpartyCleared;
    }).length;
    final missingProof = _secureTransactions.where((transaction) {
      final photos = transaction['photos'];
      final files = transaction['files'];
      final hasPhotos = photos is List && photos.isNotEmpty;
      final hasFiles = files is List && files.isNotEmpty;
      return !hasPhotos && !hasFiles;
    }).length;

    return [
      {
        'title': 'Overdue Interest',
        'value': overdue,
        'icon': Icons.warning_amber_rounded,
        'colors': const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
      },
      {
        'title': 'Partially Cleared',
        'value': partiallyCleared,
        'icon': Icons.timelapse_rounded,
        'colors': const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
      },
      {
        'title': 'Missing Proof Files',
        'value': missingProof,
        'icon': Icons.attach_file_rounded,
        'colors': const [Color(0xFFFFB562), Color(0xFFFFD9A0)],
      },
    ];
  }

  String _buildSecureCurrencyContext() {
    final t = AppLocalizations.of(context).t;
    final currencies = _secureTransactions
        .map((transaction) => (transaction['currency'] ?? 'INR').toString().toUpperCase())
        .toSet();
    if (currencies.isEmpty) return t('no_secure_currency_data_message');
    if (currencies.length == 1) {
      return t('single_currency_context_message').replaceFirst('{currency}', currencies.first);
    }
    return t('mixed_currency_context_message').replaceFirst('{currencies}', currencies.take(4).join(', '));
  }

  Map<String, String> _buildSecureExtendedInsights() {
    final t = AppLocalizations.of(context).t;
    if (_secureTransactions.isEmpty) {
      return {
        'netPosition': _formatSelectedCurrencyValue(0),
        'netPositionSign': '+',
        'partialPaymentRatio': '0%',
        'defaultRate': '0%',
        'avgClearTime': t('no_data_label'),
      };
    }

    double totalLent = 0;
    double totalBorrowed = 0;
    int partialCount = 0;
    int overdueCount = 0;
    int clearedCount = 0;
    int totalClearDays = 0;
    final now = DateTime.now();

    for (final t in _secureTransactions) {
      final role = _secureViewerRole(t);
      final amount = _secureDisplayAmount(t);
      if (role == 'lender') {
        totalLent += amount;
      } else {
        totalBorrowed += amount;
      }

      final pp = t['partialPayments'];
      if (t['isPartiallyPaid'] == true || (pp is List && pp.isNotEmpty)) {
        partialCount++;
      }

      final fullyCleared =
          t['userCleared'] == true && t['counterpartyCleared'] == true;
      final expected =
          DateTime.tryParse((t['expectedReturnDate'] ?? '').toString());
      if (!fullyCleared && expected != null && expected.isBefore(now)) {
        overdueCount++;
      }

      if (fullyCleared) {
        final startDate = DateTime.tryParse(
            (t['date'] ?? t['createdAt'] ?? '').toString());
        if (startDate != null) {
          totalClearDays += now.difference(startDate).inDays;
          clearedCount++;
        }
      }
    }

    final netPosition = totalLent - totalBorrowed;
    final partialRatio =
        (partialCount / _secureTransactions.length * 100);
    final defaultRate =
        (overdueCount / _secureTransactions.length * 100);
    final avgClear = clearedCount == 0
        ? t('no_data_label')
        : t('days_avg_label').replaceFirst('{days}', '${(totalClearDays / clearedCount).round()}');

    return {
      'netPosition': _formatSelectedCurrencyValue(netPosition.abs()),
      'netPositionSign': netPosition >= 0 ? '+' : '-',
      'partialPaymentRatio': '${partialRatio.toStringAsFixed(0)}%',
      'defaultRate': '${defaultRate.toStringAsFixed(0)}%',
      'avgClearTime': avgClear,
    };
  }

  List<Map<String, dynamic>> _buildSecureCounterpartyData() {
    final Map<String, Map<String, dynamic>> data = {};

    for (final t in _secureTransactions) {
      final cp = _secureCounterpartyLabel(t);
      if (cp.isEmpty) continue;

      if (!data.containsKey(cp)) {
        data[cp] = {
          'email': cp,
          'totalLent': 0.0,
          'totalBorrowed': 0.0,
          'count': 0,
          'clearedCount': 0,
        };
      }

      final role = _secureViewerRole(t);
      final amount = _secureDisplayAmount(t);
      if (role == 'lender') {
        data[cp]!['totalLent'] =
            (data[cp]!['totalLent'] as double) + amount;
      } else {
        data[cp]!['totalBorrowed'] =
            (data[cp]!['totalBorrowed'] as double) + amount;
      }
      data[cp]!['count'] = (data[cp]!['count'] as int) + 1;
      final fullyCleared =
          t['userCleared'] == true && t['counterpartyCleared'] == true;
      if (fullyCleared) {
        data[cp]!['clearedCount'] =
            (data[cp]!['clearedCount'] as int) + 1;
      }
    }

    final sorted = data.values.toList();
    sorted.sort((a, b) {
      final aTotal =
          (a['totalLent'] as double) + (a['totalBorrowed'] as double);
      final bTotal =
          (b['totalLent'] as double) + (b['totalBorrowed'] as double);
      return bTotal.compareTo(aTotal);
    });
    return sorted.take(5).toList();
  }

  String _buildSecureForecastText() {
    final t = AppLocalizations.of(context).t;
    final cleared = _secureTransactions
        .where((transaction) =>
            transaction['userCleared'] == true && transaction['counterpartyCleared'] == true)
        .length;
    final total = _secureTransactions.length;
    final uncleared = total - cleared;
    if (total == 0) return t('no_transactions_to_forecast_message');
    if (uncleared == 0) return t('all_transactions_cleared_message');

    if (cleared == 0) {
      return t('transactions_pending_start_clearing_message').replaceFirst('{count}', '$uncleared');
    }

    final now = DateTime.now();
    DateTime? earliest;
    for (final transaction in _secureTransactions) {
      final d = DateTime.tryParse((transaction['date'] ?? transaction['createdAt'] ?? '').toString());
      if (d != null && (earliest == null || d.isBefore(earliest))) {
        earliest = d;
      }
    }
    final months =
        earliest == null ? 1 : ((now.difference(earliest).inDays) / 30).ceil().clamp(1, 120);
    final clearRatePerMonth = cleared / months;
    if (clearRatePerMonth <= 0) return t('rate_too_slow_to_estimate_message');

    final monthsNeeded = (uncleared / clearRatePerMonth).ceil();
    final forecastDate = DateTime(now.year, now.month + monthsNeeded);
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mIdx = ((forecastDate.month - 1) % 12).clamp(0, 11);
    return t('forecast_pending_cleared_by_message')
        .replaceFirst('{count}', '$uncleared')
        .replaceFirst('{month}', monthNames[mIdx])
        .replaceFirst('{year}', '${forecastDate.year}');
  }

  List<Map<String, dynamic>> _buildQuickNetBalances() {
    final balances = <String, Map<String, dynamic>>{};

    for (final transaction in _quickTransactions) {
      final users = List<Map<String, dynamic>>.from(transaction['users'] ?? []);
      final counterparty = users.firstWhere(
        (user) =>
            (user['email'] ?? '').toString().toLowerCase().trim() !=
            _currentUserEmail(),
        orElse: () => {},
      );
      final email = (counterparty['email'] ?? '').toString();
      final name = (counterparty['name'] ?? email).toString();
      if (email.isEmpty) continue;

      if (!balances.containsKey(email)) {
        balances[email] = {
          'email': email,
          'name': name,
          'net': 0.0,
        };
      }

      final amount = _displayAmountForTransaction(transaction);
      final isLender = _roleForViewer(transaction) == 'lender';
      if (isLender) {
        (balances[email]!['net'] as double) + amount;
      } else {
        (balances[email]!['net'] as double) - amount;
      }
      balances[email]!['net'] = ((balances[email]!['net'] as double?) ?? 0.0) +
          (isLender ? amount : -amount);
    }

    return balances.values.toList();
  }

  List<Map<String, dynamic>> _buildTopQuickPartners() {
    final totals = <String, double>{};
    final names = <String, String>{};

    for (final transaction in _quickTransactions) {
      final users = List<Map<String, dynamic>>.from(transaction['users'] ?? []);
      final counterparty = users.firstWhere(
        (user) =>
            (user['email'] ?? '').toString().toLowerCase().trim() !=
            _currentUserEmail(),
        orElse: () => {},
      );
      final email = (counterparty['email'] ?? '').toString();
      final name = (counterparty['name'] ?? email).toString();
      if (email.isEmpty) continue;
      final amount = _displayAmountForTransaction(transaction).abs();
      totals[email] = (totals[email] ?? 0) + amount;
      names[email] = name;
    }

    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(3)
        .map((entry) => {
              'email': entry.key,
              'name': names[entry.key] ?? entry.key,
              'amount': entry.value,
            })
        .toList();
  }

  List<FlSpot> _buildQuickTrendSpots() {
    final monthlyCounts = (_quickAnalytics?['monthlyCounts'] as List<dynamic>?)
            ?.map((count) => (count as num).toDouble())
            .toList() ??
        [];
    return List<FlSpot>.generate(
      monthlyCounts.length,
      (index) => FlSpot(index.toDouble(), monthlyCounts[index]),
    );
  }

  List<String> _buildQuickTrendLabels() {
    final months = List<String>.from(_quickAnalytics?['months'] ?? const []);
    final spots = _buildQuickTrendSpots();
    if (months.length == spots.length && months.isNotEmpty) {
      return months;
    }
    return List<String>.generate(spots.length, (index) => 'M${index + 1}');
  }

  Widget _buildQuickTrendChart() {
    final t = AppLocalizations.of(context).t;
    final spots = _buildQuickTrendSpots();
    final labels = _buildQuickTrendLabels();
    if (spots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Center(
          child: Text(t('no_quick_trend_data_message')),
        ),
      );
    }

    final maxY = spots.isEmpty
        ? 1
        : spots.map((e) => e.y).reduce((a, b) => a > b ? a : b);
    final dynamicInterval = spots.length > 6 ? 2.0 : 1.0;

    return Container(
      height: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.16),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                interval: maxY > 0 ? maxY / 4 : 1,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: dynamicInterval,
                reservedSize: 35,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  // Shorten label format for better fit
                  final label = labels[index];
                  final shortened = label.length > 7
                      ? label.replaceAll(RegExp(r'/0'), '/')
                      : label;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Transform.rotate(
                      angle: -0.3,
                      child: Text(
                        shortened,
                        style: TextStyle(
                          color: AppThemeColors.secondaryText(context),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: const LinearGradient(
                colors: [Color(0xFF7C9DFF), Color(0xFF58C4DD)],
              ),
              barWidth: 4,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7C9DFF).withValues(alpha: 0.25),
                    const Color(0xFF58C4DD).withValues(alpha: 0.05)
                  ],
                ),
              ),
            ),
          ],
          borderData: FlBorderData(show: false),
          minY: 0,
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> colors,
    bool useTricolorBorder = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 190,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: useTricolorBorder
                ? const [Colors.orange, Colors.white, Colors.green]
                : colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: (useTricolorBorder ? colors.first : Colors.black)
                  .withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.last, size: 20),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSecureFilteredPage({
    String filter = 'All',
    String clearanceFilter = 'All',
    String interestTypeFilter = 'All',
    String globalSearch = '',
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserTransactionsPage(
          initialFilter: filter,
          initialClearanceFilter: clearanceFilter,
          initialInterestTypeFilter: interestTypeFilter,
          initialGlobalSearch: globalSearch,
        ),
      ),
    );
  }

  // ── Overview helpers ──────────────────────────────────────────────────────

  Map<String, double> _computeOverviewStats() {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final todayStart = DateTime(now.year, now.month, now.day);

    double totalIncome = 0, totalExpense = 0;
    double pendingAmount = 0;
    double monthlySpending = 0, weeklySpending = 0, dailySpending = 0;

    // Quick transactions
    for (final t in _quickTransactions) {
      final amt = _displayAmountForTransaction(t);
      final role = _roleForViewer(t);
      final cleared = t['cleared'] == true;
      if (role == 'lender') {
        totalExpense += amt;
      } else {
        totalIncome += amt;
      }
      if (!cleared) pendingAmount += amt;

      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date != null) {
        final spending = role == 'lender' ? amt : 0.0;
        if (!date.isBefore(monthStart)) monthlySpending += spending;
        if (!date.isBefore(weekStart)) weeklySpending += spending;
        if (!date.isBefore(todayStart)) dailySpending += spending;
      }
    }

    // Secure transactions
    for (final t in _secureTransactions) {
      final amt = _secureDisplayAmount(t);
      final role = _secureViewerRole(t);
      final cleared = t['userCleared'] == true && t['counterpartyCleared'] == true;
      if (role == 'lender') {
        totalExpense += amt;
      } else {
        totalIncome += amt;
      }
      if (!cleared) pendingAmount += amt;

      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date != null) {
        final spending = role == 'lender' ? amt : 0.0;
        if (!date.isBefore(monthStart)) monthlySpending += spending;
        if (!date.isBefore(weekStart)) weeklySpending += spending;
        if (!date.isBefore(todayStart)) dailySpending += spending;
      }
    }

    // Group expenses
    final userEmail = _currentUserEmail();
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        final addedBy = (e['addedBy'] ?? '').toString().toLowerCase();
        if (addedBy != userEmail) continue;
        final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        final target = selectedCurrency.toUpperCase();
        final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
            ? (currencyData?.convert(raw, 'INR', target) ?? raw)
            : raw;
        totalExpense += amt;
        pendingAmount += amt;

        final dateStr = (e['date'] ?? '').toString();
        final date = DateTime.tryParse(dateStr)?.toLocal();
        if (date != null) {
          if (!date.isBefore(monthStart)) monthlySpending += amt;
          if (!date.isBefore(weekStart)) weeklySpending += amt;
          if (!date.isBefore(todayStart)) dailySpending += amt;
        }
      }
    }

    return {
      'totalBalance': totalIncome - totalExpense,
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'pendingAmount': pendingAmount,
      'monthlySpending': monthlySpending,
      'weeklySpending': weeklySpending,
      'dailySpending': dailySpending,
    };
  }

  Map<String, double> _computeCombinedCategoryTotals() {
    final cats = <String, double>{};
    final userEmail = _currentUserEmail();

    for (final t in _quickTransactions) {
      if (_roleForViewer(t) != 'lender') continue;
      final cat = (t['category'] ?? 'other').toString();
      cats[cat] = (cats[cat] ?? 0) + _displayAmountForTransaction(t);
    }
    for (final t in _secureTransactions) {
      if (_secureViewerRole(t) != 'lender') continue;
      final cat = (t['category'] ?? 'other').toString();
      cats[cat] = (cats[cat] ?? 0) + _secureDisplayAmount(t);
    }
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        if ((e['addedBy'] ?? '').toString().toLowerCase() != userEmail) continue;
        final cat = (e['category'] ?? 'other').toString();
        final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        final target = selectedCurrency.toUpperCase();
        final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
            ? (currencyData?.convert(raw, 'INR', target) ?? raw)
            : raw;
        cats[cat] = (cats[cat] ?? 0) + amt;
      }
    }
    return cats;
  }

  List<Map<String, dynamic>> _buildUpcomingPayments() {
    final now = DateTime.now();
    final cutoff = now.add(const Duration(days: 30));
    final upcoming = <Map<String, dynamic>>[];
    for (final t in _secureTransactions) {
      final cleared = t['userCleared'] == true && t['counterpartyCleared'] == true;
      if (cleared) continue;
      final expectedDate = DateTime.tryParse((t['expectedReturnDate'] ?? '').toString());
      if (expectedDate == null) continue;
      if (expectedDate.isAfter(now) && expectedDate.isBefore(cutoff)) {
        upcoming.add({
          'label': _secureCounterpartyLabel(t),
          'amount': _secureDisplayAmount(t),
          'date': expectedDate,
          'role': _secureViewerRole(t),
        });
      }
    }
    upcoming.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    return upcoming.take(5).toList();
  }

  List<Map<String, dynamic>> _buildRecentTransactions() {
    final all = <Map<String, dynamic>>[];
    for (final t in _quickTransactions) {
      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      all.add({
        'date': date,
        'amount': _displayAmountForTransaction(t),
        'label': (() {
          final users = List<Map<String, dynamic>>.from(t['users'] ?? []);
          final cp = users.firstWhere(
            (u) => (u['email'] ?? '').toString().toLowerCase() != _currentUserEmail(),
            orElse: () => {},
          );
          return (cp['name'] ?? cp['email'] ?? 'Unknown').toString();
        })(),
        'role': _roleForViewer(t),
        'type': 'quick',
        'category': (t['category'] ?? 'other').toString(),
      });
    }
    for (final t in _secureTransactions) {
      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      all.add({
        'date': date,
        'amount': _secureDisplayAmount(t),
        'label': _secureCounterpartyLabel(t),
        'role': _secureViewerRole(t),
        'type': 'secure',
        'category': (t['category'] ?? 'other').toString(),
      });
    }
    final userEmail = _currentUserEmail();
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        if ((e['addedBy'] ?? '').toString().toLowerCase() != userEmail) continue;
        final dateStr = (e['date'] ?? '').toString();
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        final target = selectedCurrency.toUpperCase();
        final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
            ? (currencyData?.convert(raw, 'INR', target) ?? raw)
            : raw;
        all.add({
          'date': date,
          'amount': amt,
          'label': (g['title'] ?? 'Group').toString(),
          'role': 'lender',
          'type': 'group',
          'category': (e['category'] ?? 'other').toString(),
        });
      }
    }
    all.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
    return all.take(5).toList();
  }

  Widget _buildOverviewStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    bool isNegative = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color),
            ),
            const Spacer(),
            if (isNegative) Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.red[400]),
          ]),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: isNegative ? Colors.red[600] : AppThemeColors.primaryText(context)),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final allLoading = (_quickTransactionsLoading && _quickTransactions.isEmpty) ||
        (_secureTransactionsLoading && _secureTransactions.isEmpty) ||
        (_groupDetailsLoading && _userGroups.isEmpty);
    if (allLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    }

    final t = AppLocalizations.of(context).t;
    final sym = currencyData?.symbolFor(selectedCurrency.toUpperCase()) ??
        (selectedCurrency.toUpperCase() == 'INR' ? '₹' : selectedCurrency);
    final stats = _computeOverviewStats();
    final balance = stats['totalBalance'] ?? 0;
    final upcoming = _buildUpcomingPayments();
    final recent = _buildRecentTransactions();
    final catTotals = _computeCombinedCategoryTotals();
    final sortedCats = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalCatAmt = sortedCats.fold(0.0, (s, e) => s + e.value);

    String fmt(double v) => '$sym${v.toStringAsFixed(2)}';

    return RefreshIndicator(
      onRefresh: _refreshActiveTab,
      color: AppColors.cyan,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Currency selector + subtitle
            Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Financial Overview',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context))),
                    Text('All transaction types combined',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                  ]),
                ),
                buildCurrencySelector(),
              ],
            ),
            const SizedBox(height: 20),

            // ── Key Stats Grid ───────────────────────────────────────────────
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _buildOverviewStatCard(
                  title: 'Total Balance',
                  value: fmt(balance.abs()),
                  icon: balance >= 0 ? Icons.account_balance_rounded : Icons.account_balance_outlined,
                  color: balance >= 0 ? const Color(0xFF26C6A6) : Colors.red[400]!,
                  isNegative: balance < 0,
                ),
                _buildOverviewStatCard(
                  title: 'Pending Amount',
                  value: fmt(stats['pendingAmount'] ?? 0),
                  icon: Icons.pending_actions_rounded,
                  color: Colors.orange,
                ),
                _buildOverviewStatCard(
                  title: 'Total Income',
                  value: fmt(stats['totalIncome'] ?? 0),
                  icon: Icons.arrow_downward_rounded,
                  color: const Color(0xFF42A5F5),
                ),
                _buildOverviewStatCard(
                  title: 'Total Expense',
                  value: fmt(stats['totalExpense'] ?? 0),
                  icon: Icons.arrow_upward_rounded,
                  color: Colors.deepPurple,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Spending Periods ─────────────────────────────────────────────
            Text('Spending Periods',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildPeriodCard('Daily', fmt(stats['dailySpending'] ?? 0),
                    Icons.today_rounded, const Color(0xFF66BB6A))),
                const SizedBox(width: 10),
                Expanded(child: _buildPeriodCard('Weekly', fmt(stats['weeklySpending'] ?? 0),
                    Icons.date_range_rounded, const Color(0xFF42A5F5))),
                const SizedBox(width: 10),
                Expanded(child: _buildPeriodCard('Monthly', fmt(stats['monthlySpending'] ?? 0),
                    Icons.calendar_month_rounded, Colors.deepPurple)),
              ],
            ),
            const SizedBox(height: 24),

            // ── Transaction Count Summary ─────────────────────────────────────
            Text('Transaction Summary',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Count by type',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _buildTypeCountCard('Quick', _quickTransactions.length, AppColors.cyan, Icons.flash_on_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _buildTypeCountCard('Secure', _secureTransactions.length, Colors.deepPurple, Icons.lock_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _buildTypeCountCard('Groups', _userGroups.fold(0, (s, g) => s + ((g['expenses'] as List?)?.length ?? 0)), Colors.teal, Icons.group_rounded)),
            ]),
            const SizedBox(height: 24),

            // ── Biggest Transaction ───────────────────────────────────────────
            Builder(builder: (ctx) {
              double biggestAmt = 0;
              String biggestLabel = '';
              String biggestType = '';
              for (final qt in _quickTransactions) {
                final amt = _displayAmountForTransaction(qt);
                if (amt > biggestAmt) {
                  biggestAmt = amt;
                  biggestType = 'Quick';
                  final users = List<Map<String, dynamic>>.from(qt['users'] ?? []);
                  final cp = users.firstWhere(
                    (u) => (u['email'] ?? '').toString().toLowerCase() != _currentUserEmail(),
                    orElse: () => {},
                  );
                  biggestLabel = (cp['name'] ?? cp['email'] ?? 'Unknown').toString();
                }
              }
              for (final st in _secureTransactions) {
                final amt = _secureDisplayAmount(st);
                if (amt > biggestAmt) {
                  biggestAmt = amt;
                  biggestType = 'Secure';
                  biggestLabel = _secureCounterpartyLabel(st);
                }
              }
              final userEmail = _currentUserEmail();
              for (final g in _userGroups) {
                for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
                  if ((e['addedBy'] ?? '').toString().toLowerCase() != userEmail) continue;
                  final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
                  final target = selectedCurrency.toUpperCase();
                  final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
                      ? (currencyData?.convert(raw, 'INR', target) ?? raw)
                      : raw;
                  if (amt > biggestAmt) {
                    biggestAmt = amt;
                    biggestType = 'Group';
                    biggestLabel = (g['title'] ?? 'Group').toString();
                  }
                }
              }
              if (biggestAmt == 0) return const SizedBox.shrink();
              final typeColor = biggestType == 'Quick' ? AppColors.cyan : biggestType == 'Secure' ? Colors.deepPurple : Colors.teal;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Biggest Transaction',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: typeColor.withValues(alpha: 0.25)),
                    boxShadow: [BoxShadow(color: typeColor.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.emoji_events_rounded, color: typeColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(biggestLabel,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text(biggestType, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor)),
                      ),
                    ])),
                    Text(fmt(biggestAmt),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16,
                            color: AppThemeColors.primaryText(context))),
                  ]),
                ),
                const SizedBox(height: 24),
              ]);
            }),

            // ── Upcoming Payments ────────────────────────────────────────────
            Text('Upcoming Payments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Secure transactions due in next 30 days',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 12),
            if (upcoming.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppThemeColors.border(context)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF26C6A6)),
                  const SizedBox(width: 10),
                  Text('No upcoming payments in the next 30 days',
                      style: TextStyle(color: AppThemeColors.secondaryText(context))),
                ]),
              )
            else
              ...upcoming.map((up) {
                final date = up['date'] as DateTime;
                final daysLeft = date.difference(DateTime.now()).inDays;
                final isLender = up['role'] == 'lender';
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border(left: BorderSide(
                      color: daysLeft <= 7 ? Colors.red[400]! : Colors.orange,
                      width: 4,
                    )),
                  ),
                  child: Row(children: [
                    Icon(isLender ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        color: isLender ? Colors.red[400] : Colors.green, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(up['label'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      Text('Due in $daysLeft day${daysLeft == 1 ? '' : 's'} · '
                          '${date.day}/${date.month}/${date.year}',
                          style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                    ])),
                    Text(fmt((up['amount'] as num).toDouble()),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: daysLeft <= 7 ? Colors.red[600] : AppThemeColors.primaryText(context))),
                  ]),
                );
              }),
            const SizedBox(height: 24),

            // ── Recent Transactions ──────────────────────────────────────────
            Text('Recent Transactions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Latest activity across all types',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppThemeColors.border(context)),
                ),
                child: Text('No transactions yet.',
                    style: TextStyle(color: AppThemeColors.secondaryText(context))),
              )
            else
              ...recent.map((r) {
                final isLender = r['role'] == 'lender';
                final typeLabel = r['type'] == 'quick' ? 'Quick' : r['type'] == 'secure' ? 'Secure' : 'Group';
                final typeColor = r['type'] == 'quick'
                    ? AppColors.cyan
                    : r['type'] == 'secure'
                        ? Colors.deepPurple
                        : Colors.teal;
                final date = r['date'] as DateTime;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isLender ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 16, color: isLender ? Colors.red[400] : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['label'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(typeLabel,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: typeColor)),
                        ),
                        const SizedBox(width: 6),
                        Text('${date.day}/${date.month}/${date.year}',
                            style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                      ]),
                    ])),
                    Text(fmt((r['amount'] as num).toDouble()),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isLender ? Colors.red[600] : Colors.green[700])),
                  ]),
                );
              }),
            const SizedBox(height: 24),

            // ── Category Wise Spending (Pie + Bars) ──────────────────────────
            Text('Category Wise Spending',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Your expenses broken down by category',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 16),
            if (sortedCats.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppThemeColors.border(context)),
                ),
                child: Text('No expense data yet.',
                    style: TextStyle(color: AppThemeColors.secondaryText(context))),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(children: [
                  // Pie Chart
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 48,
                        sections: sortedCats.asMap().entries.map((entry) {
                          final meta = _kCategoryMeta[entry.value.key] ?? _kCategoryMeta['other']!;
                          final pct = totalCatAmt > 0 ? entry.value.value / totalCatAmt * 100 : 0.0;
                          return PieChartSectionData(
                            color: meta['color'] as Color,
                            value: entry.value.value,
                            title: '${pct.toStringAsFixed(0)}%',
                            radius: 52,
                            titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            badgeWidget: null,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Legend + bars
                  ...sortedCats.map((entry) {
                    final meta = _kCategoryMeta[entry.key] ?? _kCategoryMeta['other']!;
                    final pct = totalCatAmt > 0 ? entry.value / totalCatAmt : 0.0;
                    final catColor = meta['color'] as Color;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(color: catColor, shape: BoxShape.circle)),
                          Expanded(child: Text(_categoryDisplayLabel(entry.key, t),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                          Text(fmt(entry.value),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 7,
                            backgroundColor: AppThemeColors.border(context),
                            valueColor: AlwaysStoppedAnimation<Color>(catColor),
                          ),
                        ),
                      ]),
                    );
                  }),
                ]),
              ),
            const SizedBox(height: 24),

            // ── Spending Trend ───────────────────────────────────────────────
            Text('Spending Trend (Monthly)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Monthly transaction activity across all types',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 12),
            _buildCombinedSpendingTrendChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context)),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildTypeCountCard(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.07), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 8),
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildCategoryPieChart({required Map<String, double> cats}) {
    if (cats.isEmpty) return const SizedBox.shrink();
    final t = AppLocalizations.of(context).t;
    final sorted = cats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0.0, (s, e) => s + e.value);
    final sym = currencyData?.symbolFor(selectedCurrency.toUpperCase()) ??
        (selectedCurrency.toUpperCase() == 'INR' ? '₹' : selectedCurrency);
    String fmt(double v) => '$sym${v.toStringAsFixed(2)}';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 48,
              sections: sorted.map((entry) {
                final meta = _kCategoryMeta[entry.key] ?? _kCategoryMeta['other']!;
                final pct = total > 0 ? entry.value / total * 100 : 0.0;
                return PieChartSectionData(
                  color: meta['color'] as Color,
                  value: entry.value,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: 52,
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...sorted.map((entry) {
          final meta = _kCategoryMeta[entry.key] ?? _kCategoryMeta['other']!;
          final pct = total > 0 ? entry.value / total : 0.0;
          final catColor = meta['color'] as Color;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: catColor, shape: BoxShape.circle)),
                Expanded(child: Text(_categoryDisplayLabel(entry.key, t),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                Text(fmt(entry.value),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 7,
                  backgroundColor: AppThemeColors.border(context),
                  valueColor: AlwaysStoppedAnimation<Color>(catColor),
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildGroupBreakdown() {
    final userEmail = _currentUserEmail();
    final groupTotals = <Map<String, dynamic>>[];
    for (final g in _userGroups) {
      double total = 0.0;
      int expenseCount = 0;
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        if ((e['addedBy'] ?? '').toString().toLowerCase() != userEmail) continue;
        final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        final target = selectedCurrency.toUpperCase();
        final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
            ? (currencyData?.convert(raw, 'INR', target) ?? raw)
            : raw;
        total += amt;
        expenseCount++;
      }
      if (total > 0) {
        groupTotals.add({
          'title': (g['title'] ?? 'Group').toString(),
          'amount': total,
          'count': expenseCount,
        });
      }
    }
    if (groupTotals.isEmpty) return const SizedBox.shrink();
    groupTotals.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    final sym = currencyData?.symbolFor(selectedCurrency.toUpperCase()) ??
        (selectedCurrency.toUpperCase() == 'INR' ? '₹' : selectedCurrency);
    String fmt(double v) => '$sym${v.toStringAsFixed(2)}';
    const cardColors = [
      [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
      [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
      [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
      [Color(0xFF58C4DD), Color(0xFF89E0EF)],
      [Color(0xFFFFB562), Color(0xFFFFD9A0)],
      [Color(0xFF7E74F1), Color(0xFFC0BCFF)],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Group-wise Spending',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 4),
        Text('Your contribution to each group',
            style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 12),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemCount: groupTotals.length,
            itemBuilder: (context, i) {
              final item = groupTotals[i];
              final c = cardColors[i % cardColors.length];
              return Container(
                width: 160,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [c[0], c[1]], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(item['title'].toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('${item['count']} expense${(item['count'] as int) != 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                    const SizedBox(height: 8),
                    Text(fmt(item['amount'] as double),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCombinedSpendingTrendChart() {
    // Build monthly buckets for last 6 months
    final now = DateTime.now();
    final buckets = List.generate(6, (i) {
      final month = DateTime(now.year, now.month - 5 + i, 1);
      return {'month': month, 'amount': 0.0};
    });

    void addToMonthBucket(DateTime date, double amount) {
      for (final bucket in buckets) {
        final m = bucket['month'] as DateTime;
        if (date.year == m.year && date.month == m.month) {
          bucket['amount'] = (bucket['amount'] as double) + amount;
          break;
        }
      }
    }

    final userEmail = _currentUserEmail();
    for (final t in _quickTransactions) {
      if (_roleForViewer(t) != 'lender') continue;
      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date != null) addToMonthBucket(date, _displayAmountForTransaction(t));
    }
    for (final t in _secureTransactions) {
      if (_secureViewerRole(t) != 'lender') continue;
      final dateStr = (t['date'] ?? t['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(dateStr)?.toLocal();
      if (date != null) addToMonthBucket(date, _secureDisplayAmount(t));
    }
    for (final g in _userGroups) {
      for (final e in List<dynamic>.from(g['expenses'] ?? [])) {
        if ((e['addedBy'] ?? '').toString().toLowerCase() != userEmail) continue;
        final dateStr = (e['date'] ?? '').toString();
        final date = DateTime.tryParse(dateStr)?.toLocal();
        if (date == null) continue;
        final raw = ((e['amountInr'] ?? e['amount'] ?? 0) as num).toDouble();
        final target = selectedCurrency.toUpperCase();
        final amt = (target != 'INR' && (currencyData?.canConvert('INR', target) ?? false))
            ? (currencyData?.convert(raw, 'INR', target) ?? raw)
            : raw;
        addToMonthBucket(date, amt);
      }
    }

    final spots = buckets.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), (e.value['amount'] as double))).toList();
    final labels = buckets.map((b) {
      final m = b['month'] as DateTime;
      const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return names[m.month - 1];
    }).toList();

    final maxY = spots.isEmpty ? 1.0 : spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 240,
      padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.14),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i],
                        style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: const LinearGradient(colors: [Color(0xFF26C6A6), Color(0xFF42A5F5)]),
              barWidth: 3,
              dotData: FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(colors: [
                  const Color(0xFF26C6A6).withValues(alpha: 0.22),
                  const Color(0xFF42A5F5).withValues(alpha: 0.04),
                ], begin: Alignment.topCenter, end: Alignment.bottomCenter),
              ),
            ),
          ],
          borderData: FlBorderData(show: false),
          minY: 0,
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: transparentAppBar(context, title: t('analytics_title_label')),
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(top: context.sh(45)),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final t = AppLocalizations.of(context).t;
    if (analyticsSharing == false) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 64,
                color: AppColors.cyan,
              ),
              const SizedBox(height: 24),
              Text(
                t('analytics_disabled_privacy_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t('enable_analytics_sharing_message'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: AppThemeColors.secondaryText(context)),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacySettingsPage(),
                    ),
                  ).then((_) => _refreshActiveTab());
                },
                icon: const Icon(Icons.settings, color: Colors.white),
                label: Text(
                  t('open_privacy_settings_label'),
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        AppTabBar(
          controller: _tabController,
          tabs: [
            AppTabItem(label: 'Overview'),
            AppTabItem(label: t('secure_trxns_tab_label')),
            AppTabItem(label: t('quick_trxns_tab_label')),
            AppTabItem(label: t('groups_trxns_tab_label')),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverviewTab(),
              _buildTabContent(
                analytics: _secureAnalytics,
                loading: _secureLoading,
                error: _secureError,
                config: AnalyticsTabConfig(
                  tabId: 'secure',
                  tabTitle: t('secure_analytics_title_label'),
                  tabSubtitle: t('secure_analytics_subtitle_message'),
                  metrics: [
                    AnalyticsMetricDefinition(
                      id: 'totalLent',
                      title: t('total_lent_label'),
                      subtitle: t('amount_shared_by_you_message'),
                      icon: Icons.arrow_upward_rounded,
                      colors: const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalBorrowed',
                      title: t('total_borrowed_label'),
                      subtitle: t('amount_taken_by_you_message'),
                      icon: Icons.arrow_downward_rounded,
                      colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalInterest',
                      title: t('interest_label'),
                      subtitle: t('interest_tracked_so_far_message'),
                      icon: Icons.percent_rounded,
                      colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'cleared',
                      title: t('cleared_label'),
                      subtitle: t('fully_cleared_transactions_message'),
                      icon: Icons.check_circle_outline_rounded,
                      colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'uncleared',
                      title: t('uncleared_label'),
                      subtitle: t('pending_transactions_message'),
                      icon: Icons.pending_actions_rounded,
                      colors: const [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'total',
                      title: t('total_transactions_label'),
                      subtitle: t('all_secure_records_message'),
                      icon: Icons.receipt_long_rounded,
                      colors: const [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'monthly',
                      title: t('monthly_activity_label'),
                      subtitle: t('twelve_month_transaction_trend_message'),
                      icon: Icons.show_chart_rounded,
                      colors: const [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
                      isTrend: true,
                    ),
                  ],
                ),
              ),
              _buildTabContent(
                analytics: _quickAnalytics,
                loading: _quickLoading,
                error: _quickError,
                config: AnalyticsTabConfig(
                  tabId: 'quick',
                  tabTitle: t('quick_analytics_title_label'),
                  tabSubtitle: t('quick_analytics_subtitle_message'),
                  metrics: [
                    AnalyticsMetricDefinition(
                      id: 'totalLent',
                      title: t('total_lent_label'),
                      subtitle: t('quick_amount_shared_by_you_message'),
                      icon: Icons.flash_on_rounded,
                      colors: const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalBorrowed',
                      title: t('total_borrowed_label'),
                      subtitle: t('quick_amount_taken_by_you_message'),
                      icon: Icons.bolt_rounded,
                      colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalInterest',
                      title: t('outstanding_label'),
                      subtitle: t('uncleared_quick_amount_message'),
                      icon: Icons.account_balance_wallet_outlined,
                      colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'cleared',
                      title: t('cleared_label'),
                      subtitle: t('quick_transactions_already_closed_message'),
                      icon: Icons.check_circle_outline_rounded,
                      colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'uncleared',
                      title: t('uncleared_label'),
                      subtitle: t('quick_transactions_still_open_message'),
                      icon: Icons.pending_actions_rounded,
                      colors: const [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'total',
                      title: t('total_transactions_label'),
                      subtitle: t('all_quick_records_message'),
                      icon: Icons.receipt_long_rounded,
                      colors: const [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'monthly',
                      title: t('monthly_activity_label'),
                      subtitle: t('twelve_month_quick_trend_message'),
                      icon: Icons.show_chart_rounded,
                      colors: const [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
                      isTrend: true,
                    ),
                  ],
                ),
              ),
              _buildTabContent(
                analytics: _groupAnalytics,
                loading: _groupLoading,
                error: _groupError,
                config: AnalyticsTabConfig(
                  tabId: 'group',
                  tabTitle: t('group_analytics_title_label'),
                  tabSubtitle: t('group_analytics_subtitle_message'),
                  metrics: [
                    AnalyticsMetricDefinition(
                      id: 'totalLent',
                      title: t('contributed_label'),
                      subtitle: t('what_you_paid_into_groups_message'),
                      icon: Icons.volunteer_activism_outlined,
                      colors: const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalBorrowed',
                      title: t('your_share_title_label'),
                      subtitle: t('what_belongs_to_you_message'),
                      icon: Icons.pie_chart_outline_rounded,
                      colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalInterest',
                      title: t('outstanding_label'),
                      subtitle: t('amount_still_unsettled_message'),
                      icon: Icons.account_balance_wallet_outlined,
                      colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    AnalyticsMetricDefinition(
                      id: 'cleared',
                      title: t('settled_label'),
                      subtitle: t('splits_already_settled_message'),
                      icon: Icons.task_alt_rounded,
                      colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'uncleared',
                      title: t('unsettled_label'),
                      subtitle: t('splits_still_pending_message'),
                      icon: Icons.hourglass_bottom_rounded,
                      colors: const [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'total',
                      title: t('expenses_label'),
                      subtitle: t('tracked_group_expenses_message'),
                      icon: Icons.receipt_rounded,
                      colors: const [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'totalGroups',
                      title: t('groups_label'),
                      subtitle: t('groups_included_in_analytics_message'),
                      icon: Icons.groups_2_outlined,
                      colors: const [Color(0xFF7E74F1), Color(0xFFC0BCFF)],
                    ),
                    AnalyticsMetricDefinition(
                      id: 'monthly',
                      title: t('monthly_activity_label'),
                      subtitle: t('twelve_month_group_trend_message'),
                      icon: Icons.show_chart_rounded,
                      colors: const [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
                      isTrend: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabContent({
    required Map<String, dynamic>? analytics,
    required bool loading,
    required String? error,
    required AnalyticsTabConfig config,
  }) {
    final t = AppLocalizations.of(context).t;
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cyan),
      );
    }

    if (error != null) {
      return errorStateWidget(context, error, _refreshActiveTab);
    }

    if (analytics == null) {
      return _buildEmptyState(
        icon: Icons.analytics_outlined,
        title: t('no_analytics_available_label'),
        message: t('not_enough_data_for_tab_message'),
      );
    }

    final metrics = _buildMetrics(config.metrics, analytics);
    final heroMetrics = metrics.take(2).toList();
    final showWarning =
        _displayCurrencyError != null || _hasMissingAnalyticsConversion();

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshActiveTab();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeaderCard(config, analytics),
            if (showWarning) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFF6B6B)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFE53935),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _displayCurrencyError ??
                            t('conversion_unavailable_for_analytics_message').replaceFirst('{currency}', selectedCurrency),
                        style: const TextStyle(
                          color: Color(0xFFC62828),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: heroMetrics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) => _buildHeroMetricCard(
                  metric: heroMetrics[index],
                  analytics: analytics,
                  allMetrics: metrics,
                  tabId: config.tabId,
                  tabTitle: config.tabTitle,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (config.tabId == 'secure') ...[
              const SizedBox(height: 4),
              Text(
                t('secure_insights_label'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
              const SizedBox(height: 10),
              if (_secureTransactionsLoading)
                const SizedBox(
                  height: 110,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  ),
                )
              else if (_secureTransactionsError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(_secureTransactionsError!,
                        style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      onPressed: _fetchSecureTransactions,
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFFF06322)),
                      label: const Text('Retry', style: TextStyle(color: Color(0xFFF06322), fontWeight: FontWeight.bold)),
                    ),
                  ]),
                )
              else ...[
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSummaryCard(
                        title: t('largest_pending_label'),
                        value: _buildSecureInsights()['largestPending'] ?? _formatSelectedCurrencyValue(0),
                        icon: Icons.priority_high_rounded,
                        colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          clearanceFilter: 'Totally Uncleared',
                        ),
                      ),
                      _buildSummaryCard(
                        title: t('repayment_speed_label'),
                        value:
                            _buildSecureInsights()['averageRepayment'] ?? t('no_data_label'),
                        icon: Icons.timer_outlined,
                        colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          interestTypeFilter: 'with_interest',
                        ),
                      ),
                      _buildSummaryCard(
                        title: t('top_counterparty_label'),
                        value: _buildSecureInsights()['topCounterparty'] ?? t('no_data_label'),
                        icon: Icons.people_alt_rounded,
                        colors: const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          globalSearch:
                              _buildSecureInsights()['topCounterparty'] == t('no_data_label')
                                  ? ''
                                  : _buildSecureInsights()['topCounterparty']!,
                        ),
                      ),
                      _buildSummaryCard(
                        title: t('interest_split_label'),
                        value: _buildSecureInsights()['interestMix'] ?? t('no_data_label'),
                        icon: Icons.account_tree_outlined,
                        colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          interestTypeFilter: 'with_interest',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t('risk_attention_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemCount: _buildSecureAttentionItems().length,
                    itemBuilder: (context, index) {
                      final item = _buildSecureAttentionItems()[index];
                      return _buildSummaryCard(
                        title: _attentionItemDisplayLabel(item['title']!.toString(), t),
                        value: item['value']!.toString(),
                        icon: item['icon'] as IconData,
                        colors: List<Color>.from(item['colors'] as List),
                        useTricolorBorder: true,
                        onTap: () {
                          if (item['title'] == 'Overdue Interest') {
                            _openSecureFilteredPage(
                              interestTypeFilter: 'with_interest',
                            );
                          } else if (item['title'] == 'Partially Cleared') {
                            _openSecureFilteredPage(
                              clearanceFilter: 'Partially Cleared',
                            );
                          } else {
                            _openSecureFilteredPage();
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppThemeColors.border(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        color: AppThemeColors.secondaryText(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _buildSecureCurrencyContext(),
                          style: TextStyle(
                            color: AppThemeColors.secondaryText(context),
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Extended metrics row
                Text(
                  t('extended_metrics_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                Builder(builder: (context) {
                  final ext = _buildSecureExtendedInsights();
                  return SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        _buildSummaryCard(
                          title: t('net_position_label'),
                          value:
                              '${ext['netPositionSign']}${ext['netPosition']}',
                          icon: Icons.balance_rounded,
                          colors: const [
                            Color(0xFF6BCB91),
                            Color(0xFFA9E4A7)
                          ],
                          useTricolorBorder: true,
                        ),
                        _buildSummaryCard(
                          title: t('partial_pay_rate_label'),
                          value: ext['partialPaymentRatio'] ?? '0%',
                          icon: Icons.payments_outlined,
                          colors: const [
                            Color(0xFF7C9DFF),
                            Color(0xFFA9B8FF)
                          ],
                          useTricolorBorder: true,
                        ),
                        _buildSummaryCard(
                          title: t('default_rate_label'),
                          value: ext['defaultRate'] ?? '0%',
                          icon: Icons.warning_amber_rounded,
                          colors: const [
                            Color(0xFFFF8B7B),
                            Color(0xFFFFC2AE)
                          ],
                          useTricolorBorder: true,
                        ),
                        _buildSummaryCard(
                          title: t('avg_clear_time_label'),
                          value: ext['avgClearTime'] ?? t('no_data_label'),
                          icon: Icons.timer_outlined,
                          colors: const [
                            Color(0xFF58C4DD),
                            Color(0xFF89E0EF)
                          ],
                          useTricolorBorder: true,
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                // Counterparty drilldown
                Text(
                  t('top_counterparties_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(t('top_counterparties_subtitle_message'),
                    style: TextStyle(
                        fontSize: 12, color: AppThemeColors.mutedText(context))),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final partners = _buildSecureCounterpartyData();
                  if (partners.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(t('no_counterparty_data_message'),
                          style: TextStyle(
                              color: AppThemeColors.mutedText(context))),
                    );
                  }
                  return Column(
                    children: partners.map((p) {
                      final lent = p['totalLent'] as double;
                      final borrowed = p['totalBorrowed'] as double;
                      final net = lent - borrowed;
                      final total = lent + borrowed;
                      final count = p['count'] as int;
                      final cleared = p['clearedCount'] as int;
                      final email = p['email'].toString();
                      final displayName = email.contains('@')
                          ? email.split('@').first
                          : email;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: AppThemeColors.border(context)),
                          boxShadow: const [
                            BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2))
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.cyan
                                    .withValues(alpha: 0.15),
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Color(0xFF0077B6),
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(displayName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                        t('txn_count_cleared_message')
                                            .replaceFirst('{count}', '$count')
                                            .replaceFirst('{cleared}', '$cleared'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppThemeColors.mutedText(context))),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
                                children: [
                                  Text(
                                      _formatSelectedCurrencyValue(total),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                  Text(
                                      '${net >= 0 ? '+' : ''}${_formatSelectedCurrencyValue(net.abs())} net',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: net >= 0
                                              ? Colors.green.shade600
                                              : Colors.red.shade600)),
                                ],
                              ),
                            ]),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: count > 0
                                    ? (cleared / count).clamp(0.0, 1.0)
                                    : 0,
                                minHeight: 6,
                                backgroundColor: AppThemeColors.border(context),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    cleared == count
                                        ? Colors.green
                                        : Colors.orange),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }),
                const SizedBox(height: 24),
                // Clearance forecast card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF0F7FF), Color(0xFFE8F5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                      top: const BorderSide(
                          color: AppColors.tricolorOrange, width: 2),
                      bottom: const BorderSide(
                          color: AppColors.tricolorGreen, width: 2),
                      left: BorderSide(
                          color: Colors.blue.shade200, width: 1),
                      right: BorderSide(
                          color: Colors.blue.shade200, width: 1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6)
                              .withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.auto_graph,
                            color: Color(0xFF0077B6), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('clearance_forecast_label'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0077B6))),
                            const SizedBox(height: 4),
                            Text(
                              _buildSecureForecastText(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppThemeColors.secondaryText(context),
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // Secure category breakdown
              Builder(builder: (context) {
                final cats = <String, double>{};
                for (final st in _secureTransactions) {
                  if (_secureViewerRole(st) != 'lender') continue;
                  final cat = (st['category'] ?? 'other').toString();
                  cats[cat] = (cats[cat] ?? 0) + _secureDisplayAmount(st);
                }
                if (cats.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('spending_by_category_label'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text('Loans given, broken down by purpose',
                      style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 12),
                  _buildCategoryPieChart(cats: cats),
                  const SizedBox(height: 24),
                ]);
              }),
            ],
            if (config.tabId == 'group') ...[
              _buildGroupInsights(),
              _buildGroupBreakdown(),
              const SizedBox(height: 8),
            ],
            if (config.tabId == 'quick') ...[
              const SizedBox(height: 4),
              Text(
                t('quick_insights_label'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
              const SizedBox(height: 10),
              if (_quickTransactionsLoading)
                const SizedBox(
                  height: 110,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.cyan),
                  ),
                )
              else if (_quickTransactionsError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Row(children: [
                    Expanded(child: Text(_quickTransactionsError ?? t('unable_to_load_quick_insights_message'),
                        style: const TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w600))),
                    TextButton.icon(
                      onPressed: _fetchQuickTransactions,
                      icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFFF06322)),
                      label: const Text('Retry', style: TextStyle(color: Color(0xFFF06322), fontWeight: FontWeight.bold)),
                    ),
                  ]),
                )
              else ...[
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSummaryCard(
                        title: t('biggest_pending_label'),
                        value:
                            _buildQuickInsights()['biggestPending'] ?? _formatSelectedCurrencyValue(0),
                        icon: Icons.priority_high_rounded,
                        colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: t('frequent_person_label'),
                        value:
                            _buildQuickInsights()['mostFrequentCounterparty'] ??
                                t('no_data_label'),
                        icon: Icons.person_search_rounded,
                        colors: const [Color(0xFF7E74F1), Color(0xFFC0BCFF)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: t('month_net_flow_label'),
                        value: _buildQuickInsights()['thisMonthNetFlow'] ??
                            _formatSelectedCurrencyValue(0),
                        icon: Icons.swap_vert_circle_rounded,
                        colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: t('average_amount_label'),
                        value: _buildQuickInsights()['averageQuickAmount'] ??
                            _formatSelectedCurrencyValue(0),
                        icon: Icons.analytics_rounded,
                        colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                        useTricolorBorder: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t('per_person_ledger_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 108,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _buildQuickNetBalances().length,
                    itemBuilder: (context, index) {
                      final item = _buildQuickNetBalances()[index];
                      final net = (item['net'] as double?) ?? 0.0;
                      final isPositive = net >= 0;
                      return Container(
                        width: 190,
                        margin: const EdgeInsets.only(right: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF7C9DFF),
                                  Color(0xFFFF8B7B),
                                  Color(0xFF6BCB91),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    (item['name'] ?? item['email'] ?? t('unknown_label'))
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppThemeColors.primaryText(context),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isPositive ? t('you_will_get_label') : t('you_owe_label'),
                                    style: TextStyle(
                                      color: AppThemeColors.secondaryText(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatSelectedCurrencyValue(net.abs()),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isPositive
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t('quick_activity_trend_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 12),
                _buildQuickTrendChart(),
                const SizedBox(height: 20),
                Text(
                  t('quick_breakdown_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemCount: _buildQuickBreakdown().length,
                    itemBuilder: (context, index) {
                      final item = _buildQuickBreakdown()[index];
                      return _buildSummaryCard(
                        title: item['title']!.toString(),
                        value: item['value']!.toStringAsFixed(0),
                        icon: index == 0
                            ? Icons.arrow_upward_rounded
                            : index == 1
                                ? Icons.arrow_downward_rounded
                                : index == 2
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.pending_actions_rounded,
                        colors: index == 0
                            ? const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)]
                            : index == 1
                                ? const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)]
                                : index == 2
                                    ? const [
                                        Color(0xFF6BCB91),
                                        Color(0xFFA9E4A7)
                                      ]
                                    : const [
                                        Color(0xFFFFB562),
                                        Color(0xFFFFD9A0)
                                      ],
                        useTricolorBorder: true,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const QuickTransactionsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list_alt_rounded),
                    label: Text(t('view_quick_transactions_label')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  t('top_quick_partners_label'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final partners = _buildTopQuickPartners();
                    if (partners.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          t('no_partner_data_message'),
                          style: TextStyle(color: AppThemeColors.mutedText(context)),
                        ),
                      );
                    }
                    return SizedBox(
                      height: 118,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemCount: partners.length,
                        itemBuilder: (context, index) {
                          final item = partners[index];
                          return Container(
                            width: 180,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C9DFF), Color(0xFF58C4DD)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  item['name'].toString(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  t('quick_interaction_label'),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatSelectedCurrencyValue(
                                      (item['amount'] as double?) ?? 0.0),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                // Category breakdown for quick transactions
                Builder(builder: (context) {
                  final cats = <String, double>{};
                  for (final qt in _quickTransactions) {
                    if (_roleForViewer(qt) != 'lender') continue;
                    final cat = (qt['category'] ?? 'other').toString();
                    cats[cat] = (cats[cat] ?? 0) + _displayAmountForTransaction(qt);
                  }
                  if (cats.isEmpty) return const SizedBox.shrink();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('spending_by_category_label'),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context))),
                    const SizedBox(height: 4),
                    Text('Where your lent money goes',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                    const SizedBox(height: 12),
                    _buildCategoryPieChart(cats: cats),
                    const SizedBox(height: 24),
                  ]);
                }),
              ],
            ],
            const SizedBox(height: 24),
            Text(
              t('analytics_options_label'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('open_option_charts_message'),
              style: TextStyle(
                fontSize: 13,
                color: AppThemeColors.secondaryText(context),
              ),
            ),
            const SizedBox(height: 14),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.1,
              ),
              itemBuilder: (context, index) => _buildOptionCard(
                metric: metrics[index],
                analytics: analytics,
                allMetrics: metrics,
                tabId: config.tabId,
                tabTitle: config.tabTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    AnalyticsTabConfig config,
    Map<String, dynamic> analytics,
  ) {
    final t = AppLocalizations.of(context).t;
    final total = ((analytics['total'] as num?) ?? 0).toInt();
    final displayCurrency = _hasMissingAnalyticsConversion()
        ? 'INR'
        : selectedCurrency.toUpperCase();
    final monthlyCounts =
        (analytics['monthlyCounts'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList();
    final peakMonth = monthlyCounts.isEmpty
        ? 0.0
        : monthlyCounts.reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  config.tabTitle,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  config.tabSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F7FB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t('all_monetary_values_in_message').replaceFirst('{currency}', displayCurrency),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0099B7),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      t('show_in_label'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    buildCurrencySelector(),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFFE8F2FF), Color(0xFFF7FBFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B58B8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  t('records_label'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('peak_value_message').replaceFirst('{value}', peakMonth.toStringAsFixed(0)),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cyan,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetricCard({
    required AnalyticsMetric metric,
    required Map<String, dynamic> analytics,
    required List<AnalyticsMetric> allMetrics,
    required String tabId,
    required String tabTitle,
  }) {
    return GestureDetector(
      onTap: () => _openMetricPage(metric, analytics, allMetrics, tabId, tabTitle),
      child: Container(
        width: 164,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            colors: metric.colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: metric.colors.first.withValues(alpha: 0.30),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(metric.icon, color: Colors.white, size: 26),
            const Spacer(),
            Text(
              metric.displayValue,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              metric.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required AnalyticsMetric metric,
    required Map<String, dynamic> analytics,
    required List<AnalyticsMetric> allMetrics,
    required String tabId,
    required String tabTitle,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _openMetricPage(metric, analytics, allMetrics, tabId, tabTitle),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: metric.colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(metric.icon, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  metric.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  metric.displayValue,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: metric.colors.first,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metric.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppThemeColors.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<AnalyticsMetric> _buildMetrics(
    List<AnalyticsMetricDefinition> definitions,
    Map<String, dynamic> analytics,
  ) {
    final monthlyCounts =
        (analytics['monthlyCounts'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList();

    return definitions.map((definition) {
      final rawValue = definition.id == 'monthly'
          ? monthlyCounts.fold<double>(0.0, (sum, value) => sum + value)
          : ((analytics[definition.id] as num?) ?? 0).toDouble();

      return AnalyticsMetric(
        id: definition.id,
        title: definition.title,
        subtitle: definition.subtitle,
        icon: definition.icon,
        colors: definition.colors,
        value: rawValue,
        displayValue: definition.isTrend
            ? '${rawValue.toStringAsFixed(0)} events'
            : definition.isCurrency
                ? _formatAmount(rawValue)
                : rawValue.toStringAsFixed(0),
        isCurrency: definition.isCurrency,
        isTrend: definition.isTrend,
      );
    }).toList();
  }

  void _openMetricPage(
    AnalyticsMetric metric,
    Map<String, dynamic> analytics,
    List<AnalyticsMetric> allMetrics,
    String tabId,
    String tabTitle,
  ) {
    if (tabId == 'secure') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserTransactionsPage(
            initialFilter: metric.id == 'totalLent'
                ? 'Lending'
                : metric.id == 'totalBorrowed'
                    ? 'Borrowing'
                    : 'All',
            initialClearanceFilter: metric.id == 'cleared'
                ? 'Totally Cleared'
                : metric.id == 'uncleared'
                    ? 'Totally Uncleared'
                    : 'All',
            initialInterestTypeFilter:
                metric.id == 'totalInterest' ? 'with_interest' : 'All',
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyticsDetailPage(
          tabTitle: tabTitle,
          metric: metric,
          analytics: analytics,
          allMetrics: allMetrics,
          selectedDisplayCurrency: selectedCurrency,
          displayCurrencyData: currencyData,
          hasMissingConversion: _hasMissingAnalyticsConversion(),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.cyan, size: 60),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
            ),
          ],
        ),
      ),
    );
  }
}

