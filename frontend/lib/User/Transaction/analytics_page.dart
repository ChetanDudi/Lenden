import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../Settings/privacy_settings_page.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../utils/display_currency_helper.dart';
import 'Quick Transactions/quick_transactions_page.dart';
import 'Secure Transactions/view_secure_transactions_page.dart';

class AnalyticsPage extends StatefulWidget {
  final List<dynamic>? transactions;

  const AnalyticsPage({Key? key, this.transactions}) : super(key: key);

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with SingleTickerProviderStateMixin {
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
  DisplayCurrencyData? _displayCurrencyData;
  List<Map<String, dynamic>> _quickTransactions = [];
  List<Map<String, dynamic>> _secureTransactions = [];
  String _selectedDisplayCurrency = 'INR';
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
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadDisplayCurrencies();
    _ensureTabLoaded(0);
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
      setState(() {
        _secureLoading = false;
        _quickLoading = false;
        _groupLoading = false;
        _secureError = 'User email not found.';
        _quickError = 'User email not found.';
        _groupError = 'User email not found.';
      });
      return;
    }

    if (index == 0) {
      if (!force && _secureTabLoaded && _secureDetailsLoaded) return;
      await Future.wait([
        _fetchSecureAnalytics(email),
        _fetchSecureTransactions(email: email),
      ]);
      _secureTabLoaded = true;
      _secureDetailsLoaded = true;
      return;
    }

    if (index == 1) {
      if (!force && _quickTabLoaded && _quickDetailsLoaded) return;
      await Future.wait([
        _fetchQuickAnalytics(email),
        _fetchQuickTransactions(),
      ]);
      _quickTabLoaded = true;
      _quickDetailsLoaded = true;
      return;
    }

    if (!force && _groupTabLoaded) return;
    await Future.wait([
      _fetchGroupAnalytics(email),
      _fetchUserGroups(),
    ]);
    _groupTabLoaded = true;
  }

  Future<void> _refreshActiveTab() async {
    await _loadDisplayCurrencies();
    await _ensureTabLoaded(_tabController.index, force: true);
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
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
        _displayCurrencyError =
            'Currency conversion options are not available right now.';
      });
    }
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
        setState(() {
          _secureError = 'Failed to fetch secure transaction analytics.';
          _secureLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _secureError = 'Unable to connect. Please check your internet connection.';
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
        setState(() {
          _groupError = 'Failed to fetch group transaction analytics.';
          _groupLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _groupError = 'Unable to connect. Please check your internet connection.';
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
    final target = _selectedDisplayCurrency.toUpperCase();
    if (target != 'INR' &&
        !(_displayCurrencyData?.canConvert('INR', target) ?? false)) {
      return 'â‚¹${amtInr.toStringAsFixed(0)}';
    }
    final converted =
        _displayCurrencyData?.convert(amtInr, 'INR', target) ?? amtInr;
    final sym = _displayCurrencyData?.symbolFor(target) ?? 'â‚¹';
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

  Widget _buildGroupInsights() {
    if (_groupDetailsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: CircularProgressIndicator(color: Color(0xFF00B4D8))),
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
        // â”€â”€ Member contributions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Text('Member Contributions',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900)),
        const SizedBox(height: 4),
        Text('Who paid into the group (total across all your groups)',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
                    backgroundColor: Colors.grey[200],
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
          // â”€â”€ Top categories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Text('Spending by Category',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900)),
          const SizedBox(height: 4),
          Text('Across all your group expenses',
              style:
                  TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
                          meta['label'] as String,
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
                      backgroundColor: Colors.grey[200],
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
        setState(() {
          _quickError = 'Failed to fetch quick transaction analytics.';
          _quickLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _quickError = 'Unable to connect. Please check your internet connection.';
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
        setState(() {
          _quickTransactionsError = 'Failed to load quick transactions.';
          _quickTransactionsLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _quickTransactionsError = 'Error: $e';
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
        setState(() {
          _secureTransactionsError = 'User email not found.';
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
        setState(() {
          _secureTransactionsError = 'Failed to load secure transactions.';
          _secureTransactionsLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _secureTransactionsError = 'Error: $e';
        _secureTransactionsLoading = false;
      });
    }
  }

  bool _hasMissingAnalyticsConversion() {
    if (_selectedDisplayCurrency.toUpperCase() == 'INR') return false;
    if (_displayCurrencyData == null) return true;
    return !_displayCurrencyData!.canConvert('INR', _selectedDisplayCurrency);
  }

  String _formatAmount(double value, {String originalCurrency = 'INR'}) {
    final sourceCurrency = originalCurrency.toUpperCase();
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final canConvert = _displayCurrencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency == targetCurrency);
    if (!canConvert) {
      final sourceSymbol = _displayCurrencyData?.symbolFor(sourceCurrency) ??
          (sourceCurrency == 'INR' ? 'â‚¹' : sourceCurrency);
      return '$sourceSymbol${value.toStringAsFixed(2)}';
    }

    final converted = _displayCurrencyData?.convert(
          value,
          sourceCurrency,
          targetCurrency,
        ) ??
        value;
    final symbol = _displayCurrencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? 'â‚¹' : targetCurrency);
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  Widget _buildCurrencySelector() {
    final currencies = _displayCurrencyData?.currencies ??
        const <Map<String, String>>[
          {'code': 'INR', 'symbol': 'â‚¹', 'label': ''},
        ];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedDisplayCurrency,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            borderRadius: BorderRadius.circular(16),
            items: currencies
                .map(
                  (currency) => DropdownMenuItem<String>(
                    value: currency['code'],
                    child: Text(
                      '${currency['symbol']} ${currency['code']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final symbol = _displayCurrencyData?.symbolFor(targetCurrency) ??
        (targetCurrency == 'INR' ? 'â‚¹' : targetCurrency);
    return '$symbol${value.toStringAsFixed(2)}';
  }

  double _displayAmountForTransaction(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toDouble() ??
        double.tryParse('${transaction['amount']}') ??
        0.0;
    final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final canConvert = _displayCurrencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency.toUpperCase() == targetCurrency);
    return canConvert
        ? (_displayCurrencyData?.convert(
                amount, sourceCurrency, targetCurrency) ??
            amount)
        : amount;
  }

  Map<String, String> _buildQuickInsights() {
    if (_quickTransactions.isEmpty) {
      return {
        'biggestPending': 'â‚¹0.00',
        'mostFrequentCounterparty': 'No data',
        'thisMonthNetFlow': 'â‚¹0.00',
        'averageQuickAmount': 'â‚¹0.00',
      };
    }

    Map<String, dynamic>? biggestPending;
    final counterpartyCounts = <String, int>{};
    final counterpartyNames = <String, String>{};
    double monthNet = 0;
    double totalAmount = 0;
    final now = DateTime.now();

    for (final transaction in _quickTransactions) {
      final amount = _displayAmountForTransaction(transaction);
      totalAmount += amount;
      if (transaction['cleared'] != true) {
        if (biggestPending == null ||
            _displayAmountForTransaction(biggestPending) < amount) {
          biggestPending = transaction;
        }
      }

      final users = List<Map<String, dynamic>>.from(transaction['users'] ?? []);
      final counterparty = users.firstWhere(
        (user) =>
            (user['email'] ?? '').toString().toLowerCase().trim() !=
            _currentUserEmail(),
        orElse: () => {},
      );
      final email = (counterparty['email'] ?? '').toString();
      final name = (counterparty['name'] ?? email).toString();
      if (email.isNotEmpty) {
        counterpartyCounts[email] = (counterpartyCounts[email] ?? 0) + 1;
        counterpartyNames[email] = name;
      }

      final date = DateTime.tryParse(
        (transaction['date'] ?? transaction['createdAt'] ?? '').toString(),
      )?.toLocal();
      if (date != null && date.year == now.year && date.month == now.month) {
        if (_roleForViewer(transaction) == 'lender') {
          monthNet += amount;
        } else {
          monthNet -= amount;
        }
      }
    }

    String mostFrequent = 'No data';
    if (counterpartyCounts.isNotEmpty) {
      final top = counterpartyCounts.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      mostFrequent = counterpartyNames[top.key] ?? top.key;
    }

    return {
      'biggestPending': biggestPending == null
          ? 'â‚¹0.00'
          : _formatSelectedCurrencyValue(
              _displayAmountForTransaction(biggestPending),
            ),
      'mostFrequentCounterparty': mostFrequent,
      'thisMonthNetFlow':
          '${monthNet >= 0 ? '+' : '-'}${_formatSelectedCurrencyValue(monthNet.abs())}',
      'averageQuickAmount':
          _formatSelectedCurrencyValue(totalAmount / _quickTransactions.length),
    };
  }

  List<Map<String, dynamic>> _buildQuickBreakdown() {
    final total = _quickTransactions.length.toDouble();
    final lent = _quickTransactions
        .where((t) => _roleForViewer(t) == 'lender')
        .length
        .toDouble();
    final borrowed = total - lent;
    final cleared =
        _quickTransactions.where((t) => t['cleared'] == true).length.toDouble();
    final pending = total - cleared;

    return [
      {'title': 'Lent', 'value': lent},
      {'title': 'Borrowed', 'value': borrowed},
      {'title': 'Cleared', 'value': cleared},
      {'title': 'Pending', 'value': pending},
    ];
  }

  double _secureDisplayAmount(Map<String, dynamic> transaction) {
    final amount = (transaction['amount'] as num?)?.toDouble() ??
        double.tryParse('${transaction['amount']}') ??
        0.0;
    final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final canConvert = _displayCurrencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency.toUpperCase() == targetCurrency);
    return canConvert
        ? (_displayCurrencyData?.convert(amount, sourceCurrency, targetCurrency) ??
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
    if (_secureTransactions.isEmpty) {
      return {
        'largestPending': 'â‚¹0.00',
        'averageRepayment': 'No data',
        'topCounterparty': 'No data',
        'interestMix': '0 with interest / 0 no interest',
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
        ? 'No data'
        : counterpartyCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final averageRepayment = repaymentSamples == 0
        ? 'No data'
        : '${(totalRepaymentDays / repaymentSamples).round()} days avg';
    final noInterest = _secureTransactions.length - withInterest;

    return {
      'largestPending': largestPending == null
          ? 'â‚¹0.00'
          : _formatSelectedCurrencyValue(_secureDisplayAmount(largestPending)),
      'averageRepayment': averageRepayment,
      'topCounterparty': topCounterparty,
      'interestMix': '$withInterest with interest / $noInterest no interest',
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
    final currencies = _secureTransactions
        .map((transaction) => (transaction['currency'] ?? 'INR').toString().toUpperCase())
        .toSet();
    if (currencies.isEmpty) return 'No secure currency data available yet.';
    if (currencies.length == 1) {
      return 'Most secure analytics are based on a single currency: ${currencies.first}.';
    }
    return 'Secure analytics include mixed currencies (${currencies.take(4).join(', ')}), so totals may blend converted and original values.';
  }

  Map<String, String> _buildSecureExtendedInsights() {
    if (_secureTransactions.isEmpty) {
      return {
        'netPosition': 'â‚¹0.00',
        'netPositionSign': '+',
        'partialPaymentRatio': '0%',
        'defaultRate': '0%',
        'avgClearTime': 'No data',
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
        ? 'No data'
        : '${(totalClearDays / clearedCount).round()} days avg';

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
    final cleared = _secureTransactions
        .where((t) =>
            t['userCleared'] == true && t['counterpartyCleared'] == true)
        .length;
    final total = _secureTransactions.length;
    final uncleared = total - cleared;
    if (total == 0) return 'No transactions to forecast.';
    if (uncleared == 0) return 'All transactions cleared! ðŸŽ‰';

    if (cleared == 0) {
      return '$uncleared transactions pending â€” start clearing to see forecast.';
    }

    final now = DateTime.now();
    DateTime? earliest;
    for (final t in _secureTransactions) {
      final d = DateTime.tryParse((t['date'] ?? t['createdAt'] ?? '').toString());
      if (d != null && (earliest == null || d.isBefore(earliest))) {
        earliest = d;
      }
    }
    final months =
        earliest == null ? 1 : ((now.difference(earliest).inDays) / 30).ceil().clamp(1, 120);
    final clearRatePerMonth = cleared / months;
    if (clearRatePerMonth <= 0) return 'Rate too slow to estimate.';

    final monthsNeeded = (uncleared / clearRatePerMonth).ceil();
    final forecastDate = DateTime(now.year, now.month + monthsNeeded);
    final monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final mIdx = ((forecastDate.month - 1) % 12).clamp(0, 11);
    return 'At current pace: ~$uncleared pending cleared by '
        '${monthNames[mIdx]} ${forecastDate.year}';
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
    final spots = _buildQuickTrendSpots();
    final labels = _buildQuickTrendLabels();
    if (spots.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No quick trend data available yet.'),
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
        color: Colors.white,
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
            horizontalInterval: maxY / 4,
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
                interval: maxY / 4,
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
                          color: Colors.grey.shade600,
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
            color: Colors.white,
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          title: const Text(
            'Analytics',
            style: TextStyle(color: Colors.black),
          ),
        ),
      ),
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
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
                color: Color(0xFF00B4D8),
              ),
              const SizedBox(height: 24),
              const Text(
                'Analytics is disabled in your privacy settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Enable analytics sharing to view your secure, quick, and group transaction insights.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
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
                label: const Text(
                  'Open Privacy Settings',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: const Color(0xFF00B4D8),
                ),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: const Color(0xFF00B4D8),
                overlayColor: WidgetStateProperty.all(Colors.transparent),
                tabs: const [
                  Tab(text: 'Secure Trxns'),
                  Tab(text: 'Quick Trxns'),
                  Tab(text: 'Groups Trxns'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTabContent(
                analytics: _secureAnalytics,
                loading: _secureLoading,
                error: _secureError,
                config: const _AnalyticsTabConfig(
                  tabTitle: 'Secure Analytics',
                  tabSubtitle:
                      'See the most important lending and borrowing signals.',
                  metrics: [
                    _MetricDefinition(
                      id: 'totalLent',
                      title: 'Total Lent',
                      subtitle: 'Amount shared by you',
                      icon: Icons.arrow_upward_rounded,
                      colors: [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalBorrowed',
                      title: 'Total Borrowed',
                      subtitle: 'Amount taken by you',
                      icon: Icons.arrow_downward_rounded,
                      colors: [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalInterest',
                      title: 'Interest',
                      subtitle: 'Interest tracked so far',
                      icon: Icons.percent_rounded,
                      colors: [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'cleared',
                      title: 'Cleared',
                      subtitle: 'Fully cleared transactions',
                      icon: Icons.check_circle_outline_rounded,
                      colors: [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    _MetricDefinition(
                      id: 'uncleared',
                      title: 'Uncleared',
                      subtitle: 'Pending transactions',
                      icon: Icons.pending_actions_rounded,
                      colors: [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    _MetricDefinition(
                      id: 'total',
                      title: 'Total Transactions',
                      subtitle: 'All secure records',
                      icon: Icons.receipt_long_rounded,
                      colors: [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    _MetricDefinition(
                      id: 'monthly',
                      title: 'Monthly Activity',
                      subtitle: '12-month transaction trend',
                      icon: Icons.show_chart_rounded,
                      colors: [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
                      isTrend: true,
                    ),
                  ],
                ),
              ),
              _buildTabContent(
                analytics: _quickAnalytics,
                loading: _quickLoading,
                error: _quickError,
                config: const _AnalyticsTabConfig(
                  tabTitle: 'Quick Analytics',
                  tabSubtitle:
                      'Track your fast lending, borrowing, and pending quick records.',
                  metrics: [
                    _MetricDefinition(
                      id: 'totalLent',
                      title: 'Total Lent',
                      subtitle: 'Quick amount shared by you',
                      icon: Icons.flash_on_rounded,
                      colors: [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalBorrowed',
                      title: 'Total Borrowed',
                      subtitle: 'Quick amount taken by you',
                      icon: Icons.bolt_rounded,
                      colors: [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalInterest',
                      title: 'Outstanding',
                      subtitle: 'Uncleared quick amount',
                      icon: Icons.account_balance_wallet_outlined,
                      colors: [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'cleared',
                      title: 'Cleared',
                      subtitle: 'Quick transactions already closed',
                      icon: Icons.check_circle_outline_rounded,
                      colors: [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    _MetricDefinition(
                      id: 'uncleared',
                      title: 'Uncleared',
                      subtitle: 'Quick transactions still open',
                      icon: Icons.pending_actions_rounded,
                      colors: [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    _MetricDefinition(
                      id: 'total',
                      title: 'Total Transactions',
                      subtitle: 'All quick records',
                      icon: Icons.receipt_long_rounded,
                      colors: [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    _MetricDefinition(
                      id: 'monthly',
                      title: 'Monthly Activity',
                      subtitle: '12-month quick trend',
                      icon: Icons.show_chart_rounded,
                      colors: [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
                      isTrend: true,
                    ),
                  ],
                ),
              ),
              _buildTabContent(
                analytics: _groupAnalytics,
                loading: _groupLoading,
                error: _groupError,
                config: const _AnalyticsTabConfig(
                  tabTitle: 'Group Analytics',
                  tabSubtitle:
                      'Track contributions, dues, expenses, and group movement.',
                  metrics: [
                    _MetricDefinition(
                      id: 'totalLent',
                      title: 'Contributed',
                      subtitle: 'What you paid into groups',
                      icon: Icons.volunteer_activism_outlined,
                      colors: [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalBorrowed',
                      title: 'Your Share',
                      subtitle: 'What belongs to you',
                      icon: Icons.pie_chart_outline_rounded,
                      colors: [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'totalInterest',
                      title: 'Outstanding',
                      subtitle: 'Amount still unsettled',
                      icon: Icons.account_balance_wallet_outlined,
                      colors: [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                      isCurrency: true,
                    ),
                    _MetricDefinition(
                      id: 'cleared',
                      title: 'Settled',
                      subtitle: 'Splits already settled',
                      icon: Icons.task_alt_rounded,
                      colors: [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                    ),
                    _MetricDefinition(
                      id: 'uncleared',
                      title: 'Unsettled',
                      subtitle: 'Splits still pending',
                      icon: Icons.hourglass_bottom_rounded,
                      colors: [Color(0xFFFFB562), Color(0xFFFFD9A0)],
                    ),
                    _MetricDefinition(
                      id: 'total',
                      title: 'Expenses',
                      subtitle: 'Tracked group expenses',
                      icon: Icons.receipt_rounded,
                      colors: [Color(0xFF57A4FF), Color(0xFF90C6FF)],
                    ),
                    _MetricDefinition(
                      id: 'totalGroups',
                      title: 'Groups',
                      subtitle: 'Groups included in analytics',
                      icon: Icons.groups_2_outlined,
                      colors: [Color(0xFF7E74F1), Color(0xFFC0BCFF)],
                    ),
                    _MetricDefinition(
                      id: 'monthly',
                      title: 'Monthly Activity',
                      subtitle: '12-month group trend',
                      icon: Icons.show_chart_rounded,
                      colors: [Color(0xFF6B7CFF), Color(0xFFB3BCFF)],
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
    required _AnalyticsTabConfig config,
  }) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
      );
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red[300]!, Colors.orange[400]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                        child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red[400]),
                      ),
                      const SizedBox(height: 16),
                      Text('Oops! Something went wrong',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(error, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.all(2),
                child: ElevatedButton.icon(
                  onPressed: _refreshActiveTab,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4D8),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (analytics == null) {
      return _buildEmptyState(
        icon: Icons.analytics_outlined,
        title: 'No analytics available',
        message: 'We could not find enough data for this tab yet.',
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
                            'Conversion to $_selectedDisplayCurrency is not available for analytics yet. Showing INR values instead.',
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
                  tabTitle: config.tabTitle,
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (config.tabTitle == 'Secure Analytics') ...[
              const SizedBox(height: 4),
              Text(
                'Secure Insights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 10),
              if (_secureTransactionsLoading)
                const SizedBox(
                  height: 110,
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
                  ),
                )
              else if (_secureTransactionsError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Text(
                    _secureTransactionsError!,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSummaryCard(
                        title: 'Largest Pending',
                        value: _buildSecureInsights()['largestPending'] ?? 'â‚¹0.00',
                        icon: Icons.priority_high_rounded,
                        colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          clearanceFilter: 'Totally Uncleared',
                        ),
                      ),
                      _buildSummaryCard(
                        title: 'Repayment Speed',
                        value:
                            _buildSecureInsights()['averageRepayment'] ?? 'No data',
                        icon: Icons.timer_outlined,
                        colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          interestTypeFilter: 'with_interest',
                        ),
                      ),
                      _buildSummaryCard(
                        title: 'Top Counterparty',
                        value: _buildSecureInsights()['topCounterparty'] ?? 'No data',
                        icon: Icons.people_alt_rounded,
                        colors: const [Color(0xFF7C9DFF), Color(0xFFA9B8FF)],
                        useTricolorBorder: true,
                        onTap: () => _openSecureFilteredPage(
                          globalSearch:
                              _buildSecureInsights()['topCounterparty'] == 'No data'
                                  ? ''
                                  : _buildSecureInsights()['topCounterparty']!,
                        ),
                      ),
                      _buildSummaryCard(
                        title: 'Interest Split',
                        value: _buildSecureInsights()['interestMix'] ?? 'No data',
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
                  'Risk / Attention',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
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
                        title: item['title']!.toString(),
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.currency_exchange_rounded,
                        color: Colors.blueGrey.shade600,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _buildSecureCurrencyContext(),
                          style: TextStyle(
                            color: Colors.grey.shade700,
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
                  'Extended Metrics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
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
                          title: 'Net Position',
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
                          title: 'Partial Pay Rate',
                          value: ext['partialPaymentRatio'] ?? '0%',
                          icon: Icons.payments_outlined,
                          colors: const [
                            Color(0xFF7C9DFF),
                            Color(0xFFA9B8FF)
                          ],
                          useTricolorBorder: true,
                        ),
                        _buildSummaryCard(
                          title: 'Default Rate',
                          value: ext['defaultRate'] ?? '0%',
                          icon: Icons.warning_amber_rounded,
                          colors: const [
                            Color(0xFFFF8B7B),
                            Color(0xFFFFC2AE)
                          ],
                          useTricolorBorder: true,
                        ),
                        _buildSummaryCard(
                          title: 'Avg Clear Time',
                          value: ext['avgClearTime'] ?? 'No data',
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
                  'Top Counterparties',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Most active lending/borrowing partners.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final partners = _buildSecureCounterpartyData();
                  if (partners.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('No counterparty data yet.',
                          style: TextStyle(
                              color: Colors.grey.shade500)),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: Colors.grey.shade200),
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
                                backgroundColor: const Color(0xFF00B4D8)
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
                                        '$count txn${count > 1 ? 's' : ''}'
                                        ' Â· $cleared cleared',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500)),
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
                                backgroundColor: Colors.grey.shade200,
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
                          color: Color(0xFFFF9933), width: 2),
                      bottom: const BorderSide(
                          color: Color(0xFF138808), width: 2),
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
                            const Text('Clearance Forecast',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0077B6))),
                            const SizedBox(height: 4),
                            Text(
                              _buildSecureForecastText(),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
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
            ],
            if (config.tabTitle == 'Group Analytics') ...[
              _buildGroupInsights(),
            ],
            if (config.tabTitle == 'Quick Analytics') ...[
              const SizedBox(height: 4),
              Text(
                'Quick Insights',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 10),
              if (_quickTransactionsLoading)
                const SizedBox(
                  height: 110,
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
                  ),
                )
              else if (_quickTransactionsError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Text(
                    _quickTransactionsError ?? 'Unable to load quick insights.',
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else ...[
                SizedBox(
                  height: 110,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _buildSummaryCard(
                        title: 'Biggest Pending',
                        value:
                            _buildQuickInsights()['biggestPending'] ?? 'â‚¹0.00',
                        icon: Icons.priority_high_rounded,
                        colors: const [Color(0xFFFF8B7B), Color(0xFFFFC2AE)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: 'Frequent Person',
                        value:
                            _buildQuickInsights()['mostFrequentCounterparty'] ??
                                'No data',
                        icon: Icons.person_search_rounded,
                        colors: const [Color(0xFF7E74F1), Color(0xFFC0BCFF)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: 'Month Net Flow',
                        value: _buildQuickInsights()['thisMonthNetFlow'] ??
                            'â‚¹0.00',
                        icon: Icons.swap_vert_circle_rounded,
                        colors: const [Color(0xFF58C4DD), Color(0xFF89E0EF)],
                        useTricolorBorder: true,
                      ),
                      _buildSummaryCard(
                        title: 'Average Amount',
                        value: _buildQuickInsights()['averageQuickAmount'] ??
                            'â‚¹0.00',
                        icon: Icons.analytics_rounded,
                        colors: const [Color(0xFF6BCB91), Color(0xFFA9E4A7)],
                        useTricolorBorder: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Per-Person Ledger',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    (item['name'] ?? item['email'] ?? 'Unknown')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isPositive ? 'You will get' : 'You owe',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
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
                  'Quick Activity Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 12),
                _buildQuickTrendChart(),
                const SizedBox(height: 20),
                Text(
                  'Quick Breakdown',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
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
                    label: const Text('View Quick Transactions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
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
                  'Top Quick Partners',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (context) {
                    final partners = _buildTopQuickPartners();
                    if (partners.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'No partner data is available yet.',
                          style: TextStyle(color: Colors.grey),
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
                                  'Quick interaction',
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
              ],
            ],
            const SizedBox(height: 24),
            Text(
              'Analytics Options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Open any option to view charts and related details.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
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
                tabTitle: config.tabTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    _AnalyticsTabConfig config,
    Map<String, dynamic> analytics,
  ) {
    final total = ((analytics['total'] as num?) ?? 0).toInt();
    final displayCurrency = _hasMissingAnalyticsConversion()
        ? 'INR'
        : _selectedDisplayCurrency.toUpperCase();
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
        color: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  config.tabSubtitle,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.grey.shade600,
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
                    'All monetary values in $displayCurrency',
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
                      'Show In',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _buildCurrencySelector(),
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
                  'Records',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Peak ${peakMonth.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF00B4D8),
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
    required _AnalyticsMetric metric,
    required Map<String, dynamic> analytics,
    required List<_AnalyticsMetric> allMetrics,
    required String tabTitle,
  }) {
    return GestureDetector(
      onTap: () => _openMetricPage(metric, analytics, allMetrics, tabTitle),
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
    required _AnalyticsMetric metric,
    required Map<String, dynamic> analytics,
    required List<_AnalyticsMetric> allMetrics,
    required String tabTitle,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _openMetricPage(metric, analytics, allMetrics, tabTitle),
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
            color: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
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
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_AnalyticsMetric> _buildMetrics(
    List<_MetricDefinition> definitions,
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

      return _AnalyticsMetric(
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
    _AnalyticsMetric metric,
    Map<String, dynamic> analytics,
    List<_AnalyticsMetric> allMetrics,
    String tabTitle,
  ) {
    if (tabTitle == 'Secure Analytics') {
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
        builder: (_) => _AnalyticsDetailPage(
          tabTitle: tabTitle,
          metric: metric,
          analytics: analytics,
          allMetrics: allMetrics,
          selectedDisplayCurrency: _selectedDisplayCurrency,
          displayCurrencyData: _displayCurrencyData,
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
            Icon(icon, color: const Color(0xFF00B4D8), size: 60),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsDetailPage extends StatelessWidget {
  final String tabTitle;
  final _AnalyticsMetric metric;
  final Map<String, dynamic> analytics;
  final List<_AnalyticsMetric> allMetrics;
  final String selectedDisplayCurrency;
  final DisplayCurrencyData? displayCurrencyData;
  final bool hasMissingConversion;

  const _AnalyticsDetailPage({
    required this.tabTitle,
    required this.metric,
    required this.analytics,
    required this.allMetrics,
    required this.selectedDisplayCurrency,
    required this.displayCurrencyData,
    required this.hasMissingConversion,
  });

  @override
  Widget build(BuildContext context) {
    final months = List<String>.from(analytics['months'] ?? const []);
    final monthlyCounts =
        (analytics['monthlyCounts'] as List<dynamic>? ?? const [])
            .map((value) => (value as num).toDouble())
            .toList();
    final total = ((analytics['total'] as num?) ?? 0).toDouble();
    final cleared = ((analytics['cleared'] as num?) ?? 0).toDouble();
    final pending = ((analytics['uncleared'] as num?) ?? 0).toDouble();
    final ratio = total == 0 ? 0.0 : (cleared / total).clamp(0.0, 1.0);

    final secondaryMetrics =
        allMetrics.where((item) => item.id != metric.id).take(2).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          metric.title,
          style: const TextStyle(color: Colors.black),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  colors: metric.colors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: metric.colors.first.withValues(alpha: 0.30),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    metric.displayValue,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    metric.subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      hasMissingConversion
                          ? 'Showing INR values'
                          : 'Showing in ${selectedDisplayCurrency.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasMissingConversion) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F1),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFF6B6B)),
                ),
                child: const Text(
                  'Selected analytics currency is not available yet. Showing INR values instead.',
                  style: TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'Quick Facts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniInfoCard(
                    title: 'Records',
                    value: total.toStringAsFixed(0),
                    color: const Color(0xFF1B58B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniInfoCard(
                    title: 'Completion',
                    value: '${(ratio * 100).toStringAsFixed(0)}%',
                    color: const Color(0xFF00B4D8),
                  ),
                ),
              ],
            ),
            if (secondaryMetrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: secondaryMetrics
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: item == secondaryMetrics.first &&
                                    secondaryMetrics.length > 1
                                ? 12
                                : 0,
                          ),
                          child: _MiniInfoCard(
                            title: item.title,
                            value: item.displayValue,
                            color: item.colors.first,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 22),
            _ChartShell(
              title: "Today's Stats",
              trailing: metric.isTrend
                  ? const Text(
                      '12 months',
                      style: TextStyle(
                        color: Color(0xFF00B4D8),
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LegendDot(
                            color: const Color(0xFF7C9DFF), label: 'Cleared'),
                        const SizedBox(width: 12),
                        _LegendDot(
                            color: const Color(0xFFFF8B7B), label: 'Pending'),
                      ],
                    ),
              child: SizedBox(
                height: 220,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    gridData: FlGridData(
                      show: true,
                      horizontalInterval: 5,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.grey.shade200,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= months.length) {
                              return const SizedBox.shrink();
                            }

                            final label = months[index];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                label.length >= 7 ? label.substring(5) : label,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineBarsData: [
                      _buildPrimaryLine(monthlyCounts),
                      if (!metric.isTrend)
                        _buildSecondaryLine(cleared, pending, months.length),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _ChartShell(
              title: 'Needed Info',
              child: Column(
                children: [
                  _InfoRow(
                    label: metric.title,
                    value: metric.displayValue,
                  ),
                  _InfoRow(
                    label: 'Total Records',
                    value: total.toStringAsFixed(0),
                  ),
                  _InfoRow(
                    label: 'Cleared',
                    value: cleared.toStringAsFixed(0),
                  ),
                  _InfoRow(
                    label: 'Pending',
                    value: pending.toStringAsFixed(0),
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildPrimaryLine(List<double> monthlyCounts) {
    final points = monthlyCounts.isEmpty
        ? [const FlSpot(0, 0)]
        : monthlyCounts
            .asMap()
            .entries
            .map((entry) => FlSpot(entry.key.toDouble(), entry.value))
            .toList();

    return LineChartBarData(
      spots: points,
      isCurved: true,
      color: const Color(0xFF7C9DFF),
      barWidth: 3,
      isStrokeCapRound: true,
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            const Color(0xFF7C9DFF).withValues(alpha: 0.25),
            const Color(0xFF7C9DFF).withValues(alpha: 0.03),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 4,
          color: Colors.white,
          strokeWidth: 2.5,
          strokeColor: const Color(0xFF7C9DFF),
        ),
      ),
    );
  }

  LineChartBarData _buildSecondaryLine(
    double cleared,
    double pending,
    int length,
  ) {
    final count = length <= 0 ? 1 : length;
    final step = count == 1 ? 0.0 : 1.0 / (count - 1);

    final points = List.generate(count, (index) {
      final progress = step * index;
      final value = (cleared * (1 - progress)) + (pending * progress);
      return FlSpot(index.toDouble(), value);
    });

    return LineChartBarData(
      spots: points,
      isCurved: true,
      color: const Color(0xFFFF8B7B),
      barWidth: 2,
      dashArray: const [6, 4],
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF8B7B).withValues(alpha: 0.16),
            const Color(0xFFFF8B7B).withValues(alpha: 0.02),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _MiniInfoCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartShell extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _ChartShell({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _InfoRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : Colors.grey.shade200,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsTabConfig {
  final String tabTitle;
  final String tabSubtitle;
  final List<_MetricDefinition> metrics;

  const _AnalyticsTabConfig({
    required this.tabTitle,
    required this.tabSubtitle,
    required this.metrics,
  });
}

class _MetricDefinition {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool isCurrency;
  final bool isTrend;

  const _MetricDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    this.isCurrency = false,
    this.isTrend = false,
  });
}

class _AnalyticsMetric {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final double value;
  final String displayValue;
  final bool isCurrency;
  final bool isTrend;

  const _AnalyticsMetric({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.value,
    required this.displayValue,
    required this.isCurrency,
    required this.isTrend,
  });
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

