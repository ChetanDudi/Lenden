//This file is to view user transactions
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import 'dart:convert';
import 'dart:math';
import '../../../utils/api_client.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../../utils/display_currency_helper.dart';
import 'secure_transaction_detail_page.dart';
import 'partial_payment_page.dart';
import 'create_secure_transaction_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

const _kSecureCategories = [
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

IconData _secureCatIcon(String? key) {
  final cat = _kSecureCategories.firstWhere((c) => c['key'] == key, orElse: () => _kSecureCategories.last);
  return cat['icon'] as IconData;
}

String _secureCatLabel(String? key) {
  return (_kSecureCategories.firstWhere((c) => c['key'] == key, orElse: () => _kSecureCategories.last)['label'] as String);
}

class UserTransactionsPage extends StatefulWidget {
  final String initialFilter;
  final String initialClearanceFilter;
  final String initialPartialClearedType;
  final String initialInterestTypeFilter;
  final String initialGlobalSearch;
  final bool initialShowFavouritesOnly;

  const UserTransactionsPage({
    Key? key,
    this.initialFilter = 'All',
    this.initialClearanceFilter = 'All',
    this.initialPartialClearedType = 'my',
    this.initialInterestTypeFilter = 'All',
    this.initialGlobalSearch = '',
    this.initialShowFavouritesOnly = false,
  }) : super(key: key);

  @override
  _UserTransactionsPageState createState() => _UserTransactionsPageState();
}

class _UserTransactionsPageState extends State<UserTransactionsPage> {
  List<dynamic> lending = [];
  List<dynamic> borrowing = [];
  int totalTransactions = 0;
  bool loading = true;
  String? error;
  String filter = 'All'; // 'All', 'Lending', 'Borrowing'
  String clearanceFilter =
      'All'; // 'All', 'Totally Cleared', 'Totally Uncleared', 'Partially Cleared'
  String partialClearedType = 'my'; // 'my', 'other'
  DateTime? _startDate;
  DateTime? _endDate;
  double? _minAmount;
  double? _maxAmount;
  // New filter/search state
  String _searchCounterparty = '';
  String _searchPlace = '';
  String _searchTransactionId = '';
  double? _searchAmount;
  String _sortBy = 'Created'; // 'Created', 'Transaction Date', 'Amount', 'Status'
  bool _sortAsc = false;
  final Map<String, Future<Map<String, dynamic>?>> _profileCache = {};

  Future<Map<String, dynamic>?> _getCounterpartyProfile(String email) {
    if (email.isEmpty) return Future.value(null);
    return _profileCache.putIfAbsent(email, () async {
      try {
        final res = await ApiClient.get(
            '/api/users/profile-by-email?email=${Uri.encodeComponent(email)}');
        if (res.statusCode == 200) return jsonDecode(res.body);
      } catch (_) {}
      return null;
    });
  }

  Widget _counterpartyAvatar(String email, {double radius = 18}) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getCounterpartyProfile(email),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        ImageProvider? imageProvider;
        if (profile != null &&
            profile['deactivatedAccount'] != true &&
            profile['profileIsPrivate'] != true) {
          dynamic imgUrl = profile['profileImage'];
          if (imgUrl is Map) imgUrl = imgUrl['url'];
          if (imgUrl is String && imgUrl.isNotEmpty && imgUrl != 'null') {
            imageProvider = NetworkImage(imgUrl);
          } else {
            final gender = (profile['gender'] ?? 'Other').toString();
            imageProvider = AssetImage(gender == 'Male'
                ? 'assets/Male.png'
                : gender == 'Female'
                    ? 'assets/Female.png'
                    : 'assets/Other.png');
          }
        }
        return CircleAvatar(
          radius: radius,
          backgroundColor: Colors.teal.shade100,
          backgroundImage: imageProvider,
          child: imageProvider == null
              ? Icon(Icons.person, color: Colors.teal, size: radius * 1.2)
              : null,
        );
      },
    );
  }

  Widget _currentUserAvatar({double radius = 18}) {
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final imgUrl = user?['profileImage'];
    ImageProvider? imageProvider;
    if (imgUrl is String && imgUrl.isNotEmpty && imgUrl != 'null') {
      imageProvider = NetworkImage(imgUrl);
    } else {
      final gender = (user?['gender'] ?? 'Other').toString();
      imageProvider = AssetImage(gender == 'Male'
          ? 'assets/Male.png'
          : gender == 'Female'
              ? 'assets/Female.png'
              : 'assets/Other.png');
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.teal.shade100,
      backgroundImage: imageProvider,
    );
  }

  String interestTypeFilter = 'All'; // 'All', 'simple', 'compound'
  String globalSearch = '';
  final TextEditingController _globalSearchController = TextEditingController();

  final TextEditingController _counterpartyController = TextEditingController();
  final TextEditingController _placeController = TextEditingController();
  final TextEditingController _transactionIdController =
      TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  bool showAllTransactions = false;
  bool showFavouritesOnly = false;
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
  String? _displayCurrencyError;
  Timer? _countdownTimer;
  Timer? _searchDebounceTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    clearanceFilter = widget.initialClearanceFilter;
    partialClearedType = widget.initialPartialClearedType;
    interestTypeFilter = widget.initialInterestTypeFilter;
    globalSearch = widget.initialGlobalSearch;
    showFavouritesOnly = widget.initialShowFavouritesOnly;
    fetchTransactions();
    _loadDisplayCurrencies();
    _counterpartyController.text = _searchCounterparty;
    _placeController.text = _searchPlace;
    _transactionIdController.text = _searchTransactionId;
    _amountController.text = _searchAmount?.toString() ?? '';
    _globalSearchController.text = globalSearch;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _counterpartyController.dispose();
    _placeController.dispose();
    _transactionIdController.dispose();
    _amountController.dispose();
    _globalSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadDisplayCurrencies() async {
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = data;
        _displayCurrencyError = null;
        if (!data.currencies.any(
          (item) => item['code'] == _selectedDisplayCurrency,
        )) {
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

  Widget _buildErrorState(String message, VoidCallback onRetry) {
    final t = AppLocalizations.of(context).t;
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
                decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                      child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red[400]),
                    ),
                    const SizedBox(height: 16),
                    Text(t('oops_something_went_wrong_message'),
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context))),
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
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(t('retry_label'), style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
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

  String _formatDisplayAmount(num? amount, String? originalCurrency) {
    final numericAmount = (amount ?? 0).toDouble();
    final sourceCurrency = (originalCurrency ?? 'INR').toUpperCase();
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    final canConvert = _displayCurrencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency == targetCurrency);
    if (!canConvert) {
      final originalSymbol =
          _displayCurrencyData?.symbolFor(sourceCurrency) ?? sourceCurrency;
      return '$originalSymbol${numericAmount.toStringAsFixed(2)} $sourceCurrency';
    }
    final converted = _displayCurrencyData?.convert(
          numericAmount,
          sourceCurrency,
          targetCurrency,
        ) ??
        numericAmount;
    final symbol =
        _displayCurrencyData?.symbolFor(targetCurrency) ?? targetCurrency;
    return '$symbol${converted.toStringAsFixed(2)} $targetCurrency';
  }

  bool _hasMissingConversionForSecureTransactions() {
    if (_selectedDisplayCurrency.toUpperCase() == 'INR') return false;
    if (_displayCurrencyData == null) return true;
    final allTransactions = [...lending, ...borrowing];
    for (final transaction in allTransactions) {
      final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
      if (!_displayCurrencyData!.canConvert(
        sourceCurrency,
        _selectedDisplayCurrency,
      )) {
        return true;
      }
    }
    return false;
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
            borderRadius: BorderRadius.circular(14),
            items: currencies
                .map(
                  (currency) => DropdownMenuItem(
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

  Future<void> fetchTransactions() async {
    // Yield once so any caller invoking this directly from initState() never
    // touches AppLocalizations.of(context) before initState() has returned.
    await Future.value();
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    setState(() {
      loading = true;
      error = null;
    });
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    if (email == null) {
      setState(() {
        error = t('user_email_not_found_message');
        loading = false;
      });
      return;
    }
    try {
      // Build query params from current filter state
      final params = <String, String>{
        'email': email,
      };

      // Filter (lending/borrowing/all)
      if (filter != 'All') {
        params['filter'] = filter.toLowerCase();
      }

      // Clearance filter
      if (clearanceFilter != 'All') {
        final clearanceMap = {
          'Totally Cleared': 'totally_cleared',
          'Totally Uncleared': 'totally_uncleared',
          'Partially Cleared': 'partially_cleared',
        };
        params['clearanceFilter'] = clearanceMap[clearanceFilter] ?? 'all';
        if (clearanceFilter == 'Partially Cleared') {
          params['partialClearedType'] = partialClearedType;
        }
      }

      // Interest type filter
      if (interestTypeFilter != 'All') {
        params['interestTypeFilter'] = interestTypeFilter;
      }

      // Date range
      if (_startDate != null) {
        params['startDate'] = _startDate!.toIso8601String();
      }
      if (_endDate != null) {
        params['endDate'] = _endDate!.toIso8601String();
      }

      // Amount range
      if (_minAmount != null) {
        params['minAmount'] = _minAmount!.toString();
      }
      if (_maxAmount != null) {
        params['maxAmount'] = _maxAmount!.toString();
      }

      // Global search
      if (globalSearch.isNotEmpty) {
        params['search'] = globalSearch;
      }

      // Sort
      final sortByMap = {
        'Created': 'created',
        'Transaction Date': 'transaction_date',
        'Amount': 'amount',
        'Status': 'status',
      };
      params['sortBy'] = sortByMap[_sortBy] ?? 'created';
      params['sortOrder'] = _sortAsc ? 'asc' : 'desc';

      // Favourites only
      if (showFavouritesOnly) {
        params['favouritesOnly'] = 'true';
      }

      final queryString = params.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final res = await ApiClient.get('/api/transactions/user?$queryString');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          lending = data['lending'] ?? [];
          borrowing = data['borrowing'] ?? [];
          totalTransactions = data['totalTransactions'] ?? 0;
          loading = false;
        });
      } else {
        setState(() {
          error = t('failed_to_load_transactions_message');
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = t('unable_to_connect_check_internet_message');
        loading = false;
      });
    }
  }

  Widget _buildTransactionCard(Map t, bool isLending) {
    final tr = AppLocalizations.of(context).t;
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    final userEmail = t['userEmail'];
    // Determine the counterparty email based on current user's role
    final counterpartyEmail =
        (email == userEmail) ? t['counterpartyEmail'] : userEmail;
    // Use creator identity — not isLending — to map cleared fields correctly.
    // userCleared = creator's status, counterpartyCleared = other party's status.
    final isCreator = (email != null && email == userEmail);
    bool youCleared =
        (isCreator ? t['userCleared'] : t['counterpartyCleared']) == true;
    bool otherCleared =
        (isCreator ? t['counterpartyCleared'] : t['userCleared']) == true;
    bool fullyCleared = youCleared && otherCleared;
    final hasPartialPayment = _hasPartialPayment(Map<String, dynamic>.from(t));
    final expectedReturnDate =
        DateTime.tryParse((t['expectedReturnDate'] ?? '').toString());
    final now = _now;
    final isOverdue = expectedReturnDate != null &&
        expectedReturnDate.isBefore(now) &&
        !fullyCleared;
    final isDueSoon = expectedReturnDate != null &&
        !isOverdue &&
        expectedReturnDate.difference(now).inDays >= 0 &&
        expectedReturnDate.difference(now).inDays <= 7 &&
        !fullyCleared;
    String dateStr =
        t['date'] != null ? t['date'].toString().substring(0, 10) : '';
    String timeStr = t['time'] != null ? t['time'].toString() : '';
    Color borderColor = fullyCleared
        ? Colors.green
        : hasPartialPayment
            ? Colors.purple
            : (youCleared || otherCleared)
                ? Colors.orange
                : Colors.teal;

    // Tap card to open detail page
    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SecureTransactionDetailPage(
              transaction: Map<String, dynamic>.from(t),
              isLending: isLending,
            ),
          ),
        );
        if (mounted) fetchTransactions();
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
        border: Border(
          left: BorderSide(color: borderColor, width: 6),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Column(
            children: [
              // Main content (always visible)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date and time row (tap card to open full details)
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            color: Colors.blue, size: 18),
                        SizedBox(width: 6),
                        Text('${tr('date')}: $dateStr',
                            style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                        SizedBox(width: 10),
                        Icon(Icons.access_time,
                            color: Colors.deepPurple, size: 18),
                        SizedBox(width: 6),
                        Text('${tr('time')}: $timeStr',
                            style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                        Spacer(),
                        Icon(Icons.chevron_right, color: Colors.teal, size: 20),
                      ],
                    ),
                    SizedBox(height: 10),
                    // Header with expand/collapse arrow
                    Row(
                      children: [
                        Icon(
                            isLending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            color: isLending ? Colors.green : Colors.orange,
                            size: 28),
                        if (t['isPartiallyPaid'] == true) ...[
                          SizedBox(width: 4),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tr('partial_label'),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(width: 10),
                        _currentUserAvatar(radius: 18),
                        SizedBox(width: 10),
                        Text(
                          isLending
                              ? tr('lending_you_gave_money_label')
                              : tr('borrowing_you_took_money_label'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isLending ? Colors.green : Colors.orange,
                              fontSize: 16),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    // Counterparty info (always visible)
                    Row(
                      children: [
                        _counterpartyAvatar(counterpartyEmail?.toString() ?? '',
                            radius: 14),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('${tr('counterparty_label')}: $counterpartyEmail',
                              style:
                                  TextStyle(fontSize: 15, color: AppThemeColors.primaryText(context)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    // Amount (always visible - most important)
                    Row(
                      children: [
                        Icon(Icons.attach_money, color: Colors.green, size: 20),
                        SizedBox(width: 6),
                        Text(
                          '${tr('amount')}: ${_formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString())}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700]),
                        ),
                      ],
                    ),
                        if (expectedReturnDate != null && !fullyCleared) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isOverdue
                                  ? Colors.red.withValues(alpha: 0.10)
                                  : isDueSoon
                                      ? Colors.amber.withValues(alpha: 0.14)
                                      : Colors.teal.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isOverdue
                                    ? Colors.red.withValues(alpha: 0.24)
                                    : isDueSoon
                                        ? Colors.amber.withValues(alpha: 0.28)
                                        : Colors.teal.withValues(alpha: 0.22),
                              ),
                            ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOverdue
                                  ? Icons.warning_amber_rounded
                                  : Icons.schedule_rounded,
                                  size: 16,
                                  color: isOverdue
                                      ? Colors.red.shade700
                                      : isDueSoon
                                          ? Colors.orange.shade800
                                          : Colors.teal.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _remainingTimeLabel(expectedReturnDate),
                                  style: TextStyle(
                                    color: isOverdue
                                        ? Colors.red.shade700
                                        : isDueSoon
                                            ? Colors.orange.shade800
                                            : Colors.teal.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: 6),
                    // Status indicator (always visible)
                    SizedBox(height: 8),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: fullyCleared
                            ? Colors.green.withValues(alpha: 0.1)
                            : hasPartialPayment
                                ? Colors.purple.withValues(alpha: 0.1)
                                : (youCleared || otherCleared)
                                    ? Colors.orange.withValues(alpha: 0.1)
                                    : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border(
                          left: BorderSide(color: borderColor, width: 6),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            fullyCleared
                                ? Icons.verified
                                : hasPartialPayment
                                    ? Icons.account_balance_wallet_outlined
                                    : (youCleared || otherCleared)
                                        ? Icons.check
                                        : Icons.hourglass_empty,
                            color: fullyCleared
                                ? Colors.green
                                : hasPartialPayment
                                    ? Colors.purple
                                    : (youCleared || otherCleared)
                                        ? Colors.orange
                                        : Colors.grey,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            fullyCleared
                                ? tr('fully_cleared_label')
                                : hasPartialPayment
                                    ? tr('partially_paid_or_cleared_label')
                                    : (youCleared && !otherCleared)
                                        ? tr('you_cleared_label')
                                        : (!youCleared && otherCleared)
                                            ? tr('other_cleared_label')
                                            : tr('uncleared_label'),
                            style: TextStyle(
                              color: fullyCleared
                                  ? Colors.green
                                  : hasPartialPayment
                                      ? Colors.purple
                                      : (youCleared || otherCleared)
                                          ? Colors.orange
                                          : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.22)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_secureCatIcon((t['category'] ?? 'other').toString()), size: 14, color: Colors.deepPurple),
                          const SizedBox(width: 5),
                          Text(
                            _secureCatLabel((t['category'] ?? 'other').toString()),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.deepPurple),
                          ),
                        ],
                      ),
                    ),
                    if (!fullyCleared && !isLending) ...[
                      const SizedBox(height: 6),
                      Builder(builder: (context) {
                        final double dueAmt = _calculateRemainingWithInterest(t);
                        final bool hasInterest = t['interestType'] != null && t['interestRate'] != null;
                        final String txSymbol = _displayCurrencyData?.symbolFor(
                              (t['currency'] ?? 'INR').toString(),
                            ) ?? currencySymbolFor(t['currency'] as String?);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.payments_outlined, size: 14,
                                    color: hasInterest ? Colors.deepOrange : Colors.teal),
                                const SizedBox(width: 4),
                                Text(
                                  '${tr('amount_due_label')}: $txSymbol${dueAmt.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: hasInterest ? Colors.deepOrange : Colors.teal,
                                  ),
                                ),
                                if (hasInterest) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '(${t['interestType']} ${t['interestRate']}% ${tr('interest_label').toLowerCase()})',
                                    style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.account_balance_wallet_rounded, size: 16, color: Colors.white),
                                label: Text(
                                  '${tr('pay_now_label')}  •  $txSymbol${dueAmt.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyan,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                onPressed: () async {
                                  final double remaining = _calculateRemainingWithInterest(t);
                                  if (remaining <= 0) return;
                            // "Pay Now" is the same two-sided-OTP, real-wallet-transfer
                            // flow as Partial Payment — pre-filled with the full
                            // remaining amount — so there's exactly one payment path.
                            final result = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PartialPaymentPage(
                                  transaction: Map<String, dynamic>.from(t),
                                  isFullPayment: true,
                                ),
                              ),
                            );
                            if (result == true) fetchTransactions();
                          },
                        ),
                      ),
                          ],     // Column.children
                        );     // return Column(...)
                      }),      // Builder
                    ],         // if spread
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    ),  // closes Container
    );  // closes GestureDetector
  }



  int _activeFilterCount() {
    int count = 0;
    if (filter != 'All') count++;
    if (showFavouritesOnly) count++;
    if (clearanceFilter != 'All') count++;
    if (interestTypeFilter != 'All') count++;
    if (_startDate != null || _endDate != null) count++;
    if (_minAmount != null || _maxAmount != null) count++;
    return count;
  }

  Widget _buildFilterToolbar() {
    final t = AppLocalizations.of(context).t;
    final activeCount = _activeFilterCount();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: 28),
              child: Row(
                children: [
                  _buildPrimaryFilterTab(
                    label: t('all'),
                    selected: filter == 'All',
                    accentColor: AppColors.cyan,
                    onTap: () { setState(() => filter = 'All'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildPrimaryFilterTab(
                    label: t('lending_label'),
                    selected: filter == 'Lending',
                    accentColor: Colors.green,
                    onTap: () { setState(() => filter = 'Lending'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildPrimaryFilterTab(
                    label: t('borrowing_label'),
                    selected: filter == 'Borrowing',
                    accentColor: Colors.orange,
                    onTap: () { setState(() => filter = 'Borrowing'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildToolbarAction(
                    icon: showFavouritesOnly
                        ? Icons.favorite
                        : Icons.favorite_border,
                    label: t('fav_label'),
                    accentColor: Colors.red,
                    isActive: showFavouritesOnly,
                    onTap: () {
                      setState(() => showFavouritesOnly = !showFavouritesOnly);
                      fetchTransactions();
                    },
                  ),
                  const SizedBox(width: 10),
                  _buildToolbarAction(
                    icon: Icons.tune_rounded,
                    label:
                        activeCount > 0 ? t('filters_count_label').replaceFirst('{count}', '$activeCount') : t('filters_label'),
                    accentColor: AppColors.cyan,
                    isActive: activeCount > 0,
                    onTap: _showFiltersBottomSheet,
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 34,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppThemeColors.scaffoldBg(context).withValues(alpha: 0.0),
                    AppThemeColors.scaffoldBg(context).withValues(alpha: 0.86),
                    AppThemeColors.scaffoldBg(context),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '->',
                  style: TextStyle(
                    color: AppThemeColors.mutedText(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryFilterTab({
    required String label,
    required bool selected,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        constraints: BoxConstraints(minWidth: label.length > 8 ? 112 : 74),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? accentColor.withValues(alpha: 0.32)
                : Colors.grey.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? accentColor : AppThemeColors.secondaryText(context),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarAction({
    required IconData icon,
    required String label,
    required Color accentColor,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? accentColor.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? accentColor.withValues(alpha: 0.38)
                : Colors.grey.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accentColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<DateTime?> _showStyledDatePicker({
    required DateTime initialDate,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.cyan,
              onPrimary: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.cyan,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> _showFiltersBottomSheet() async {
    final t = AppLocalizations.of(context).t;
    String tempClearanceFilter = 'All';
    String tempInterestTypeFilter = 'All';
    String tempSortBy = 'Created';
    bool tempSortAsc = false;
    DateTime? tempStartDate;
    DateTime? tempEndDate;
    double? tempMinAmount;
    double? tempMaxAmount;

    final minAmountController = TextEditingController();
    final maxAmountController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            Future<void> pickDate(bool isStart) async {
              final picked = await _showStyledDatePicker(
                initialDate: isStart
                    ? (tempStartDate ?? DateTime.now())
                    : (tempEndDate ?? DateTime.now()),
              );
              if (picked == null) return;
              modalSetState(() {
                if (isStart) {
                  tempStartDate = picked;
                } else {
                  tempEndDate = picked;
                }
              });
            }

            Widget sectionTitle(String title, String subtitle) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppThemeColors.mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }

            String clearanceFilterLabel(String value) {
              switch (value) {
                case 'Totally Cleared':
                  return t('totally_cleared_label');
                case 'Totally Uncleared':
                  return t('totally_uncleared_label');
                case 'Partially Cleared':
                  return t('partially_cleared_label');
                default:
                  return t('all');
              }
            }

            String sortByLabel(String value) {
              switch (value) {
                case 'Transaction Date':
                  return t('transaction_date_label');
                case 'Amount':
                  return t('amount');
                case 'Status':
                  return t('status_label');
                default:
                  return t('created_label');
              }
            }

            Widget tricolorSection({
              required Widget child,
              required Color backgroundColor,
            }) {
              return Container(
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
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: child,
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
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
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4FBFE),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.tune_rounded,
                                      color: AppColors.cyan),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t('refine_transactions_title'),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppThemeColors.primaryText(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        t('refine_transactions_subtitle_message'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppThemeColors.mutedText(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          tricolorSection(
                            backgroundColor: const Color(0xFFF8FBFD),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  t('clearance_status_label'),
                                  t('clearance_status_subtitle_message'),
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      'All',
                                      'Totally Cleared',
                                      'Totally Uncleared',
                                      'Partially Cleared',
                                    ]
                                        .map(
                                          (value) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text(clearanceFilterLabel(value)),
                                              selected:
                                                  tempClearanceFilter == value,
                                              onSelected: (_) {
                                                modalSetState(() {
                                                  tempClearanceFilter = value;
                                                });
                                              },
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          tricolorSection(
                            backgroundColor: const Color(0xFFFFFCF7),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  t('interest_type_label'),
                                  t('interest_type_subtitle_message'),
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      {'label': t('all'), 'value': 'All'},
                                      {
                                        'label': t('simple_interest_label'),
                                        'value': 'simple'
                                      },
                                      {
                                        'label': t('compound_interest_label'),
                                        'value': 'compound'
                                      },
                                      {
                                        'label': t('with_interest_label'),
                                        'value': 'with_interest'
                                      },
                                    ]
                                        .map(
                                          (item) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text(item['label']!),
                                              selected:
                                                  tempInterestTypeFilter ==
                                                      item['value'],
                                              onSelected: (_) {
                                                modalSetState(() {
                                                  tempInterestTypeFilter =
                                                      item['value']!;
                                                });
                                              },
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          tricolorSection(
                            backgroundColor: const Color(0xFFF7F9FD),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  t('sort_transactions_label'),
                                  t('sort_transactions_subtitle_message'),
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      'Created',
                                      'Transaction Date',
                                      'Amount',
                                      'Status',
                                    ]
                                        .map(
                                          (value) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text(sortByLabel(value)),
                                              selected: tempSortBy == value,
                                              onSelected: (_) {
                                                modalSetState(() {
                                                  tempSortBy = value;
                                                });
                                              },
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      {
                                        'label': t('newest_first_label'),
                                        'value': false,
                                      },
                                      {
                                        'label': t('oldest_first_label'),
                                        'value': true,
                                      },
                                    ]
                                        .map(
                                          (item) => Padding(
                                            padding:
                                                const EdgeInsets.only(right: 8),
                                            child: ChoiceChip(
                                              label: Text(
                                                  item['label'].toString()),
                                              selected: tempSortAsc ==
                                                  item['value'] as bool,
                                              onSelected: (_) {
                                                modalSetState(() {
                                                  tempSortAsc =
                                                      item['value'] as bool;
                                                });
                                              },
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          tricolorSection(
                            backgroundColor: const Color(0xFFF7FBF8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  t('date_range_label'),
                                  t('date_range_subtitle_message'),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => pickDate(true),
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: t('start_date_label'),
                                            border: InputBorder.none,
                                            isDense: true,
                                            prefixIcon: const Icon(
                                              Icons.calendar_today,
                                              color: AppColors.cyan,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                tempStartDate == null
                                                    ? t('any_label')
                                                    : DateFormat('yyyy-MM-dd')
                                                        .format(tempStartDate!),
                                              ),
                                              const Icon(Icons.calendar_today,
                                                  color: Colors.teal),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => pickDate(false),
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: t('end_date_label'),
                                            border: InputBorder.none,
                                            isDense: true,
                                            prefixIcon: const Icon(
                                              Icons.calendar_today,
                                              color: AppColors.cyan,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                tempEndDate == null
                                                    ? t('any_label')
                                                    : DateFormat('yyyy-MM-dd')
                                                        .format(tempEndDate!),
                                              ),
                                              const Icon(Icons.calendar_today,
                                                  color: Colors.teal),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          tricolorSection(
                            backgroundColor: const Color(0xFFF9F7FC),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionTitle(
                                  t('amount_range_label'),
                                  t('amount_range_subtitle_message'),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: minAmountController,
                                        decoration: InputDecoration(
                                          labelText: t('min_amount_label'),
                                          filled: true,
                                          fillColor: AppThemeColors.cardBg(context),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          isDense: true,
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        onChanged: (val) {
                                          tempMinAmount = double.tryParse(val);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: maxAmountController,
                                        decoration: InputDecoration(
                                          labelText: t('max_amount_label'),
                                          filled: true,
                                          fillColor: AppThemeColors.cardBg(context),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          isDense: true,
                                        ),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(
                                          decimal: true,
                                        ),
                                        onChanged: (val) {
                                          tempMaxAmount = double.tryParse(val);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
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
                                  child: OutlinedButton(
                                    onPressed: () {
                                      modalSetState(() {
                                        tempClearanceFilter = 'All';
                                        tempInterestTypeFilter = 'All';
                                        tempSortBy = 'Created';
                                        tempSortAsc = false;
                                        tempStartDate = null;
                                        tempEndDate = null;
                                        tempMinAmount = null;
                                        tempMaxAmount = null;
                                        minAmountController.clear();
                                        maxAmountController.clear();
                                      });
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: AppThemeColors.cardBg(context),
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    child: Text(
                                      t('clear_sheet_label'),
                                      style: const TextStyle(
                                        color: Color(0xFF0077B6),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
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
                                  child: ElevatedButton(
                                    onPressed: () {
                                      setState(() {
                                        clearanceFilter = tempClearanceFilter;
                                        interestTypeFilter =
                                            tempInterestTypeFilter;
                                        _sortBy = tempSortBy;
                                        _sortAsc = tempSortAsc;
                                        _startDate = tempStartDate;
                                        _endDate = tempEndDate;
                                        _minAmount = tempMinAmount;
                                        _maxAmount = tempMaxAmount;
                                      });
                                      Navigator.pop(context);
                                      fetchTransactions();
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.cyan,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    child: Text(
                                      t('apply_filters_label'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFilterSummary() {
    final t = AppLocalizations.of(context).t;
    String clearanceLabel(String value) {
      switch (value) {
        case 'Totally Cleared':
          return t('totally_cleared_label');
        case 'Totally Uncleared':
          return t('totally_uncleared_label');
        case 'Partially Cleared':
          return t('partially_cleared_label');
        default:
          return t('all');
      }
    }
    String sortByDisplayLabel(String value) {
      switch (value) {
        case 'Transaction Date':
          return t('transaction_date_label');
        case 'Amount':
          return t('amount');
        case 'Status':
          return t('status_label');
        default:
          return t('created_label');
      }
    }
    final chips = <Map<String, dynamic>>[];
    if (filter != 'All') {
      chips.add({
        'label': filter == 'Lending' ? t('lending_label') : t('borrowing_label'),
        'color': filter == 'Lending' ? Colors.green : Colors.orange,
      });
    }
    if (showFavouritesOnly) {
      chips.add({'label': t('favourites_label'), 'color': Colors.red});
    }
    if (clearanceFilter != 'All') {
      chips.add({
        'label': clearanceLabel(clearanceFilter),
        'color': clearanceFilter == 'Totally Cleared'
            ? Colors.green
            : clearanceFilter == 'Totally Uncleared'
                ? Colors.orange
                : Colors.blue,
      });
    }
    if (interestTypeFilter != 'All') {
      chips.add({
        'label': interestTypeFilter == 'with_interest'
            ? t('with_interest_label')
            : interestTypeFilter == 'simple'
                ? t('simple_interest_label')
                : t('compound_interest_label'),
        'color': interestTypeFilter == 'simple'
            ? Colors.green
            : interestTypeFilter == 'compound'
                ? Colors.blue
                : Colors.purple,
      });
    }
    if (_startDate != null || _endDate != null) {
      chips.add({
        'label':
            '${t('dates_label')}: ${_startDate == null ? t('any_label') : DateFormat('MMM d').format(_startDate!)} - ${_endDate == null ? t('any_label') : DateFormat('MMM d').format(_endDate!)}',
        'color': AppColors.cyan,
      });
    }
    if (_minAmount != null || _maxAmount != null) {
      chips.add({
        'label':
            '${t('amount')}: ${_minAmount?.toStringAsFixed(0) ?? t('any_label')} - ${_maxAmount?.toStringAsFixed(0) ?? t('any_label')}',
        'color': const Color(0xFF7C4DFF),
      });
    }
    if (_sortBy != 'Created' || _sortAsc != false) {
      chips.add({
        'label':
            '${t('sort_label')}: ${sortByDisplayLabel(_sortBy)} • ${_sortAsc ? t('oldest_first_label') : t('newest_first_label')}',
        'color': const Color(0xFF1565C0),
      });
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined,
                    size: 18, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(
                  t('active_filters_label'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(t('reset_label')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips
                  .map(
                    (chip) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (chip['color'] as Color).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (chip['color'] as Color).withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        chip['label'] as String,
                        style: TextStyle(
                          color: chip['color'] as Color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return filter != 'All' ||
        clearanceFilter != 'All' ||
        _startDate != null ||
        _endDate != null ||
        _minAmount != null ||
        _maxAmount != null ||
        _searchCounterparty.isNotEmpty ||
        _searchPlace.isNotEmpty ||
        _searchTransactionId.isNotEmpty ||
        _searchAmount != null ||
        globalSearch.isNotEmpty ||
        interestTypeFilter != 'All' ||
        showFavouritesOnly ||
        _sortBy != 'Created' ||
        _sortAsc != false;
  }

  void _resetFilters() {
    setState(() {
      filter = 'All';
      clearanceFilter = 'All';
      partialClearedType = 'my';
      _startDate = null;
      _endDate = null;
      _minAmount = null;
      _maxAmount = null;
      _searchCounterparty = '';
      _searchPlace = '';
      _searchTransactionId = '';
      _searchAmount = null;
      _sortBy = 'Created';
      _sortAsc = false;
      interestTypeFilter = 'All';
      globalSearch = '';
      showFavouritesOnly = false;
      showAllTransactions = false;
      _counterpartyController.clear();
      _placeController.clear();
      _transactionIdController.clear();
      _amountController.clear();
      _globalSearchController.clear();
    });
    fetchTransactions();
  }



  // Returns the amount still owed: remaining principal + accrued interest.
  // Returns 0 if fully cleared.
  double _calculateRemainingWithInterest(Map t) {
    if (t['userCleared'] == true && t['counterpartyCleared'] == true) return 0.0;
    final double original = (t['amount'] as num?)?.toDouble() ?? 0.0;
    double paid = 0.0;
    if (t['isPartiallyPaid'] == true && t['partialPayments'] is List) {
      final pp = t['partialPayments'] as List;
      paid = pp.fold<double>(0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0.0));
    }
    double remaining = (original - paid).clamp(0.0, double.infinity);
    if (remaining <= 0) return 0.0;
    if (t['interestType'] != null && t['interestRate'] != null) {
      final txDate = DateTime.tryParse((t['date'] ?? '').toString());
      if (txDate != null) {
        final days = DateTime.now().difference(txDate).inDays;
        if (days > 0) {
          final rate = (t['interestRate'] as num).toDouble();
          if (t['interestType'] == 'simple') {
            remaining = remaining + (remaining * rate * days / 365);
          } else if (t['interestType'] == 'compound') {
            final n = (t['compoundingFrequency'] as num?)?.toInt() ?? 1;
            remaining = remaining * pow(1 + (rate / 100) / n, n * (days / 365.0));
          }
        }
      }
    }
    return remaining;
  }

  bool _hasPartialPayment(Map t) {
    final partialPayments = t['partialPayments'];
    return t['isPartiallyPaid'] == true ||
        (partialPayments is List && partialPayments.isNotEmpty);
  }





  String _remainingTimeLabel(DateTime expectedReturnDate) {
    final t = AppLocalizations.of(context).t;
    final difference = expectedReturnDate.difference(_now);
    if (difference.isNegative) {
      return t('overdue_since_message').replaceFirst('{date}', DateFormat('MMM d').format(expectedReturnDate));
    }
    if (difference.inDays > 0) {
      return t('days_remaining_message').replaceFirst('{count}', '${difference.inDays}');
    }
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    final seconds = difference.inSeconds.remainder(60);
    return t('hms_remaining_message').replaceFirst('{h}', '$hours').replaceFirst('{m}', '$minutes').replaceFirst('{s}', '$seconds');
  }

  // Returns already server-filtered data as-is
  Map<String, List<dynamic>> _getFilteredTransactionBuckets() {
    return {
      'lending': List<dynamic>.from(lending),
      'borrowing': List<dynamic>.from(borrowing),
    };
  }

  Widget _buildStatusLegend() {
    final t = AppLocalizations.of(context).t;
    Widget item(Color color, IconData icon, String label) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          item(Colors.grey, Icons.hourglass_empty, t('uncleared_label')),
          item(Colors.orange, Icons.check_circle_outline, t('you_cleared_label')),
          item(Colors.blue, Icons.people_alt_outlined, t('other_cleared_label')),
          item(Colors.green, Icons.verified, t('fully_cleared_label')),
        ],
      ),
    );
  }

  List<Widget> _buildFilteredTransactionCards({int? limit}) {
    final tr = AppLocalizations.of(context).t;
    List<Widget> widgets = [];
    final buckets = _getFilteredTransactionBuckets();
    final lendingFiltered = List<dynamic>.from(buckets['lending'] ?? const []);
    final borrowingFiltered =
        List<dynamic>.from(buckets['borrowing'] ?? const []);

    var allTransactions = <Map>[];
    if (filter == 'All' || filter == 'Lending') {
      allTransactions.addAll(
        lendingFiltered.map((t) => {'type': 'lending', 'data': t}),
      );
    }
    if (filter == 'All' || filter == 'Borrowing') {
      allTransactions.addAll(
        borrowingFiltered.map((t) => {'type': 'borrowing', 'data': t}),
      );
    }

    List limitedTransactions = allTransactions;
    if (limit != null && allTransactions.length > limit) {
      limitedTransactions = allTransactions.take(limit).toList();
    }

    var finalLending = limitedTransactions
        .where((t) => t['type'] == 'lending')
        .map((t) => t['data'])
        .toList();
    var finalBorrowing = limitedTransactions
        .where((t) => t['type'] == 'borrowing')
        .map((t) => t['data'])
        .toList();

    if (finalLending.isNotEmpty) {
      widgets.add(Text(tr('lending_amount_label'),
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)));
      widgets.add(SizedBox(height: 8));
      widgets.addAll(finalLending.map((t) => _buildTransactionCard(t, true)));
      widgets.add(SizedBox(height: 20));
    }

    if (finalBorrowing.isNotEmpty) {
      widgets.add(Text(tr('borrowing_amount_label'),
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.orange)));
      widgets.add(SizedBox(height: 8));
      widgets
          .addAll(finalBorrowing.map((t) => _buildTransactionCard(t, false)));
    }

    if (widgets.isEmpty) {
      widgets.add(Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                showFavouritesOnly
                    ? Icons.star_border_rounded
                    : Icons.receipt_long,
                size: 80,
                color: AppThemeColors.mutedText(context)),
            const SizedBox(height: 20),
            Text(
              showFavouritesOnly
                  ? tr('no_favourite_transactions_found_message')
                  : tr('no_transactions_found_message'),
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.secondaryText(context)),
            ),
            const SizedBox(height: 10),
            Text(
              showFavouritesOnly
                  ? tr('mark_transaction_favourite_hint_message')
                  : tr('try_adjusting_search_filters_message'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppThemeColors.mutedText(context)),
            ),
            if (_hasActiveFilters()) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _resetFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(tr('reset_filters_label')),
              ),
            ],
          ],
        ),
      ));
    }
    return widgets;
  }

  Future<void> _openCreateSecureTransaction() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
      int? dailyRemaining;
      await Future.wait([
        session.loadFreebieCounts(),
        ApiClient.get('/api/limits/daily').then((res) {
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            dailyRemaining = data['limits']?['userTransactions']?['remaining'];
          }
        }),
      ]);
      if (!mounted) return;
      if (dailyRemaining != null && dailyRemaining! <= 0) {
        showDailyLimitDialog(context,
            message: t('daily_secure_transactions_limit_reached_message'));
        return;
      }
      final freeRemaining = session.freeUserTransactionsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: t('secure_transaction_feature_label'), coinCost: 10, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TransactionPage(useCoins: true)));
        return;
      }
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => TransactionPage()));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context).t;
    final buckets = _getFilteredTransactionBuckets();
    final filteredLending = List<dynamic>.from(buckets['lending'] ?? const []);
    final filteredBorrowing =
        List<dynamic>.from(buckets['borrowing'] ?? const []);

    int totalCount = 0;
    if (filter == 'All' || filter == 'Lending') {
      totalCount += filteredLending.length;
    }
    if (filter == 'All' || filter == 'Borrowing') {
      totalCount += filteredBorrowing.length;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(loc('your_transactions_count_title').replaceFirst('{count}', '$totalTransactions'),
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
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
          Padding(
            padding: EdgeInsets.only(top: context.sh(90)),
            child: loading
          ? Center(child: CircularProgressIndicator())
          : error != null
              ? _buildErrorState(error!, fetchTransactions)
              : RefreshIndicator(
                  onRefresh: fetchTransactions,
                  color: AppColors.cyan,
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Container(
                        padding: const EdgeInsets.all(2), // border width
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.white, Colors.green],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: TextField(
                          controller: _globalSearchController,
                          decoration: InputDecoration(
                            hintText: loc('search_transactions_hint_message'),
                            prefixIcon:
                                Icon(Icons.search, color: AppColors.cyan),
                            filled: true,
                            fillColor: AppThemeColors.cardBg(context),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 0, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) {
                            setState(() => globalSearch = v);
                            _searchDebounceTimer?.cancel();
                            _searchDebounceTimer = Timer(
                              const Duration(milliseconds: 300),
                              fetchTransactions,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildFilterToolbar(),
                    _buildActiveFilterSummary(),
                    _buildStatusLegend(),
                    if (_displayCurrencyError != null ||
                        _hasMissingConversionForSecureTransactions())
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFFF6B6B)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Color(0xFFD62828), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _displayCurrencyError ??
                                      loc('conversion_not_available_secure_message').replaceFirst('{currency}', _selectedDisplayCurrency),
                                  style: const TextStyle(
                                    color: Color(0xFFD62828),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            loc('show_in_label'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 10),
                          _buildCurrencySelector(),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    Column(
                      children: [
                          ..._buildFilteredTransactionCards(
                              limit: showAllTransactions ? null : 3),
                          if (!showAllTransactions && totalCount > 3)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: ElevatedButton(
                                  onPressed: () => setState(
                                      () => showAllTransactions = true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.cyan,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: Text(loc('view_all_transactions_label'),
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 16)),
                                ),
                              ),
                            ),
                          if (showAllTransactions && totalCount > 3)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: ElevatedButton(
                                  onPressed: () => setState(
                                      () => showAllTransactions = false),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppThemeColors.cardBg(context),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: Text(loc('show_less_label'),
                                      style: TextStyle(
                                          color: AppColors.cyan,
                                          fontSize: 16)),
                                ),
                              ),
                            ),
                        ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FloatingActionButton(
          onPressed: _openCreateSecureTransaction,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

}
