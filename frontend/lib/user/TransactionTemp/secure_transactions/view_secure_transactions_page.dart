//This file is to view user transactions
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import 'dart:convert';
import '../../../utils/api_client.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../../utils/display_currency_helper.dart';
import 'secure_transaction_detail_page.dart';

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
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
        _displayCurrencyError =
            'Currency conversion options are not available right now.';
      });
    }
  }

  Widget _buildErrorState(String message, VoidCallback onRetry) {
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
                    Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
          {'code': 'INR', 'symbol': 'â‚¹', 'label': ''},
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
          color: Colors.white,
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
    setState(() {
      loading = true;
      error = null;
    });
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    if (email == null) {
      setState(() {
        error = 'User email not found.';
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
          error = 'Failed to load transactions.';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Unable to connect. Please check your internet connection.';
        loading = false;
      });
    }
  }

  Widget _buildTransactionCard(Map t, bool isLending) {
    List<Map<String, dynamic>> attachments = [];
    if (t['files'] != null && t['files'] is List && t['files'].isNotEmpty) {
      attachments = List<Map<String, dynamic>>.from(t['files']);
    } else if (t['photos'] != null &&
        t['photos'] is List &&
        t['photos'].isNotEmpty) {
      // For backward compatibility, treat photos as images
      attachments = t['photos']
          .map<Map<String, dynamic>>(
              (p) => {'type': 'image/jpeg', 'data': p, 'name': 'Photo'})
          .toList();
    }
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    final userEmail = t['userEmail'];
    // Determine the counterparty email based on current user's role
    final counterpartyEmail =
        (email == userEmail) ? t['counterpartyEmail'] : userEmail;
    bool youCleared =
        (isLending ? t['userCleared'] : t['counterpartyCleared']) == true;
    bool otherCleared =
        (isLending ? t['counterpartyCleared'] : t['userCleared']) == true;
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
    String counterparty =
        isLending ? t['counterpartyEmail'] : t['counterpartyEmail'];
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
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SecureTransactionDetailPage(
              transaction: Map<String, dynamic>.from(t),
              isLending: isLending,
            ),
          ),
        );
        if (result == true) fetchTransactions();
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 0),
      decoration: BoxDecoration(
        color: Colors.white,
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
                        Text('Date: $dateStr',
                            style: TextStyle(fontSize: 14)),
                        SizedBox(width: 10),
                        Icon(Icons.access_time,
                            color: Colors.deepPurple, size: 18),
                        SizedBox(width: 6),
                        Text('Time: $timeStr',
                            style: TextStyle(fontSize: 14)),
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
                              'Partial',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(width: 10),
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.teal.shade100,
                          child: Icon(Icons.person, color: Colors.teal, size: 22),
                        ),
                        SizedBox(width: 10),
                        Text(
                          isLending
                              ? 'Lending (You gave money)'
                              : 'Borrowing (You took money)',
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
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.teal.shade100,
                          child: Icon(Icons.person_outline, color: Colors.teal, size: 16),
                        ),
                        SizedBox(width: 8),
                        Text('Counterparty: $counterpartyEmail',
                            style:
                                TextStyle(fontSize: 15, color: Colors.black87),
                            softWrap: false,
                            overflow: TextOverflow.fade),
                      ],
                    ),
                    SizedBox(height: 6),
                    // Amount (always visible - most important)
                    Row(
                      children: [
                        Icon(Icons.attach_money, color: Colors.green, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Amount: ${_formatDisplayAmount((t['amount'] as num?) ?? 0, t['currency']?.toString())}',
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
                                  _remainingTimeLabel(expectedReturnDate!),
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
                                ? 'Fully Cleared'
                                : hasPartialPayment
                                    ? 'Partially Paid / Cleared'
                                    : (youCleared && !otherCleared)
                                        ? 'You cleared'
                                        : (!youCleared && otherCleared)
                                            ? 'Other cleared'
                                            : 'Uncleared',
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

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: Text('All'),
            selected: filter == 'All',
            onSelected: (_) { setState(() => filter = 'All'); fetchTransactions(); },
            selectedColor: Color(0xFF00B4D8).withValues(alpha: 0.2),
          ),
          SizedBox(width: 8),
          ChoiceChip(
            label: Text('Lending'),
            selected: filter == 'Lending',
            onSelected: (_) { setState(() => filter = 'Lending'); fetchTransactions(); },
            selectedColor: Colors.green.withValues(alpha: 0.2),
            labelStyle: TextStyle(color: Colors.green[800]),
          ),
          SizedBox(width: 8),
          ChoiceChip(
            label: Text('Borrowing'),
            selected: filter == 'Borrowing',
            onSelected: (_) { setState(() => filter = 'Borrowing'); fetchTransactions(); },
            selectedColor: Colors.orange.withValues(alpha: 0.2),
            labelStyle: TextStyle(color: Colors.orange[800]),
          ),
          SizedBox(width: 8),
          ChoiceChip(
            label: Text('Favourites'),
            selected: showFavouritesOnly,
            onSelected: (selected) {
                setState(() => showFavouritesOnly = selected);
                fetchTransactions();
            },
            selectedColor: Colors.red.withValues(alpha: 0.2),
            labelStyle: TextStyle(color: Colors.red[800]),
          ),
          if (_hasActiveFilters()) ...[
            SizedBox(width: 8),
            ActionChip(
              label: const Text('Reset'),
              avatar: const Icon(Icons.refresh_rounded, size: 18),
              onPressed: _resetFilters,
              backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.10),
              labelStyle: const TextStyle(
                color: Color(0xFF0077B6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildClearanceFilterChips() {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.symmetric(vertical: 8),
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Tooltip(
                      message: 'Show all transactions',
                      child: ChoiceChip(
                        label: Text('All'),
                        selected: clearanceFilter == 'All',
                        onSelected: (_) {
                          setState(() => clearanceFilter = 'All');
                          fetchTransactions();
                        },
                        selectedColor: Color(0xFF00B4D8).withValues(alpha: 0.2),
                      ),
                    ),
                    SizedBox(width: 8),
                    Tooltip(
                      message: 'Both parties have cleared',
                      child: ChoiceChip(
                        label: Text('Totally Cleared'),
                        selected: clearanceFilter == 'Totally Cleared',
                        onSelected: (_) {
                          setState(() => clearanceFilter = 'Totally Cleared');
                          fetchTransactions();
                        },
                        selectedColor: Colors.green.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: Colors.green[800]),
                      ),
                    ),
                    SizedBox(width: 8),
                    Tooltip(
                      message: 'Neither party has cleared',
                      child: ChoiceChip(
                        label: Text('Totally Uncleared'),
                        selected: clearanceFilter == 'Totally Uncleared',
                        onSelected: (_) {
                          setState(() => clearanceFilter = 'Totally Uncleared');
                          fetchTransactions();
                        },
                        selectedColor: Colors.orange.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: Colors.orange[800]),
                      ),
                    ),
                    SizedBox(width: 8),
                    Tooltip(
                      message: 'Only one party has cleared',
                      child: ChoiceChip(
                        label: Text('Partially Cleared'),
                        selected: clearanceFilter == 'Partially Cleared',
                        onSelected: (_) {
                          setState(() => clearanceFilter = 'Partially Cleared');
                          fetchTransactions();
                        },
                        selectedColor: Colors.blue.withValues(alpha: 0.2),
                        labelStyle: TextStyle(color: Colors.blue[800]),
                      ),
                    ),
                  ],
                ),
              ),
              if (clearanceFilter == 'Partially Cleared')
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ToggleButtons(
                        isSelected: [
                          partialClearedType == 'my',
                          partialClearedType == 'other'
                        ],
                        onPressed: (idx) {
                          setState(() => partialClearedType = idx == 0 ? 'my' : 'other');
                          fetchTransactions();
                        },
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.white,
                        fillColor: Colors.teal,
                        color: Colors.teal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              Icon(Icons.person, size: 18),
                              SizedBox(width: 6),
                              Text('My Side')
                            ]),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(children: [
                              Icon(Icons.people, size: 18),
                              SizedBox(width: 6),
                              Text('Other Party Side')
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Interest type filter chips
        Container(
          margin: EdgeInsets.only(top: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: Text('All'),
                  selected: interestTypeFilter == 'All',
                  onSelected: (_) { setState(() => interestTypeFilter = 'All'); fetchTransactions(); },
                  selectedColor: Color(0xFF00B4D8).withValues(alpha: 0.2),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Simple Interest'),
                  selected: interestTypeFilter == 'simple',
                  onSelected: (_) { setState(() => interestTypeFilter = 'simple'); fetchTransactions(); },
                  selectedColor: Colors.green.withValues(alpha: 0.2),
                  labelStyle: TextStyle(color: Colors.green[800]),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('Compound Interest'),
                  selected: interestTypeFilter == 'compound',
                  onSelected: (_) { setState(() => interestTypeFilter = 'compound'); fetchTransactions(); },
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                  labelStyle: TextStyle(color: Colors.blue[800]),
                ),
                SizedBox(width: 8),
                ChoiceChip(
                  label: Text('With Interest'),
                  selected: interestTypeFilter == 'with_interest',
                  onSelected: (_) { setState(() => interestTypeFilter = 'with_interest'); fetchTransactions(); },
                  selectedColor: Colors.purple.withValues(alpha: 0.2),
                  labelStyle: TextStyle(color: Colors.purple[800]),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
                    label: 'All',
                    selected: filter == 'All',
                    accentColor: const Color(0xFF00B4D8),
                    onTap: () { setState(() => filter = 'All'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildPrimaryFilterTab(
                    label: 'Lending',
                    selected: filter == 'Lending',
                    accentColor: Colors.green,
                    onTap: () { setState(() => filter = 'Lending'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildPrimaryFilterTab(
                    label: 'Borrowing',
                    selected: filter == 'Borrowing',
                    accentColor: Colors.orange,
                    onTap: () { setState(() => filter = 'Borrowing'); fetchTransactions(); },
                  ),
                  const SizedBox(width: 10),
                  _buildToolbarAction(
                    icon: showFavouritesOnly
                        ? Icons.favorite
                        : Icons.favorite_border,
                    label: 'Fav',
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
                        activeCount > 0 ? 'Filters ($activeCount)' : 'Filters',
                    accentColor: const Color(0xFF00B4D8),
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
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: 0.86),
                    Colors.white,
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
                    color: Colors.grey.shade600,
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
          color: selected ? accentColor.withValues(alpha: 0.12) : Colors.white,
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
            color: selected ? accentColor : Colors.grey.shade700,
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
          color: isActive ? accentColor.withValues(alpha: 0.12) : Colors.white,
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

  Widget _buildAdvancedFilters() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _startDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Start Date',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(_startDate == null
                      ? 'Any'
                      : DateFormat('yyyy-MM-dd').format(_startDate!)),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _endDate = picked);
                },
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'End Date',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  child: Text(_endDate == null
                      ? 'Any'
                      : DateFormat('yyyy-MM-dd').format(_endDate!)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: 'Min Amount',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) =>
                    setState(() => _minAmount = double.tryParse(val)),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                decoration: InputDecoration(
                  labelText: 'Max Amount',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) =>
                    setState(() => _maxAmount = double.tryParse(val)),
              ),
            ),
          ],
        ),
      ],
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
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF00B4D8),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
              background: Colors.white,
            ),
            dialogTheme: DialogTheme(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00B4D8),
              ),
            ),
            cardColor: Colors.white,
            canvasColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
  }

  Future<void> _showFiltersBottomSheet() async {
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
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
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
                      color: const Color(0xFFFDFEFE),
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
                                    color: const Color(0xFF00B4D8)
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(Icons.tune_rounded,
                                      color: Color(0xFF00B4D8)),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Refine Transactions',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Use smart filters to narrow the secure list quickly.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
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
                                  'Clearance status',
                                  'Choose how far the transaction has progressed.',
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
                                              label: Text(value),
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
                                  'Interest type',
                                  'Focus on the interest setup you want to review.',
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      {'label': 'All', 'value': 'All'},
                                      {
                                        'label': 'Simple Interest',
                                        'value': 'simple'
                                      },
                                      {
                                        'label': 'Compound Interest',
                                        'value': 'compound'
                                      },
                                      {
                                        'label': 'With Interest',
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
                                  'Sort transactions',
                                  'Order secure transactions by creation time, transaction date, amount, or status.',
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
                                              label: Text(value),
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
                                        'label': 'Newest First',
                                        'value': false,
                                      },
                                      {
                                        'label': 'Oldest First',
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
                                  'Date range',
                                  'Limit results to a transaction period.',
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => pickDate(true),
                                        child: InputDecorator(
                                          decoration: InputDecoration(
                                            labelText: 'Start Date',
                                            border: InputBorder.none,
                                            isDense: true,
                                            prefixIcon: const Icon(
                                              Icons.calendar_today,
                                              color: Color(0xFF00B4D8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                tempStartDate == null
                                                    ? 'Any'
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
                                            labelText: 'End Date',
                                            border: InputBorder.none,
                                            isDense: true,
                                            prefixIcon: const Icon(
                                              Icons.calendar_today,
                                              color: Color(0xFF00B4D8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                tempEndDate == null
                                                    ? 'Any'
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
                                  'Amount range',
                                  'See only transactions within a value band.',
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: minAmountController,
                                        decoration: InputDecoration(
                                          labelText: 'Min Amount',
                                          filled: true,
                                          fillColor: Colors.white,
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
                                          labelText: 'Max Amount',
                                          filled: true,
                                          fillColor: Colors.white,
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
                                      backgroundColor: Colors.white,
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    child: const Text(
                                      'Clear Sheet',
                                      style: TextStyle(
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
                                      backgroundColor: const Color(0xFF00B4D8),
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    child: const Text(
                                      'Apply Filters',
                                      style: TextStyle(
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
    final chips = <Map<String, dynamic>>[];
    if (filter != 'All') {
      chips.add({
        'label': filter,
        'color': filter == 'Lending' ? Colors.green : Colors.orange,
      });
    }
    if (showFavouritesOnly) {
      chips.add({'label': 'Favourites', 'color': Colors.red});
    }
    if (clearanceFilter != 'All') {
      chips.add({
        'label': clearanceFilter,
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
            ? 'With Interest'
            : interestTypeFilter == 'simple'
                ? 'Simple Interest'
                : 'Compound Interest',
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
            'Dates: ${_startDate == null ? 'Any' : DateFormat('MMM d').format(_startDate!)} - ${_endDate == null ? 'Any' : DateFormat('MMM d').format(_endDate!)}',
        'color': const Color(0xFF00B4D8),
      });
    }
    if (_minAmount != null || _maxAmount != null) {
      chips.add({
        'label':
            'Amount: ${_minAmount?.toStringAsFixed(0) ?? 'Any'} - ${_maxAmount?.toStringAsFixed(0) ?? 'Any'}',
        'color': const Color(0xFF7C4DFF),
      });
    }
    if (_sortBy != 'Created' || _sortAsc != false) {
      chips.add({
        'label':
            'Sort: $_sortBy â€¢ ${_sortAsc ? 'Oldest First' : 'Newest First'}',
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
          color: Colors.white,
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
                    size: 18, color: Color(0xFF00B4D8)),
                const SizedBox(width: 8),
                const Text(
                  'Active filters',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reset'),
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

  String? _viewerEmail() {
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    return user?['email'];
  }

  bool _isTotallyCleared(Map t) =>
      (t['userCleared'] == true && t['counterpartyCleared'] == true);

  bool _hasPartialPayment(Map t) {
    final partialPayments = t['partialPayments'];
    return t['isPartiallyPaid'] == true ||
        (partialPayments is List && partialPayments.isNotEmpty);
  }

  bool _isTotallyUncleared(Map t) => (t['userCleared'] != true &&
      t['counterpartyCleared'] != true &&
      !_hasPartialPayment(t));

  bool _isPartiallyClearedMySide(Map t) {
    final email = _viewerEmail();
    if (t['userEmail'] == email) {
      return t['userCleared'] == true && t['counterpartyCleared'] != true;
    } else if (t['counterpartyEmail'] == email) {
      return t['counterpartyCleared'] == true && t['userCleared'] != true;
    }
    return false;
  }

  bool _isPartiallyClearedOtherSide(Map t) {
    final email = _viewerEmail();
    if (t['userEmail'] == email) {
      return t['counterpartyCleared'] == true && t['userCleared'] != true;
    } else if (t['counterpartyEmail'] == email) {
      return t['userCleared'] == true && t['counterpartyCleared'] != true;
    }
    return false;
  }

  bool _isPartiallyCleared(Map t) {
    final userCleared = t['userCleared'] == true;
    final counterpartyCleared = t['counterpartyCleared'] == true;
    return userCleared != counterpartyCleared || _hasPartialPayment(t);
  }

  String _remainingTimeLabel(DateTime expectedReturnDate) {
    final difference = expectedReturnDate.difference(_now);
    if (difference.isNegative) {
      return 'Overdue since ${DateFormat('MMM d').format(expectedReturnDate)}';
    }
    if (difference.inDays > 0) {
      return '${difference.inDays} day(s) remaining';
    }
    final hours = difference.inHours;
    final minutes = difference.inMinutes.remainder(60);
    final seconds = difference.inSeconds.remainder(60);
    return '${hours}h ${minutes}m ${seconds}s remaining';
  }

  // Returns already server-filtered data as-is
  Map<String, List<dynamic>> _getFilteredTransactionBuckets() {
    return {
      'lending': List<dynamic>.from(lending),
      'borrowing': List<dynamic>.from(borrowing),
    };
  }

  Widget _buildStatusLegend() {
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
          item(Colors.grey, Icons.hourglass_empty, 'Uncleared'),
          item(Colors.orange, Icons.check_circle_outline, 'You cleared'),
          item(Colors.blue, Icons.people_alt_outlined, 'Other cleared'),
          item(Colors.green, Icons.verified, 'Fully cleared'),
        ],
      ),
    );
  }

  List<Widget> _buildFilteredTransactionCards({int? limit}) {
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
      widgets.add(Text('Lending Amount',
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)));
      widgets.add(SizedBox(height: 8));
      widgets.addAll(finalLending.map((t) => _buildTransactionCard(t, true)));
      widgets.add(SizedBox(height: 20));
    }

    if (finalBorrowing.isNotEmpty) {
      widgets.add(Text('Borrowing Amount',
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
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              'No transactions found',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            Text(
              'Try adjusting your search or filters',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            ),
            if (_hasActiveFilters()) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _resetFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reset Filters'),
              ),
            ],
          ],
        ),
      ));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
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
      appBar: AppBar(
        backgroundColor: Color(0xFF00B4D8),
        elevation: 0,
        title: Text('Your Transactions ($totalTransactions)',
            style: TextStyle(color: Colors.black)),
      ),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : error != null
              ? _buildErrorState(error!, fetchTransactions)
              : Column(
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
                            hintText:
                                'Search transactions... (email, place, type, id, amount, lending/borrowing)',
                            prefixIcon:
                                Icon(Icons.search, color: Color(0xFF00B4D8)),
                            filled: true,
                            fillColor: Colors.white,
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
                                      'Conversion to $_selectedDisplayCurrency is not available for one or more secure transactions. Showing original currencies instead.',
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
                          const Text(
                            'Show In',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 10),
                          _buildCurrencySelector(),
                        ],
                      ),
                    ),
                    SizedBox(height: 8),
                    Expanded(
                      child: ListView(
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
                                    backgroundColor: Color(0xFF00B4D8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: Text('View All Transactions',
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
                                    backgroundColor: Colors.grey[300],
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 12),
                                  ),
                                  child: Text('Show Less',
                                      style: TextStyle(
                                          color: Color(0xFF00B4D8),
                                          fontSize: 16)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

}