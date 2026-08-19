//This file is to view user transactions
import 'package:flutter/material.dart';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../utils/share_utils.dart';
import '../../../utils/pickers.dart';
import '../../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import 'dart:convert';
import 'dart:math';
import '../../../utils/api_client.dart';
import 'dart:async';
import '../../../widgets/currency_display.dart';
import 'secure_transaction_detail_page.dart';
import 'partial_payment_page.dart';
import 'create_secure_transaction_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/budget_limit_banner.dart';
import '../../../widgets/free_attempts_banner.dart';
import '../../../widgets/search_tab_bar.dart';
import '../../budget/budget_messages_page.dart';
import '../../budget/budget_planning_page.dart';

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

class _UserTransactionsPageState extends State<UserTransactionsPage>
    with CurrencyDisplayMixin<UserTransactionsPage> {
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
  int _bannerRefreshTrigger = 0;
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
  int _txnPage = 1;
  bool _txnHasMore = false;
  bool _loadingMore = false;
  static const int _txnPageSize = 20;
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
    loadCurrencies(onError: (_) {
      if (mounted) {
        setState(() => _displayCurrencyError = AppLocalizations.of(context).t('currency_conversion_unavailable_message'));
      }
    });
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


  String _formatDisplayAmount(num? amount, String? originalCurrency) {
    final numericAmount = (amount ?? 0).toDouble();
    final sourceCurrency = (originalCurrency ?? 'INR').toUpperCase();
    final targetCurrency = selectedCurrency.toUpperCase();
    final canConvert = currencyData?.canConvert(
          sourceCurrency,
          targetCurrency,
        ) ??
        (sourceCurrency == targetCurrency);
    if (!canConvert) {
      final originalSymbol =
          currencyData?.symbolFor(sourceCurrency) ?? sourceCurrency;
      return '$originalSymbol${numericAmount.toStringAsFixed(2)} $sourceCurrency';
    }
    final converted = currencyData?.convert(
          numericAmount,
          sourceCurrency,
          targetCurrency,
        ) ??
        numericAmount;
    final symbol =
        currencyData?.symbolFor(targetCurrency) ?? targetCurrency;
    return '$symbol${converted.toStringAsFixed(2)} $targetCurrency';
  }

  bool _hasMissingConversionForSecureTransactions() {
    if (selectedCurrency.toUpperCase() == 'INR') return false;
    if (currencyData == null) return true;
    final allTransactions = [...lending, ...borrowing];
    for (final transaction in allTransactions) {
      final sourceCurrency = (transaction['currency'] ?? 'INR').toString();
      if (!currencyData!.canConvert(
        sourceCurrency,
        selectedCurrency,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> fetchTransactions({bool append = false}) async {
    // Yield once so any caller invoking this directly from initState() never
    // touches AppLocalizations.of(context) before initState() has returned.
    await Future.value();
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    if (append) {
      setState(() => _loadingMore = true);
    } else {
      _txnPage = 1;
      setState(() {
        loading = true;
        error = null;
      });
    }
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

      // Pagination
      final fetchPage = append ? _txnPage + 1 : 1;
      params['page'] = fetchPage.toString();
      params['limit'] = _txnPageSize.toString();

      final queryString = params.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final res = await ApiClient.get('/api/transactions/user?$queryString');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final newLending = List<dynamic>.from(data['lending'] ?? []);
        final newBorrowing = List<dynamic>.from(data['borrowing'] ?? []);
        setState(() {
          if (append) {
            lending = [...lending, ...newLending];
            borrowing = [...borrowing, ...newBorrowing];
            _txnPage = fetchPage;
          } else {
            lending = newLending;
            borrowing = newBorrowing;
            _txnPage = 1;
            showAllTransactions = false;
          }
          totalTransactions = data['totalTransactions'] ?? 0;
          _txnHasMore = data['hasMore'] ?? false;
          loading = false;
          _loadingMore = false;
        });
      } else {
        setState(() {
          error = t('failed_to_load_transactions_message');
          loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        error = t('unable_to_connect_check_internet_message');
        loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (_loadingMore || !_txnHasMore) return;
    await fetchTransactions(append: true);
  }

  bool _isSecureFavourited(Map t) {
    final email = Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return false;
    final favList = t['favourite'];
    return favList is List && favList.contains(email);
  }

  Future<void> _toggleSecureFavourite(Map<String, dynamic> t) async {
    final tid = t['transactionId']?.toString() ?? '';
    if (tid.isEmpty) return;
    final email = Provider.of<SessionProvider>(context, listen: false).user?['email'];
    if (email == null) return;
    final fav = List<dynamic>.from(t['favourite'] is List ? t['favourite'] : []);
    final isFav = fav.contains(email);
    // Optimistic update
    if (isFav) { fav.remove(email); } else { fav.add(email); }
    setState(() {
      for (final list in [lending, borrowing]) {
        final idx = list.indexWhere((tx) => tx['transactionId']?.toString() == tid);
        if (idx != -1) list[idx] = {...Map<String, dynamic>.from(list[idx]), 'favourite': List<dynamic>.from(fav)};
      }
    });
    try {
      final res = await ApiClient.put('/api/transactions/$tid/favourite', body: {'email': email});
      if (res.statusCode != 200 && mounted) {
        // Revert on failure
        if (isFav) { fav.add(email); } else { fav.remove(email); }
        setState(() {
          for (final list in [lending, borrowing]) {
            final idx = list.indexWhere((tx) => tx['transactionId']?.toString() == tid);
            if (idx != -1) list[idx] = {...Map<String, dynamic>.from(list[idx]), 'favourite': List<dynamic>.from(fav)};
          }
        });
      }
    } catch (_) {}
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
                        GestureDetector(
                          onTap: () => _toggleSecureFavourite(Map<String, dynamic>.from(t)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Icon(
                              _isSecureFavourited(t) ? Icons.favorite : Icons.favorite_border,
                              color: _isSecureFavourited(t) ? Colors.redAccent : Colors.grey,
                              size: 20,
                            ),
                          ),
                        ),
                        SizedBox(width: 4),
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
                        Icon(Icons.attach_money,
                            color: isLending ? Colors.green : Colors.red.shade700, size: 20),
                        SizedBox(width: 6),
                        Text(
                          '${tr('amount')}: ${_formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString())}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isLending ? Colors.green[700] : Colors.red.shade700),
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
                        final String txSymbol = currencyData?.symbolFor(
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildMiniFilterChip(
              label: t('all'),
              selected: filter == 'All',
              accentColor: AppColors.cyan,
              onTap: () { setState(() => filter = 'All'); fetchTransactions(); },
            ),
            const SizedBox(width: 6),
            _buildMiniFilterChip(
              label: t('lending_label'),
              selected: filter == 'Lending',
              accentColor: Colors.green,
              onTap: () { setState(() => filter = 'Lending'); fetchTransactions(); },
            ),
            const SizedBox(width: 6),
            _buildMiniFilterChip(
              label: t('borrowing_label'),
              selected: filter == 'Borrowing',
              accentColor: Colors.orange,
              onTap: () { setState(() => filter = 'Borrowing'); fetchTransactions(); },
            ),
            const SizedBox(width: 6),
            _buildMiniFilterChip(
              icon: showFavouritesOnly ? Icons.favorite : Icons.favorite_border,
              label: t('fav_label'),
              selected: showFavouritesOnly,
              accentColor: Colors.red,
              onTap: () { setState(() => showFavouritesOnly = !showFavouritesOnly); fetchTransactions(); },
            ),
            const SizedBox(width: 6),
            _buildMiniFilterChip(
              icon: Icons.tune_rounded,
              label: activeCount > 0 ? t('filters_count_label').replaceFirst('{count}', '$activeCount') : t('filters_label'),
              selected: activeCount > 0,
              accentColor: AppColors.cyan,
              onTap: _showFiltersBottomSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniFilterChip({
    required String label,
    required bool selected,
    required Color accentColor,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accentColor.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: selected ? accentColor : AppThemeColors.secondaryText(context)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? accentColor : AppThemeColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<DateTime?> _showStyledDatePicker({
    required DateTime initialDate,
  }) => showAppDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );

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
    if (!session.hasFeature('secure_transactions')) {
      if (mounted) showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black26,
        builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
      );
      int? dailyRemaining;
      try {
        await Future.wait([
          session.loadFreebieCounts(),
          ApiClient.get('/api/limits/daily').then((res) {
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              dailyRemaining = data['limits']?['userTransactions']?['remaining'];
            }
          }),
        ]);
      } finally {
        if (mounted) Navigator.pop(context);
      }
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
            featureName: t('secure_transaction_feature_label'), coinCost: session.secureTransactionCoinCost, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TransactionPage(useCoins: true)));
        return;
      }
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => TransactionPage()));
    if (mounted) {
      fetchTransactions();
      setState(() => _bannerRefreshTrigger++);
    }
  }

  // ── Monthly Summary ───────────────────────────────────────────────────────
  Widget _buildMonthlySummary() {
    final now = DateTime.now();
    double monthLent = 0, monthBorrowed = 0;
    int lentCount = 0, borrowedCount = 0;
    for (final tx in lending) {
      final d = DateTime.tryParse((tx['date'] ?? tx['createdAt'] ?? '').toString());
      if (d != null && d.year == now.year && d.month == now.month) {
        monthLent += (tx['amount'] as num?)?.toDouble() ?? 0;
        lentCount++;
      }
    }
    for (final tx in borrowing) {
      final d = DateTime.tryParse((tx['date'] ?? tx['createdAt'] ?? '').toString());
      if (d != null && d.year == now.year && d.month == now.month) {
        monthBorrowed += (tx['amount'] as num?)?.toDouble() ?? 0;
        borrowedCount++;
      }
    }
    if (lentCount == 0 && borrowedCount == 0) return const SizedBox.shrink();
    final sym = currencyData?.symbolFor(selectedCurrency.toUpperCase()) ?? '₹';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This Month', style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context), fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('$sym${monthLent.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
          Text('$lentCount lent', style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context))),
        ])),
        Container(width: 1, height: 36, color: AppThemeColors.border(context)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('This Month', style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context), fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('$sym${monthBorrowed.toStringAsFixed(2)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFC62828))),
          Text('$borrowedCount borrowed', style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context))),
        ])),
      ]),
    );
  }

  // ── CSV Export ────────────────────────────────────────────────────────────
  Future<void> _exportCsv() async {
    final allTxns = [...lending, ...borrowing];
    if (allTxns.isEmpty) {
      ElegantNotification.error(
        title: const Text('Nothing to export', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('No transactions to export'),
      ).show(context);
      return;
    }
    final buf = StringBuffer();
    buf.writeln('Amount,Currency,Role,Description,Counterparty,Date,Time,You Cleared,Other Cleared,Expected Return,Overdue');
    String cell(dynamic v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    final userEmail = Provider.of<SessionProvider>(context, listen: false).user?['email'] ?? '';
    for (final tx in allTxns) {
      final isCreator = tx['userEmail']?.toString() == userEmail;
      final youCleared = (isCreator ? tx['userCleared'] : tx['counterpartyCleared']) == true;
      final otherCleared = (isCreator ? tx['counterpartyCleared'] : tx['userCleared']) == true;
      final counterparty = isCreator ? tx['counterpartyEmail'] : tx['userEmail'];
      final isLending = lending.contains(tx);
      final expectedReturn = (tx['expectedReturnDate'] ?? '').toString().split('T').first;
      final expectedDt = DateTime.tryParse((tx['expectedReturnDate'] ?? '').toString());
      final isOverdue = expectedDt != null && expectedDt.isBefore(DateTime.now()) && !youCleared;
      buf.writeln([
        cell(tx['amount']),
        cell(tx['currency'] ?? 'INR'),
        cell(isLending ? 'Lending' : 'Borrowing'),
        cell(tx['description']),
        cell(counterparty),
        cell((tx['date'] ?? '').toString().split('T').first),
        cell(tx['time']),
        cell(youCleared ? 'Yes' : 'No'),
        cell(otherCleared ? 'Yes' : 'No'),
        cell(expectedReturn),
        cell(isOverdue ? 'Yes' : 'No'),
      ].join(','));
    }
    final now = DateTime.now();
    final filename = 'lenden_secure_txns_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
    final ok = await shareTextFile(content: buf.toString(), filename: filename, subject: 'LenDen Secure Transactions Export');
    if (!ok && mounted) {
      ElegantNotification.error(
        title: const Text('Export failed', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('Could not export the file'),
      ).show(context);
    }
  }

  // ── PDF Export ────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    final allTxns = [...lending, ...borrowing];
    if (allTxns.isEmpty) {
      ElegantNotification.error(
        title: const Text('Nothing to export', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('No transactions to export'),
      ).show(context);
      return;
    }

    const darkBg    = PdfColor.fromInt(0xFF0D1B2A);
    const cyan      = PdfColor.fromInt(0xFF00BCD4);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const textDark  = PdfColor.fromInt(0xFF1A1A1A);
    const green     = PdfColor.fromInt(0xFF2E7D32);
    const red       = PdfColor.fromInt(0xFFC62828);
    const orange    = PdfColor.fromInt(0xFFF06322);
    const white70   = PdfColor(1, 1, 1, 0.7);

    String pdfSym(String code) {
      const safe = <String, String>{
        'USD': r'$', 'CAD': r'$', 'AUD': r'$', 'HKD': r'$', 'SGD': r'$', 'NZD': r'$', 'MXN': r'$',
        'EUR': '€', 'GBP': '£', 'JPY': '¥', 'CNY': '¥',
        'CHF': 'Fr', 'INR': 'Rs.', 'RUB': 'RUB', 'KRW': 'KRW', 'BRL': r'R$', 'ZAR': 'R',
      };
      return safe[code.toUpperCase()] ?? code.toUpperCase();
    }

    pw.Widget cell(String text, {bool bold = false, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? textDark)),
        );

    final userEmail = Provider.of<SessionProvider>(context, listen: false).user?['email'] ?? '';
    final now = DateTime.now();
    final genLabel = DateFormat('d MMM yyyy, h:mm a').format(now);
    final lendingCount = lending.length;
    final borrowingCount = borrowing.length;
    final summarySym = pdfSym((allTxns.isNotEmpty ? (allTxns.first['currency'] ?? 'INR') : 'INR').toString().toUpperCase());

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        // Header
        pw.Container(
          decoration: const pw.BoxDecoration(color: darkBg, borderRadius: pw.BorderRadius.all(pw.Radius.circular(12))),
          padding: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('LenDen', style: pw.TextStyle(color: PdfColors.white, fontSize: 26, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Secure Transactions Report', style: pw.TextStyle(color: cyan, fontSize: 13)),
            pw.SizedBox(height: 12),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('$lendingCount lending · $borrowingCount borrowing', style: pw.TextStyle(color: white70, fontSize: 10)),
              pw.Text('Generated: $genLabel', style: pw.TextStyle(color: white70, fontSize: 10)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 20),

        // Summary
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 20),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 0.5), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
          padding: const pw.EdgeInsets.all(14),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Total Lent', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('$summarySym${lending.fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Total Borrowed', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('$summarySym${borrowing.fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0)).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: red)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Total Transactions', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('${allTxns.length}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: textDark)),
            ]),
          ]),
        ),

        // Table
        pw.Text('Transactions', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: textDark)),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(0.9),
            2: const pw.FlexColumnWidth(2.0),
            3: const pw.FlexColumnWidth(1.5),
            4: const pw.FlexColumnWidth(1.0),
            5: const pw.FlexColumnWidth(1.0),
            6: const pw.FlexColumnWidth(1.0),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
              children: ['Amount', 'Role', 'Description', 'Counterparty', 'Date', 'You ✓', 'Status']
                  .map((h) => cell(h, bold: true)).toList(),
            ),
            for (int i = 0; i < allTxns.length; i++) () {
              final tx = allTxns[i];
              final isLend = lending.contains(tx);
              final isCreator = tx['userEmail']?.toString() == userEmail;
              final youCleared = (isCreator ? tx['userCleared'] : tx['counterpartyCleared']) == true;
              final otherCleared = (isCreator ? tx['counterpartyCleared'] : tx['userCleared']) == true;
              final fullyCleared = youCleared && otherCleared;
              final counterparty = (isCreator ? tx['counterpartyEmail'] : tx['userEmail'])?.toString() ?? '—';
              final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
              final sym = pdfSym((tx['currency'] ?? 'INR').toString().toUpperCase());
              final dateStr = (tx['date'] ?? '').toString().split('T').first;
              final expectedDt = DateTime.tryParse((tx['expectedReturnDate'] ?? '').toString());
              final isOverdue = expectedDt != null && expectedDt.isBefore(DateTime.now()) && !fullyCleared;
              return pw.TableRow(
                decoration: pw.BoxDecoration(color: i.isEven ? lightGrey : null),
                children: [
                  cell('$sym${amt.toStringAsFixed(2)}', bold: true, color: isLend ? green : red),
                  cell(isLend ? 'Lending' : 'Borrowing'),
                  cell((tx['description'] ?? '—').toString()),
                  cell(counterparty),
                  cell(dateStr),
                  cell(youCleared ? 'Yes' : 'No', color: youCleared ? green : orange),
                  cell(fullyCleared ? 'Cleared' : isOverdue ? 'Overdue' : 'Pending',
                      color: fullyCleared ? green : isOverdue ? red : orange),
                ],
              );
            }(),
          ],
        ),
      ],
    ));

    final bytes = await doc.save();
    final filename = 'lenden_secure_txns_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
    final ok = await shareBytesFile(bytes: bytes, filename: filename, mimeType: 'application/pdf', subject: 'LenDen Secure Transactions Report');
    if (!ok && mounted) {
      ElegantNotification.error(
        title: const Text('Export failed', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('Could not export the PDF'),
      ).show(context);
    }
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
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: AppThemeColors.primaryText(context)),
            onSelected: (value) {
              if (value == 'export_csv') _exportCsv();
              if (value == 'export_pdf') _exportPdf();
            },
            itemBuilder: (ctx) => [
              if (lending.isNotEmpty || borrowing.isNotEmpty) ...[
                const PopupMenuItem(
                  value: 'export_csv',
                  child: Row(children: [
                    Icon(Icons.table_chart_outlined, size: 18),
                    SizedBox(width: 12),
                    Text('Export CSV'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'export_pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Export PDF'),
                  ]),
                ),
              ],
            ],
          ),
        ],
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
              ? errorStateWidget(context, error!, fetchTransactions)
              : RefreshIndicator(
                  onRefresh: fetchTransactions,
                  color: AppColors.cyan,
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                  children: [
                    BudgetLimitBanner(
                      type: 'secure',
                      refreshTrigger: _bannerRefreshTrigger,
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const BudgetPlanningPage())),
                      onViewMessages: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const BudgetMessagesPage())),
                    ),
                    const SizedBox(height: 6),
                    const FreeAttemptsBanner(featureKey: 'secure_transactions'),
                    AppSearchBar(
                      controller: _globalSearchController,
                      hintText: loc('search_transactions_hint_message'),
                      onChanged: (v) {
                        setState(() => globalSearch = v);
                        _searchDebounceTimer?.cancel();
                        _searchDebounceTimer = Timer(
                          const Duration(milliseconds: 300),
                          fetchTransactions,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildMonthlySummary(),
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
                                      loc('conversion_not_available_secure_message').replaceFirst('{currency}', selectedCurrency),
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
                          buildCurrencySelector(),
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
                          // Backend pagination: load next page
                          if (_txnHasMore && showAllTransactions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator(color: AppColors.cyan)
                                    : OutlinedButton.icon(
                                        onPressed: _loadMoreTransactions,
                                        icon: const Icon(Icons.expand_more, color: AppColors.cyan),
                                        label: Text(
                                          loc('load_more_label'),
                                          style: const TextStyle(color: AppColors.cyan),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: AppColors.cyan),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
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
