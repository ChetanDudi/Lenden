import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/display_currency_helper.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/payment_success_page.dart';
import '../../digitise/gift_card_page.dart';
import '../analytics_page.dart';
import '../../wallet/lenden_wallet_page.dart';
import './create_edit_quick_transaction_page.dart';
import './quick_transaction_detail_page.dart';

class QuickTransactionsPage extends StatefulWidget {
  final String? prefillCounterpartyEmail;
  final bool openCreateOnLoad;
  final bool initialShowFavouritesOnly;

  const QuickTransactionsPage({
    Key? key,
    this.prefillCounterpartyEmail,
    this.openCreateOnLoad = false,
    this.initialShowFavouritesOnly = false,
  }) : super(key: key);
  @override
  State<QuickTransactionsPage> createState() => _QuickTransactionsPageState();
}

class _QuickTransactionsPageState extends State<QuickTransactionsPage> {
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> filteredTransactions = [];
  bool loading = true;
  String? error;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String sortBy = 'created_desc';
  String filterBy = 'all'; // 'all', 'cleared', 'not_cleared'
  String _roleFilter = 'all'; // 'all', 'lent', 'borrowed'
  String _dateFilter = 'all'; // 'all', 'today', 'week', 'month'
  String _selectedCounterparty = 'all';
  bool _showFavouritesOnly = false;
  bool _showAll = false;
  Set<String> _blockedEmails = {};
  Set<String> _pinnedTransactionIds = {};
  Map<String, dynamic>? _dailyLimits;
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
  String? _displayCurrencyError;
  Timer? _searchDebounceTimer;
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  final Map<String, int> _clearActionTokens = {};

  @override
  void initState() {
    super.initState();
    _showFavouritesOnly = widget.initialShowFavouritesOnly;
    fetchQuickTransactions();
    _loadBlockedUsers();
    _loadDailyLimits();
    _loadDisplayCurrencies();
    _loadPinnedTransactions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.openCreateOnLoad &&
          (widget.prefillCounterpartyEmail ?? '').isNotEmpty) {
        _openQuickTransactionDialog(
          prefillEmail: widget.prefillCounterpartyEmail,
        );
      }
    });
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final blocked =
            List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
        setState(() {
          _blockedEmails = blocked
              .map((u) => (u['email'] ?? '').toString().toLowerCase().trim())
              .where((e) => e.isNotEmpty)
              .toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadDailyLimits() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
    try {
      final res = await ApiClient.get('/api/limits/daily');
      if (res.statusCode == 200) {
        setState(() {
          _dailyLimits = jsonDecode(res.body);
        });
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

  String? _currentUserEmail() {
    return Provider.of<SessionProvider>(context, listen: false)
        .user?['email']
        ?.toString()
        .toLowerCase()
        .trim();
  }

  Future<void> _loadPinnedTransactions() async {
    final currentUserEmail = _currentUserEmail();
    if (currentUserEmail == null || currentUserEmail.isEmpty) return;
    final raw = await _storage.read(key: 'quick_pins_$currentUserEmail');
    if (raw == null || raw.isEmpty) return;
    try {
      final ids = List<String>.from(jsonDecode(raw) as List<dynamic>);
      if (!mounted) return;
      setState(() {
        _pinnedTransactionIds = ids.toSet();
      });
    } catch (_) {}
  }

  Future<void> _persistPinnedTransactions() async {
    final currentUserEmail = _currentUserEmail();
    if (currentUserEmail == null || currentUserEmail.isEmpty) return;
    await _storage.write(
      key: 'quick_pins_$currentUserEmail',
      value: jsonEncode(_pinnedTransactionIds.toList()),
    );
  }

  Future<void> _togglePinTransaction(String id) async {
    setState(() {
      if (_pinnedTransactionIds.contains(id)) {
        _pinnedTransactionIds.remove(id);
      } else {
        _pinnedTransactionIds.add(id);
      }
      _applyPinSort();
    });
    await _persistPinnedTransactions();
  }

  bool _isCurrentUserCreator(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final creatorEmail =
        (transaction['creatorEmail'] ?? '').toString().toLowerCase().trim();
    return currentUserEmail != null && creatorEmail == currentUserEmail;
  }

  String _roleForViewer(Map<String, dynamic> transaction) {
    final storedRole =
        (transaction['role'] ?? 'lender').toString().toLowerCase();
    if (_isCurrentUserCreator(transaction)) {
      return storedRole;
    }
    return storedRole == 'lender' ? 'borrower' : 'lender';
  }

  Map<String, dynamic>? _counterpartyForViewer(
      Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final users = List<Map<String, dynamic>>.from(transaction['users'] ?? []);
    for (final user in users) {
      final email = (user['email'] ?? '').toString().toLowerCase().trim();
      if (email.isNotEmpty && email != currentUserEmail) {
        return user;
      }
    }
    return users.isNotEmpty ? users.first : null;
  }

  List<Map<String, String>> _counterpartyOptions() {
    final seen = <String>{};
    final options = <Map<String, String>>[
      {'email': 'all', 'label': 'All People'}
    ];
    for (final transaction in transactions) {
      final counterparty = _counterpartyForViewer(transaction);
      final email = (counterparty?['email'] ?? '').toString().trim();
      if (email.isEmpty || seen.contains(email.toLowerCase())) continue;
      seen.add(email.toLowerCase());
      final name = (counterparty?['name'] ?? '').toString().trim();
      options.add({
        'email': email,
        'label': name.isNotEmpty ? name : email,
      });
    }
    return options;
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

  String _formatDisplayAmount(dynamic amount, String? originalCurrency) {
    final numericAmount = amount is num
        ? amount.toDouble()
        : double.tryParse((amount ?? 0).toString()) ?? 0.0;
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
      return '$originalSymbol${numericAmount.toStringAsFixed(2)}';
    }
    final converted = _displayCurrencyData?.convert(
          numericAmount,
          sourceCurrency,
          targetCurrency,
        ) ??
        numericAmount;
    final symbol =
        _displayCurrencyData?.symbolFor(targetCurrency) ?? targetCurrency;
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  double _displayNumericAmount(Map<String, dynamic> transaction) {
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

  String _topQuickCounterpartyName(
      List<Map<String, dynamic>> transactionsList) {
    final totals = <String, double>{};
    final names = <String, String>{};
    final currentEmail = _currentUserEmail();

    for (final transaction in transactionsList) {
      final users = List<Map<String, dynamic>>.from(transaction['users'] ?? []);
      final counterparty = users.firstWhere(
        (user) =>
            (user['email'] ?? '').toString().toLowerCase().trim() !=
            currentEmail,
        orElse: () => {},
      );
      final email = (counterparty['email'] ?? '').toString();
      final name = (counterparty['name'] ?? email).toString();
      if (email.isEmpty) continue;
      totals[email] =
          (totals[email] ?? 0.0) + _displayNumericAmount(transaction).abs();
      names[email] = name;
    }

    if (totals.isEmpty) return 'No counterparty';
    final topEntry = totals.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return names[topEntry.key] ?? topEntry.key;
  }

  bool _hasMissingConversionForQuickTransactions() {
    if (_selectedDisplayCurrency.toUpperCase() == 'INR') return false;
    if (_displayCurrencyData == null) return true;
    for (final transaction in filteredTransactions) {
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
            borderRadius: BorderRadius.circular(16),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
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

  bool _isBlockedEmail(String? email) {
    final target = email?.toLowerCase().trim();
    if (target == null || target.isEmpty) return false;
    return _blockedEmails.contains(target);
  }

  Future<void> _openQuickTransactionDialog({
    Map<String, dynamic>? transaction,
    String? prefillEmail,
  }) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (_blockedEmails.isEmpty) {
      await _loadBlockedUsers();
    }
    if (!session.isSubscribed) {
      await Future.wait([
        session.loadFreebieCounts(),
        _loadDailyLimits(),
      ]);
    }
    if (_isBlockedEmail(prefillEmail)) {
      showBlockedUserDialog(context);
      return;
    }

    final dailyQuickRemaining =
        _dailyLimits?['limits']?['quickTransactions']?['remaining'] as int?;

    // Rule: if daily limit is expired → hard block; free attempts are also paused.
    if (!session.isSubscribed && transaction == null &&
        dailyQuickRemaining != null && dailyQuickRemaining <= 0) {
      showDailyLimitDialog(context,
          message:
              'You\'ve reached today\'s limit of 3 quick transactions. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
      return;
    }

    // Daily limit OK but free attempts exhausted → offer coins.
    final shouldUseCoins = !session.isSubscribed &&
        transaction == null &&
        (session.freeQuickTransactionsRemaining ?? 0) <= 0;

    if (shouldUseCoins) {
      const int coinCost = 5;
      final coins = session.lenDenCoins ?? 0;
      if (coins < coinCost) {
        if (coins == 0) {
          showZeroCoinsDialog(context);
        } else {
          showInsufficientCoinsDialog(context);
        }
        return;
      }
      final useCoins = await showFreeAttemptsExhaustedDialog(
        context,
        featureName: 'quick transaction',
        coinCost: coinCost,
        currentCoins: coins,
      );
      if (useCoins != true) return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditQuickTransactionPage(
          transaction: transaction,
          useCoins: shouldUseCoins,
          prefillCounterpartyEmail: prefillEmail,
          blockedEmails: _blockedEmails,
          dailyRemaining:
              _dailyLimits?['limits']?['quickTransactions']?['remaining'],
          isSubscribed: session.isSubscribed,
        ),
      ),
    );

    if (result is String) {
      if (result.toLowerCase().contains('blocked')) {
        showBlockedUserDialog(context, message: result);
        return;
      }
      if (result.toLowerCase().contains('daily limit')) {
        showDailyLimitDialog(context, message: result);
        return;
      }
      ElegantNotification.error(
        title: Text("Error"),
        description: Text(result),
      ).show(context);
    } else if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      session.loadFreebieCounts();
      final giftCardAwarded = result['giftCardAwarded'] as bool?;
      final awardedCard = result['awardedCard'];
      final txn = result['transaction'] ?? result;

      final amt = (txn['amount'] as num?)?.toDouble();
      final recipient = (txn['counterpartyEmail'] ?? txn['counterpartyName'] ?? '').toString();
      final role = (txn['role'] ?? '').toString();
      final extraDetails = <String, String>{
        if (role.isNotEmpty) 'Role': role,
        if (giftCardAwarded == true && awardedCard != null) 'Bonus': '🎉 Gift card won!',
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            title: transaction != null ? 'Transaction Updated!' : 'Transaction Created!',
            amount: amt,
            recipientName: recipient.isNotEmpty ? recipient : null,
            transactionType: 'Quick Transaction',
            extraDetails: extraDetails,
          ),
        ),
      );

      if (giftCardAwarded == true && awardedCard != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ElegantNotification.success(
              title: Text("Congratulations!"),
              description: Text("You've won a gift card!"),
              action: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: Text('View', style: TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          }
        });
      }
    }
  }

  // Pin-aware local sort for display ordering (pinned first)
  void _applyPinSort() {
    filteredTransactions.sort((a, b) {
      final aPinned = _pinnedTransactionIds.contains((a['_id'] ?? '').toString());
      final bPinned = _pinnedTransactionIds.contains((b['_id'] ?? '').toString());
      return aPinned == bPinned ? 0 : (aPinned ? -1 : 1);
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void applyFilter(String filter) {
    setState(() => filterBy = filter);
    fetchQuickTransactions();
  }

  void _applyRoleFilter(String value) {
    setState(() => _roleFilter = value);
    fetchQuickTransactions();
  }

  void _toggleShowFavourites() {
    setState(() => _showFavouritesOnly = !_showFavouritesOnly);
    fetchQuickTransactions();
  }

  void _applyCounterpartyFilter(String value) {
    setState(() => _selectedCounterparty = value);
    fetchQuickTransactions();
  }

  bool _hasActiveFilters() {
    return searchQuery.isNotEmpty ||
        filterBy != 'all' ||
        _roleFilter != 'all' ||
        _dateFilter != 'all' ||
        _selectedCounterparty != 'all' ||
        _showFavouritesOnly;
  }

  bool _isQuickTransactionFavourited(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final favourites = List<dynamic>.from(transaction['favourite'] ?? []);
    return currentUserEmail != null && favourites.contains(currentUserEmail);
  }

  Future<void> _toggleQuickTransactionFavourite(
      Map<String, dynamic> transaction) async {
    final currentUserEmail = _currentUserEmail();
    if (currentUserEmail == null || currentUserEmail.isEmpty) return;
    final transactionId = (transaction['_id'] ?? '').toString();
    if (transactionId.isEmpty) return;

    final isCurrentlyFav = _isQuickTransactionFavourited(transaction);
    setState(() {
      final favourites = List<String>.from(transaction['favourite'] ?? []);
      if (isCurrentlyFav) {
        favourites.remove(currentUserEmail);
      } else {
        favourites.add(currentUserEmail);
      }
      transaction['favourite'] = favourites;
    });

    try {
      final res = await ApiClient.put(
          '/api/quick-transactions/$transactionId/favourite',
          body: {'email': currentUserEmail});
      if (res.statusCode != 200) {
        // Revert on failure
        setState(() {
          final favourites = List<String>.from(transaction['favourite'] ?? []);
          if (isCurrentlyFav) {
            favourites.add(currentUserEmail);
          } else {
            favourites.remove(currentUserEmail);
          }
          transaction['favourite'] = favourites;
        });
      }
    } catch (_) {
      setState(() {
        final favourites = List<String>.from(transaction['favourite'] ?? []);
        if (isCurrentlyFav) {
          favourites.add(currentUserEmail);
        } else {
          favourites.remove(currentUserEmail);
        }
        transaction['favourite'] = favourites;
      });
    }
  }

  String _filterSummaryLabel() {
    final labels = <String>[];
    if (filterBy == 'cleared') labels.add('Cleared');
    if (filterBy == 'not_cleared') labels.add('Pending');
    if (_dateFilter == 'today') labels.add('Today');
    if (_dateFilter == 'week') labels.add('This Week');
    if (_dateFilter == 'month') labels.add('This Month');
    if (_selectedCounterparty != 'all') {
      final match = _counterpartyOptions().firstWhere(
        (item) => item['email'] == _selectedCounterparty,
        orElse: () => {'label': 'Person'},
      );
      labels.add(match['label'] ?? 'Person');
    }
    if (labels.isEmpty) return 'Filter';
    if (labels.length == 1) return labels.first;
    return '${labels.first} +${labels.length - 1}';
  }

  String _sortSummaryLabel() {
    switch (sortBy) {
      case 'created_asc':
        return 'Oldest';
      case 'updated_desc':
        return 'Updated';
      case 'updated_asc':
        return 'Old Updated';
      case 'amount_asc':
        return 'Amt Low';
      case 'amount_desc':
        return 'Amt High';
      case 'created_desc':
      default:
        return 'Newest';
    }
  }

  void _resetFilters() {
    setState(() {
      searchQuery = '';
      _searchController.clear();
      filterBy = 'all';
      _roleFilter = 'all';
      _dateFilter = 'all';
      _selectedCounterparty = 'all';
      _showFavouritesOnly = false;
      _showAll = false;
    });
    fetchQuickTransactions();
  }

  Future<void> fetchQuickTransactions() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      // Build query params from current filter state
      final params = <String, String>{};
      if (searchQuery.isNotEmpty) params['search'] = searchQuery;
      if (sortBy != 'created_desc') params['sortBy'] = sortBy;
      if (filterBy != 'all') params['filterBy'] = filterBy;
      if (_roleFilter != 'all') params['role'] = _roleFilter == 'lent' ? 'lender' : 'borrower';
      if (_dateFilter != 'all') params['dateFilter'] = _dateFilter;
      if (_showFavouritesOnly) params['favouritesOnly'] = 'true';
      if (_selectedCounterparty != 'all') params['counterparty'] = _selectedCounterparty;

      final queryString = params.isEmpty
          ? ''
          : '?' + params.entries
              .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
              .join('&');

      final res = await ApiClient.get('/api/quick-transactions$queryString');
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
          transactions = fetchedTransactions;
          filteredTransactions = List.from(fetchedTransactions);
          // Reset counterparty filter if it no longer exists in returned data
          final counterpartyStillExists = _counterpartyOptions().any(
            (item) => item['email'] == _selectedCounterparty,
          );
          if (!counterpartyStillExists) {
            _selectedCounterparty = 'all';
          }
          // Apply pin-based sort for display order only
          _applyPinSort();
          loading = false;
        });
      } else {
        setState(() {
          error = 'Failed to load quick transactions';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Failed to load quick transactions';
        loading = false;
      });
    }
  }

  Future<void> createOrEditQuickTransaction(
      {Map<String, dynamic>? transaction}) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (_blockedEmails.isEmpty) {
      await _loadBlockedUsers();
    }
    if (!session.isSubscribed) {
      await Future.wait([
        session.loadFreebieCounts(),
        _loadDailyLimits(),
      ]);
    }
    final dailyQuickRemaining =
        _dailyLimits?['limits']?['quickTransactions']?['remaining'] as int?;

    // Daily limit expired → hard block (free attempts also paused until tomorrow).
    if (!session.isSubscribed && transaction == null &&
        dailyQuickRemaining != null && dailyQuickRemaining <= 0) {
      showDailyLimitDialog(context,
          message:
              'You\'ve reached today\'s limit of 3 quick transactions. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
      return;
    }

    // Daily limit OK but free attempts exhausted → offer coins.
    final shouldUseCoins = !session.isSubscribed &&
        transaction == null &&
        (session.freeQuickTransactionsRemaining ?? 0) <= 0;

    if (shouldUseCoins) {
      const int coinCost = 5;
      final coins = session.lenDenCoins ?? 0;
      if (coins < coinCost) {
        if (coins == 0) {
          showZeroCoinsDialog(context);
        } else {
          showInsufficientCoinsDialog(context);
        }
        return;
      }
      final useCoins = await showFreeAttemptsExhaustedDialog(
        context,
        featureName: 'quick transaction',
        coinCost: coinCost,
        currentCoins: coins,
      );
      if (useCoins != true) return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditQuickTransactionPage(
          transaction: transaction,
          useCoins: shouldUseCoins,
          blockedEmails: _blockedEmails,
          dailyRemaining:
              _dailyLimits?['limits']?['quickTransactions']?['remaining'],
          isSubscribed: session.isSubscribed,
        ),
      ),
    );

    if (result is String) {
      ElegantNotification.error(
        title: Text("Error"),
        description: Text(result),
      ).show(context);
    } else if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      session.loadFreebieCounts();
      final giftCardAwarded = result['giftCardAwarded'] as bool?;
      final awardedCard = result['awardedCard'];
      final txn = result['transaction'] ?? result;

      final amt = (txn['amount'] as num?)?.toDouble();
      final recipient = (txn['counterpartyEmail'] ?? txn['counterpartyName'] ?? '').toString();
      final role = (txn['role'] ?? '').toString();
      final extraDetails = <String, String>{
        if (role.isNotEmpty) 'Role': role,
        if (giftCardAwarded == true && awardedCard != null) 'Bonus': '🎉 Gift card won!',
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            title: transaction != null ? 'Transaction Updated!' : 'Transaction Created!',
            amount: amt,
            recipientName: recipient.isNotEmpty ? recipient : null,
            transactionType: 'Quick Transaction',
            extraDetails: extraDetails,
          ),
        ),
      );

      if (giftCardAwarded == true && awardedCard != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ElegantNotification.success(
              title: Text("Congratulations!"),
              description: Text("You've won a gift card!"),
              action: GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GiftCardPage())),
                child: Text('View', style: TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          }
        });
      }
    }
  }

  Future<void> deleteQuickTransaction(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Quick Transaction',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!transactions.any((t) => t['_id'] == id)) return;

      final res = await ApiClient.delete('/api/quick-transactions/$id');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          transactions.removeWhere((t) => t['_id'] == id);
          filteredTransactions = List.from(transactions);
          _applyPinSort();
        });
        ElegantNotification.success(
          title: const Text("Deleted"),
          description: const Text("Quick transaction has been deleted."),
        ).show(context);
      } else {
        final error = json.decode(res.body)['error'];
        ElegantNotification.error(
          title: const Text("Error"),
          description: Text(error),
        ).show(context);
      }
    }
  }

  Future<void> clearQuickTransaction(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Quick Transaction',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to clear this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final index = transactions.indexWhere((t) => t['_id'] == id);
      if (index == -1) return;
      final previousValue = transactions[index]['cleared'] == true;
      final token = DateTime.now().microsecondsSinceEpoch;
      _clearActionTokens[id] = token;

      setState(() {
        transactions[index]['cleared'] = true;
        filteredTransactions = List.from(transactions);
        _applyPinSort();
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Quick transaction cleared'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () {
              _clearActionTokens.remove(id);
              setState(() {
                transactions[index]['cleared'] = previousValue;
                filteredTransactions = List.from(transactions);
                _applyPinSort();
              });
            },
          ),
          duration: const Duration(seconds: 4),
        ),
      );

      unawaited(Future.delayed(const Duration(seconds: 4), () async {
        if (_clearActionTokens[id] != token) return;
        _clearActionTokens.remove(id);
        final res =
            await ApiClient.put('/api/quick-transactions/$id/clear', body: {});
        if (res.statusCode == 200) {
          if (!mounted) return;
          ElegantNotification.success(
            title: Text("Success"),
            description: Text("Transaction has been successfully cleared!"),
          ).show(context);
        } else {
          final error = json.decode(res.body)['error'];
          if (!mounted) return;
          setState(() {
            transactions[index]['cleared'] = previousValue;
            filteredTransactions = List.from(transactions);
            _applyPinSort();
          });
          ElegantNotification.error(
            title: Text("Error"),
            description: Text(error),
          ).show(context);
        }
      }));
    }
  }

  Future<void> _duplicateQuickTransaction(
      Map<String, dynamic> transaction) async {
    final counterpartyEmail =
        (_counterpartyForViewer(transaction)?['email'] ?? '').toString();
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditQuickTransactionPage(
          prefillCounterpartyEmail: counterpartyEmail,
          initialAmount: transaction['amount']?.toString(),
          initialCurrency: transaction['currency']?.toString(),
          initialDescription: transaction['description']?.toString(),
          initialRole: _roleForViewer(transaction),
          blockedEmails: _blockedEmails,
          dailyRemaining:
              _dailyLimits?['limits']?['quickTransactions']?['remaining'],
          isSubscribed:
              Provider.of<SessionProvider>(context, listen: false).isSubscribed,
        ),
      ),
    );

    if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      Provider.of<SessionProvider>(context, listen: false).loadFreebieCounts();
      ElegantNotification.success(
        title: Text("Success"),
        description: Text("Transaction duplicated successfully!"),
      ).show(context);
    } else if (result is String && mounted) {
      ElegantNotification.error(
        title: Text("Error"),
        description: Text(result),
      ).show(context);
    }
  }

  String _buildReceiptText(Map<String, dynamic> transaction) {
    final counterparty = _counterpartyForViewer(transaction);
    final counterpartyName =
        (counterparty?['name'] ?? counterparty?['email'] ?? 'Unknown')
            .toString();
    final viewerRole =
        _roleForViewer(transaction) == 'lender' ? 'You Lent' : 'You Borrowed';
    final status = transaction['cleared'] == true ? 'Cleared' : 'Pending';
    return [
      'LenDen Quick Transaction',
      'Amount: ${_formatDisplayAmount(transaction['amount'], transaction['currency']?.toString())}',
      'Currency: ${transaction['currency'] ?? 'INR'}',
      'Role: $viewerRole',
      'Counterparty: $counterpartyName',
      'Description: ${transaction['description'] ?? ''}',
      'Date: ${transaction['date']?.toString().split('T').first ?? ''}',
      'Time: ${transaction['time'] ?? ''}',
      'Status: $status',
    ].join('\n');
  }

  Future<void> _showReceiptDialog(Map<String, dynamic> transaction) async {
    final receiptText = _buildReceiptText(transaction);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Quick Receipt'),
        content: SingleChildScrollView(
          child: Text(
            receiptText,
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receiptText));
              if (!mounted) return;
              Navigator.pop(context);
              ElegantNotification.success(
                title: Text("Copied"),
                description: Text("Quick transaction receipt copied."),
              ).show(context);
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Share.share(
                receiptText,
                subject: 'LenDen Quick Transaction',
              );
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupDisplayedTransactions(
      List<Map<String, dynamic>> items) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final transaction in items) {
      final rawDate =
          (transaction['date'] ?? transaction['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(rawDate)?.toLocal();
      final now = DateTime.now();
      String label = 'Older';
      if (date != null) {
        if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          label = 'Today';
        } else if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.subtract(const Duration(days: 1)).day) {
          label = 'Yesterday';
        } else {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          final start =
              DateTime(weekStart.year, weekStart.month, weekStart.day);
          if (!date.isBefore(start)) {
            label = 'This Week';
          }
        }
      }
      grouped.putIfAbsent(label, () => []).add(transaction);
    }
    final order = ['Today', 'Yesterday', 'This Week', 'Older'];
    final sorted = <String, List<Map<String, dynamic>>>{};
    for (final label in order) {
      if (grouped.containsKey(label)) {
        sorted[label] = grouped[label]!;
      }
    }
    return sorted;
  }

  String _settlementStatus(Map<String, dynamic> transaction) {
    return (transaction['settlementStatus'] ?? 'none').toString().toLowerCase();
  }

  String _settlementStatusLabel(Map<String, dynamic> transaction) {
    final status = _settlementStatus(transaction);
    if (status == 'pending') return 'Settlement Pending';
    if (status == 'accepted' || transaction['cleared'] == true) {
      return 'Settled';
    }
    if (status == 'rejected') return 'Settlement Rejected';
    return 'No Settlement';
  }

  bool _canRespondToSettlement(Map<String, dynamic> transaction) {
    final currentUserEmail = _currentUserEmail();
    final requestedBy =
        (transaction['settlementRequestedBy'] ?? '').toString().toLowerCase();
    return _settlementStatus(transaction) == 'pending' &&
        currentUserEmail != null &&
        requestedBy.isNotEmpty &&
        requestedBy != currentUserEmail;
  }

  void _payNow(Map<String, dynamic> transaction) {
    final id = (transaction['_id'] ?? '').toString();
    final counterparty = _counterpartyForViewer(transaction);
    final email = (counterparty?['email'] ?? '').toString();
    final phone = counterparty?['phone']?.toString();
    final amount = ((transaction['amount'] ?? 0) as num).toDouble();
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: email,
      amount: amount,
      description: transaction['description']?.toString() ?? 'Quick transaction settlement',
      counterpartyPhone: phone,
      quickTransactionId: id,
      onSuccess: () async {
        final index = transactions.indexWhere((t) => t['_id'] == id);
        if (index != -1) {
          setState(() {
            transactions[index]['cleared'] = true;
            filteredTransactions = List.from(transactions);
            _applyPinSort();
          });
        }
        final res = await ApiClient.put('/api/quick-transactions/$id/clear', body: {});
        if (!mounted) return;
        if (res.statusCode == 200) {
          showSnack(context, 'Payment successful! Transaction settled.');
        }
      },
    );
  }

  Future<void> _requestSettlement(Map<String, dynamic> transaction) async {
    final res = await ApiClient.post(
      '/api/quick-transactions/${transaction['_id']}/request-settlement',
      body: {},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) {
      // Refresh the list so users are re-enriched (raw API has string users, not objects)
      fetchQuickTransactions();
      ElegantNotification.success(
        title: Text("Settlement Requested"),
        description: Text("The other user can now accept or reject it."),
      ).show(context);
    } else {
      ElegantNotification.error(
        title: Text("Error"),
        description:
            Text((body['error'] ?? 'Unable to request settlement').toString()),
      ).show(context);
    }
  }

  Future<void> _respondSettlement(
      Map<String, dynamic> transaction, String action) async {
    if (action == 'accept') {
      // Accept = go to payment first; backend is marked settled only after payment succeeds
      final id = (transaction['_id'] ?? '').toString();
      final counterparty = _counterpartyForViewer(transaction);
      final email = (counterparty?['email'] ?? '').toString();
      final phone = counterparty?['phone']?.toString();
      final amount = ((transaction['amount'] ?? 0) as num).toDouble();
      LendenPaymentHelper.showPaymentSheet(
        context,
        counterpartyEmail: email,
        amount: amount,
        description: transaction['description']?.toString() ??
            'Quick transaction settlement',
        counterpartyPhone: phone,
        quickTransactionId: id,
        onSuccess: () async {
          // Payment succeeded → now confirm settlement on backend
          final res = await ApiClient.post(
            '/api/quick-transactions/$id/respond-settlement',
            body: {'action': 'accept'},
          );
          if (!mounted) return;
          if (res.statusCode == 200) {
            // Refresh list with enriched users
            fetchQuickTransactions();
            showSnack(context, 'Payment successful! Settlement complete.');
          } else {
            // Payment went through but backend update failed – still refresh
            fetchQuickTransactions();
            showSnack(context,
                'Payment done but status update failed. Please refresh.',
                isError: true);
          }
        },
      );
      return;
    }

    // Reject — no payment needed, update backend directly
    final res = await ApiClient.post(
      '/api/quick-transactions/${transaction['_id']}/respond-settlement',
      body: {'action': 'reject'},
    );
    final body = jsonDecode(res.body);
    if (res.statusCode == 200) {
      fetchQuickTransactions();
      ElegantNotification.success(
        title: const Text('Settlement Rejected'),
        description: Text(
            (body['message'] ?? 'Settlement rejected successfully').toString()),
      ).show(context);
    } else {
      ElegantNotification.error(
        title: const Text('Error'),
        description: Text(
            (body['error'] ?? 'Unable to reject settlement').toString()),
      ).show(context);
    }
  }

  Widget _buildRoleChip(String label, String value, IconData icon) {
    final isSelected = _roleFilter == value;
    return GestureDetector(
      onTap: () => _applyRoleFilter(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.cyan : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? AppColors.cyan : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearedChip() {
    final isSelected = filterBy == 'cleared';
    return GestureDetector(
      onTap: () {
        setState(() => filterBy = isSelected ? 'all' : 'cleared');
        fetchQuickTransactions();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey.shade700),
            const SizedBox(width: 6),
            Text(
              'Cleared',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey.shade800,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      width: 165,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  static const List<List<Color>> _quickStatPalette = [
    [Color(0xFFFF6B6B), Color(0xFFFFA3A3)],
    [Color(0xFF8B5CF6), Color(0xFFC4B5FD)],
    [Color(0xFFF4B400), Color(0xFFFDE68A)],
  ];

  Widget _buildStatusChip(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCards() {
    final visibleTransactions =
        filteredTransactions.isEmpty ? transactions : filteredTransactions;
    final total = visibleTransactions.length;
    final lent =
        visibleTransactions.where((t) => _roleForViewer(t) == 'lender').length;
    final totalValue = visibleTransactions.fold<double>(
      0.0,
      (sum, transaction) => sum + _displayNumericAmount(transaction),
    );
    final pendingValue = visibleTransactions.fold<double>(
      0.0,
      (sum, transaction) => transaction['cleared'] == true
          ? sum
          : sum + _displayNumericAmount(transaction),
    );
    final largest = visibleTransactions.fold<double>(
      0.0,
      (maxAmount, transaction) {
        final amount = _displayNumericAmount(transaction);
        return amount > maxAmount ? amount : maxAmount;
      },
    );
    final topCounterparty = _topQuickCounterpartyName(visibleTransactions);

    return SizedBox(
      height: 140,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildSummaryCard(
            title: 'Transactions',
            value: '$total',
            icon: Icons.receipt_long_rounded,
            colors: _quickStatPalette[0],
          ),
          _buildSummaryCard(
            title: 'Quick Value',
            value: _formatDisplayAmount(totalValue, _selectedDisplayCurrency),
            icon: Icons.currency_rupee_rounded,
            colors: _quickStatPalette[1],
          ),
          _buildSummaryCard(
            title: 'Pending Value',
            value: _formatDisplayAmount(pendingValue, _selectedDisplayCurrency),
            icon: Icons.pending_actions_rounded,
            colors: _quickStatPalette[2],
          ),
          _buildSummaryCard(
            title: 'Largest Quick',
            value: _formatDisplayAmount(largest, _selectedDisplayCurrency),
            icon: Icons.leaderboard_rounded,
            colors: _quickStatPalette[0],
          ),
          _buildSummaryCard(
            title: 'Top Counterparty',
            value: topCounterparty,
            icon: Icons.person_search_rounded,
            colors: _quickStatPalette[1],
          ),
          _buildSummaryCard(
            title: 'You Lent',
            value: '$lent',
            icon: Icons.arrow_upward_rounded,
            colors: _quickStatPalette[2],
          ),
        ],
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sort By',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            _buildSortOption('Date Created (Newest)', 'created_desc'),
            _buildSortOption('Date Created (Oldest)', 'created_asc'),
            _buildSortOption('Date Updated (Newest)', 'updated_desc'),
            _buildSortOption('Date Updated (Oldest)', 'updated_asc'),
            _buildSortOption('Amount (Low to High)', 'amount_asc'),
            _buildSortOption('Amount (High to Low)', 'amount_desc'),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions() {
    Navigator.of(context)
        .push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _QuickTransactionFilterPage(
          counterpartyOptions: _counterpartyOptions(),
        ),
      ),
    )
        .then((result) {
      if (result == null || !mounted) return;
      setState(() {
        filterBy = (result['status'] ?? 'all').toString();
        _roleFilter = (result['role'] ?? 'all').toString();
        _dateFilter = (result['date'] ?? 'all').toString();
        _selectedCounterparty = (result['counterparty'] ?? 'all').toString();
        _showFavouritesOnly = result['favourites'] == true;
        _showAll = false;
      });
      fetchQuickTransactions();
    });
  }

  Widget _buildSortOption(String label, String value) {
    final isSelected = sortBy == value;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? AppColors.cyan : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? Icon(Icons.check, color: AppColors.cyan) : null,
      onTap: () {
        setState(() => sortBy = value);
        Navigator.pop(context);
        fetchQuickTransactions();
      },
    );
  }

  Color _getNoteColor(int index) {
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

  @override
  Widget build(BuildContext context) {
    final displayedTransactions =
        _showAll ? filteredTransactions : filteredTransactions.take(3).toList();
    final counterpartyOptions = _counterpartyOptions();
    final groupedTransactions =
        _groupDisplayedTransactions(displayedTransactions);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          // Main content
          SafeArea(
            child: RefreshIndicator(
              onRefresh: fetchQuickTransactions,
              color: AppColors.cyan,
              child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: 90, bottom: MediaQuery.of(context).padding.bottom + 110),
              child: Column(
                children: [
                  Consumer<SessionProvider>(
                    builder: (context, session, child) {
                      if (session.isSubscribed) {
                        return Text('You have unlimited quick transactions.',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold));
                      }
                      final remaining = session.freeQuickTransactionsRemaining;
                      if (remaining == null) {
                        return SizedBox.shrink();
                      }
                      return Text(
                          'You have $remaining free quick transactions remaining.',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold));
                    },
                  ),
                  const SizedBox(height: 12),
                  if (!loading && error == null && transactions.isNotEmpty) ...[
                    _buildQuickStatCards(),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Align(
                        alignment: Alignment.center,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AnalyticsPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.analytics_outlined),
                          label: const Text('Open Quick Analytics'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildRoleChip('All', 'all', Icons.apps_rounded),
                              const SizedBox(width: 8),
                              _buildRoleChip('They Owe', 'lent',
                                  Icons.arrow_upward_rounded),
                              const SizedBox(width: 8),
                              _buildRoleChip('I Owe', 'borrowed',
                                  Icons.arrow_downward_rounded),
                              const SizedBox(width: 8),
                              _buildClearedChip(),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _toggleShowFavourites,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _showFavouritesOnly
                                        ? AppColors.cyan
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(
                                      color: _showFavouritesOnly
                                          ? AppColors.cyan
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.favorite,
                                        size: 18,
                                        color: _showFavouritesOnly
                                            ? Colors.white
                                            : Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Favourites',
                                        style: TextStyle(
                                          color: _showFavouritesOnly
                                              ? Colors.white
                                              : Colors.grey.shade800,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 28),
                            ],
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
                  ),
                  const SizedBox(height: 24),
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(27),
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.white, Colors.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search,
                                color: Colors.grey[400], size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() => searchQuery = value);
                                  _searchDebounceTimer?.cancel();
                                  _searchDebounceTimer = Timer(
                                    const Duration(milliseconds: 300),
                                    fetchQuickTransactions,
                                  );
                                },
                                onSubmitted: (_) =>
                                    FocusScope.of(context).unfocus(),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search by description, amount, or user...',
                                  hintStyle: TextStyle(
                                      color: Colors.grey[400], fontSize: 15),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            if (searchQuery.isNotEmpty)
                              IconButton(
                                icon: Icon(Icons.clear,
                                    color: Colors.grey[400], size: 20),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => searchQuery = '');
                                  _searchDebounceTimer?.cancel();
                                  fetchQuickTransactions();
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  if (_displayCurrencyError != null ||
                      _hasMissingConversionForQuickTransactions())
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
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
                                    'Conversion to $_selectedDisplayCurrency is not available for one or more quick transactions. Showing original currencies instead.',
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
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
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
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedCounterparty,
                                  icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded),
                                  items: counterpartyOptions
                                      .map(
                                        (item) => DropdownMenuItem<String>(
                                          value: item['email'],
                                          child: Text(
                                            item['label'] ?? 'All People',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    _applyCounterpartyFilter(value);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Show In',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildCurrencySelector(),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Filter and Sort buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Filter button
                        GestureDetector(
                          onTap: _showFilterOptions,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
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
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    filterBy == 'all'
                                        ? Icons.filter_alt_outlined
                                        : Icons.filter_alt,
                                    color: filterBy == 'all'
                                        ? Colors.black87
                                        : AppColors.cyan,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    _filterSummaryLabel(),
                                    style: TextStyle(
                                      color: !_hasActiveFilters()
                                          ? Colors.black87
                                          : AppColors.cyan,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Sort button
                        GestureDetector(
                          onTap: _showSortOptions,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
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
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sort,
                                      color: Colors.black87, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    _sortSummaryLabel(),
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_hasActiveFilters()) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _resetFilters,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
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
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(Icons.restart_alt_rounded,
                                        color: Color(0xFFD62828), size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Reset',
                                      style: TextStyle(
                                        color: Color(0xFFD62828),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Transactions List
                  loading
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: Colors.black87))
                      : error != null
                          ? _buildErrorState(error!, fetchQuickTransactions)
                          : filteredTransactions.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          _showFavouritesOnly
                                              ? Icons.star_border_rounded
                                              : Icons.receipt_long,
                                          size: 80, color: Colors.grey[400]),
                                      const SizedBox(height: 20),
                                      Text(
                                        _showFavouritesOnly
                                            ? 'No favourite transactions found'
                                            : searchQuery.isNotEmpty ||
                                                filterBy != 'all' ||
                                                _roleFilter != 'all' ||
                                                _dateFilter != 'all' ||
                                                _selectedCounterparty != 'all'
                                            ? 'No transactions found'
                                            : 'No quick transactions yet.',
                                        style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[600]),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _showFavouritesOnly
                                            ? 'Mark a transaction as favourite to see it here.'
                                            : searchQuery.isNotEmpty ||
                                                filterBy != 'all' ||
                                                _roleFilter != 'all' ||
                                                _dateFilter != 'all' ||
                                                _selectedCounterparty != 'all'
                                            ? 'Try adjusting your search or filters'
                                            : 'Tap the "+" button to create your first one!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey[500]),
                                      ),
                                      if (_hasActiveFilters()) ...[
                                        const SizedBox(height: 18),
                                        GestureDetector(
                                          onTap: _resetFilters,
                                          child: Container(
                                            padding: const EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Colors.orange,
                                                  Colors.white,
                                                  Colors.green,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 18,
                                                vertical: 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(22),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: const [
                                                  Icon(
                                                    Icons.refresh_rounded,
                                                    color: AppColors.cyan,
                                                    size: 18,
                                                  ),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Reset Filters',
                                                    style: TextStyle(
                                                      color: Colors.black87,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    ListView(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                          20.0, 8, 20.0, 20.0),
                                      children: groupedTransactions.entries
                                          .expand((entry) {
                                        final sectionIndex = groupedTransactions
                                            .keys
                                            .toList()
                                            .indexOf(entry.key);
                                        return <Widget>[
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                top: 6, bottom: 10),
                                            child: Text(
                                              entry.key,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          ...entry.value
                                              .asMap()
                                              .entries
                                              .map((item) {
                                            return Padding(
                                              key: ValueKey(
                                                  (item.value['_id'] ?? '')
                                                      .toString()),
                                              padding: const EdgeInsets.only(
                                                  bottom: 16),
                                              child: _buildQuickTransactionCard(
                                                item.value,
                                                sectionIndex + item.key,
                                              ),
                                            );
                                          }),
                                        ];
                                      }).toList(),
                                    ),
                                    if (filteredTransactions.length > 3)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 20.0),
                                        child: TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _showAll = !_showAll;
                                            });
                                          },
                                          child: Text(
                                            _showAll
                                                ? 'Show Less'
                                                : 'See All Transactions',
                                            style: const TextStyle(
                                              color: Color.fromARGB(
                                                  255, 6, 18, 20),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                ],
              ),
            ), // closes SingleChildScrollView
            ), // closes RefreshIndicator
          ),

          // Blue wave at top - reduced to half size
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 90, // Reduced from 180 to 90
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),

          // Header on wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        Navigator.pushReplacementNamed(
                            context, '/user/dashboard');
                      },
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Quick Transactions',
                          style: TextStyle(
                            fontSize: 22, // Reduced font size for smaller wave
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(color: Colors.black26, blurRadius: 4)
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => createOrEditQuickTransaction(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildQuickTransactionCard(Map<String, dynamic> transaction, int i) {
    final bool isCleared = transaction['cleared'] == true;
    final roleForViewer = _roleForViewer(transaction);
    final counterparty = _counterpartyForViewer(transaction);
    final settlementStatus = _settlementStatus(transaction);
    final settlementRequestedBy =
        (transaction['settlementRequestedBy'] ?? '').toString().toLowerCase();
    final requestedByYou = settlementRequestedBy.isNotEmpty &&
        settlementRequestedBy == _currentUserEmail();
    final _creatorEmail =
        (transaction['creatorEmail'] ?? '').toString().toLowerCase().trim();
    final creatorName = (() {
      for (final user in (transaction['users'] as List? ?? [])) {
        if (user is Map) {
          if ((user['email'] ?? '').toString().toLowerCase().trim() ==
              _creatorEmail) {
            return Map<String, dynamic>.from(user);
          }
        }
      }
      return <String, dynamic>{
        'name': transaction['creatorEmail'] ?? 'Unknown',
        'email': transaction['creatorEmail'] ?? 'Unknown',
      };
    })();
    final isPinned =
        _pinnedTransactionIds.contains((transaction['_id'] ?? '').toString());
    return Slidable(
        key: ValueKey((transaction['_id'] ?? '').toString()),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            if (!isCleared &&
                (settlementStatus == 'none' ||
                    settlementStatus == 'rejected') &&
                roleForViewer == 'lender')
              SlidableAction(
                onPressed: (_) => _requestSettlement(transaction),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                icon: Icons.handshake_rounded,
                label: 'Settle',
              ),
            SlidableAction(
              onPressed: (_) => _showReceiptDialog(transaction),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: Icons.share_rounded,
              label: 'Share',
            ),
          ],
        ),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            if (!isCleared)
              SlidableAction(
                onPressed: (_) =>
                    createOrEditQuickTransaction(transaction: transaction),
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                icon: Icons.edit,
                label: 'Edit',
              ),
            if (isCleared)
              SlidableAction(
                onPressed: (_) => deleteQuickTransaction(transaction['_id']),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete,
                label: 'Delete',
              ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: GestureDetector(
            onTap: () async {
              final didChange = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => QuickTransactionDetailPage(
                    transaction: transaction,
                  ),
                ),
              );
              if (didChange == true && mounted) fetchQuickTransactions();
            },
            child: Container(
              decoration: BoxDecoration(
                color: _getNoteColor(i),
                borderRadius: BorderRadius.circular(20),
              ),
              child: SingleChildScrollView(
              // Added vertical scroll
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            // Added horizontal scroll for amount
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              '${_formatDisplayAmount(transaction['amount'], transaction['currency']?.toString())} • ${(_displayCurrencyData?.canConvert((transaction['currency'] ?? 'INR').toString(), _selectedDisplayCurrency) ?? ((transaction['currency'] ?? 'INR').toString().toUpperCase() == _selectedDisplayCurrency.toUpperCase())) ? _selectedDisplayCurrency : (transaction['currency'] ?? 'INR')}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => _togglePinTransaction(
                              (transaction['_id'] ?? '').toString()),
                          icon: Icon(
                            isPinned ? Icons.star : Icons.star_border_rounded,
                            color:
                                isPinned ? Colors.amber[700] : Colors.grey[600],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _toggleQuickTransactionFavourite(transaction),
                          icon: Icon(
                            _isQuickTransactionFavourited(transaction)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: _isQuickTransactionFavourited(transaction)
                                ? Colors.redAccent
                                : Colors.grey[600],
                          ),
                        ),
                        if (isCleared)
                          Text(
                            'Cleared',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold),
                          ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              createOrEditQuickTransaction(
                                  transaction: transaction);
                            } else if (value == 'duplicate') {
                              _duplicateQuickTransaction(transaction);
                            } else if (value == 'delete') {
                              deleteQuickTransaction(transaction['_id']);
                            } else if (value == 'request_settlement') {
                              _requestSettlement(transaction);
                            } else if (value == 'accept_settlement') {
                              _respondSettlement(transaction, 'accept');
                            } else if (value == 'reject_settlement') {
                              _respondSettlement(transaction, 'reject');
                            } else if (value == 'pay_now') {
                              _payNow(transaction);
                            } else if (value == 'share') {
                              _showReceiptDialog(transaction);
                            } else if (value == 'pin') {
                              _togglePinTransaction(
                                  (transaction['_id'] ?? '').toString());
                            }
                          },
                          itemBuilder: (context) => [
                            if (!isCleared)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                            if (!isCleared &&
                                (settlementStatus == 'none' ||
                                    settlementStatus == 'rejected') &&
                                roleForViewer == 'lender')
                              const PopupMenuItem(
                                value: 'request_settlement',
                                child: Text('Request Settlement'),
                              ),
                            if (!isCleared && roleForViewer == 'borrower')
                              const PopupMenuItem(
                                value: 'pay_now',
                                child: Row(children: [
                                  Icon(Icons.payment_rounded, size: 16, color: AppColors.cyan),
                                  SizedBox(width: 8),
                                  Text('Pay Now (Real Money)', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            if (_canRespondToSettlement(transaction))
                              const PopupMenuItem(
                                value: 'accept_settlement',
                                child: Text('Accept Settlement'),
                              ),
                            if (_canRespondToSettlement(transaction))
                              const PopupMenuItem(
                                value: 'reject_settlement',
                                child: Text('Reject Settlement'),
                              ),
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicate'),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Text('Share / Receipt'),
                            ),
                            PopupMenuItem(
                              value: 'pin',
                              child: Text(isPinned ? 'Unpin' : 'Pin'),
                            ),
                            if (isCleared)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStatusChip(
                          isCleared
                              ? 'Cleared'
                              : settlementStatus == 'pending'
                                  ? 'Pending'
                                  : 'Open',
                          isCleared
                              ? Colors.green
                              : settlementStatus == 'pending'
                                  ? Colors.orange
                                  : Colors.blueGrey,
                          isCleared
                              ? Icons.check_circle_outline
                              : settlementStatus == 'pending'
                                  ? Icons.pending_actions_rounded
                                  : Icons.receipt_long_rounded,
                        ),
                        _buildStatusChip(
                          roleForViewer == 'lender'
                              ? 'You Lent'
                              : 'You Borrowed',
                          roleForViewer == 'lender'
                              ? const Color(0xFF1B58B8)
                              : const Color(0xFFD95F02),
                          roleForViewer == 'lender'
                              ? Icons.north_east_rounded
                              : Icons.south_west_rounded,
                        ),
                        if (isPinned)
                          _buildStatusChip(
                            'Pinned',
                            Colors.amber[800]!,
                            Icons.star_rounded,
                          ),
                        if (settlementStatus != 'none')
                          _buildStatusChip(
                            _settlementStatusLabel(transaction),
                            settlementStatus == 'accepted'
                                ? Colors.green
                                : settlementStatus == 'rejected'
                                    ? Colors.red
                                    : Colors.teal,
                            settlementStatus == 'accepted'
                                ? Icons.verified_rounded
                                : settlementStatus == 'rejected'
                                    ? Icons.close_rounded
                                    : Icons.handshake_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      // Added horizontal scroll for description
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        transaction['description'] ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      // Added horizontal scroll for user info
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            (counterparty?['name'] ??
                                    counterparty?['email'] ??
                                    'Unknown')
                                .toString(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          SizedBox(width: 16),
                          Text(
                            '${transaction['date']?.substring(0, 10)} at ${transaction['time']}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isCurrentUserCreator(transaction)
                          ? 'Created by you'
                          : 'Created by ${creatorName['name'] ?? creatorName['email'] ?? 'Unknown'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    if (!isCleared && roleForViewer == 'borrower') ...[
                      const SizedBox(height: 12),
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
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.payment_rounded, color: Colors.white, size: 18),
                            label: const Text('Pay Now (Real Money)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            onPressed: () => _payNow(transaction),
                          ),
                        ),
                      ),
                    ],
                    if (settlementStatus == 'pending') ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F7FB),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF7AD7EA)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              requestedByYou
                                  ? 'Settlement requested by you'
                                  : 'Settlement requested by the other user',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0087A8),
                              ),
                            ),
                            if (_canRespondToSettlement(transaction)) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _respondSettlement(
                                          transaction, 'reject'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      child: const Text(
                                        'Reject',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _respondSettlement(
                                          transaction, 'accept'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                      ),
                                      child: const Text(
                                        'Accept',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
  }
}

class _QuickTransactionFilterPage extends StatefulWidget {
  final List<Map<String, String>> counterpartyOptions;

  const _QuickTransactionFilterPage({
    required this.counterpartyOptions,
  });

  @override
  State<_QuickTransactionFilterPage> createState() =>
      _QuickTransactionFilterPageState();
}

class _QuickTransactionFilterPageState
    extends State<_QuickTransactionFilterPage> {
  String _status = 'all';
  String _role = 'all';
  String _date = 'all';
  String _counterparty = 'all';
  bool _favouritesOnly = false;

  String _counterpartyLabel(String value) {
    final match = widget.counterpartyOptions.firstWhere(
      (item) => item['email'] == value,
      orElse: () => const {'label': 'All People'},
    );
    return match['label'] ?? 'All People';
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
    Color backgroundColor = const Color(0xFFF9FCFD),
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppColors.cyan),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceRow({
    required String label,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = groupValue == value;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => onChanged(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE9F8FC) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.cyan
                : Colors.grey.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: groupValue,
              activeColor: AppColors.cyan,
              onChanged: onChanged,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCounterpartyPicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 18),
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFDFEFE),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4FBFE),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.people_alt_outlined,
                              color: AppColors.cyan,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Choose Counterparty',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: ListView.builder(
                        itemCount: widget.counterpartyOptions.length,
                        itemBuilder: (context, index) {
                          final item = widget.counterpartyOptions[index];
                          final email = item['email'] ?? 'all';
                          final label = item['label'] ?? 'All People';
                          final selected = _counterparty == email;
                          final isAll = email == 'all';
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.of(sheetContext).pop(email),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFEAF9FD)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.cyan
                                      : Colors.grey.withValues(alpha: 0.18),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: email,
                                    groupValue: _counterparty,
                                    activeColor: AppColors.cyan,
                                    onChanged: (_) =>
                                        Navigator.of(sheetContext).pop(email),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isAll
                                          ? const Color(0xFFEDF7FA)
                                          : const Color(0xFFF4F7FF),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      isAll
                                          ? Icons.groups_rounded
                                          : Icons.person_rounded,
                                      color: isAll
                                          ? AppColors.cyan
                                          : const Color(0xFF3B82F6),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                            label,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: selected
                                                  ? FontWeight.w800
                                                  : FontWeight.w700,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          isAll
                                              ? 'Show every person in quick transactions'
                                              : 'Filter quick transactions for this counterparty',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (selected == null) return;
    setState(() => _counterparty = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          'Quick Transaction Filters',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildSection(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Status',
                    subtitle: 'Choose the transaction status you want to see.',
                    backgroundColor: const Color(0xFFFFFCF7),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: 'All Transactions',
                          value: 'all',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'Cleared Only',
                          value: 'cleared',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'Not Cleared',
                          value: 'not_cleared',
                          groupValue: _status,
                          onChanged: (value) =>
                              setState(() => _status = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.swap_vert_circle_outlined,
                    title: 'Role',
                    subtitle: 'Focus on what you lent or borrowed.',
                    backgroundColor: const Color(0xFFF7FAFF),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: 'All Roles',
                          value: 'all',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'You Lent',
                          value: 'lent',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'You Borrowed',
                          value: 'borrowed',
                          groupValue: _role,
                          onChanged: (value) =>
                              setState(() => _role = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.date_range_rounded,
                    title: 'Date Range',
                    subtitle: 'Pick a quick date window for the list.',
                    backgroundColor: const Color(0xFFF7FBF8),
                    child: Column(
                      children: [
                        _buildChoiceRow(
                          label: 'All Time',
                          value: 'all',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'Today',
                          value: 'today',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'This Week',
                          value: 'week',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                        _buildChoiceRow(
                          label: 'This Month',
                          value: 'month',
                          groupValue: _date,
                          onChanged: (value) =>
                              setState(() => _date = value ?? 'all'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.people_alt_outlined,
                    title: 'Counterparty',
                    subtitle: 'Pick a person with a cleaner full list view.',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _showCounterpartyPicker,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEAF7FB),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.people_alt_outlined,
                                color: AppColors.cyan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Selected Person',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      _counterpartyLabel(_counterparty),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F8FA),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    icon: Icons.favorite_border_rounded,
                    title: 'Favourite Filter',
                    subtitle:
                        'The enable or disable control is shown in front.',
                    backgroundColor: const Color(0xFFFFF8FA),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: _favouritesOnly,
                            activeColor: AppColors.cyan,
                            onChanged: (value) =>
                                setState(() => _favouritesOnly = value),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                'Show Favourites Only',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _status = 'all';
                          _role = 'all';
                          _date = 'all';
                          _counterparty = 'all';
                          _favouritesOnly = false;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.cyan),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          color: AppColors.cyan,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'status': _status,
                          'role': _role,
                          'date': _date,
                          'counterparty': _counterparty,
                          'favourites': _favouritesOnly,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// _QuickTransactionDialog removed — replaced by CreateEditQuickTransactionPage

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
