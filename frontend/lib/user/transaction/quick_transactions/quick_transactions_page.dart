import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import '../../../utils/share_utils.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/currency_display.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/payment_success_page.dart';
import '../../digitise/gift_card_page.dart';
import '../analytics_page.dart';
import '../../wallet/widgets/payment_sheet.dart';
import './create_edit_quick_transaction_page.dart';
import './quick_transaction_detail_page.dart';
import './recurring_templates_page.dart';
import './scheduled_transactions_page.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/wave_widget.dart';
import '../../../widgets/budget_limit_banner.dart';
import '../../../widgets/app_widgets.dart';
import '../../budget/budget_messages_page.dart';
import '../../budget/budget_planning_page.dart';
import './widgets/quick_transaction_filter_page.dart';

const _kCategories = [
  {'key': 'food',          'label': 'Food',          'icon': Icons.restaurant_rounded},
  {'key': 'transport',     'label': 'Transport',     'icon': Icons.directions_car_rounded},
  {'key': 'accommodation', 'label': 'Stay',          'icon': Icons.hotel_rounded},
  {'key': 'entertainment', 'label': 'Fun',           'icon': Icons.sports_esports_rounded},
  {'key': 'shopping',      'label': 'Shopping',      'icon': Icons.shopping_cart_rounded},
  {'key': 'utilities',     'label': 'Utilities',     'icon': Icons.electrical_services_rounded},
  {'key': 'medical',       'label': 'Medical',       'icon': Icons.local_hospital_rounded},
  {'key': 'education',     'label': 'Education',     'icon': Icons.school_rounded},
  {'key': 'personal',      'label': 'Personal',      'icon': Icons.person_rounded},
  {'key': 'rent',          'label': 'Rent',          'icon': Icons.home_rounded},
  {'key': 'business',      'label': 'Business',      'icon': Icons.business_center_rounded},
  {'key': 'travel',        'label': 'Travel',        'icon': Icons.flight_rounded},
  {'key': 'other',         'label': 'Other',         'icon': Icons.more_horiz_rounded},
];

IconData _catIcon(String? key) {
  final cat = _kCategories.firstWhere((c) => c['key'] == key, orElse: () => _kCategories.last);
  return cat['icon'] as IconData;
}

String _catLabel(String? key) {
  return (_kCategories.firstWhere((c) => c['key'] == key, orElse: () => _kCategories.last)['label'] as String);
}

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

class _QuickTransactionsPageState extends State<QuickTransactionsPage>
    with CurrencyDisplayMixin<QuickTransactionsPage> {
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
  String _categoryFilter = 'all';
  bool _showFavouritesOnly = false;
  bool _showAll = false;
  int _qtPage = 1;
  bool _qtHasMore = false;
  bool _qtLoadingMore = false;
  static const int _qtPageSize = 20;
  Set<String> _blockedEmails = {};
  Set<String> _pinnedTransactionIds = {};
  int _bannerRefreshTrigger = 0;
  Map<String, dynamic>? _dailyLimits;
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
    loadCurrencies(
      onError: (_) {
        if (mounted) {
          setState(() => _displayCurrencyError =
              AppLocalizations.of(context).t('currency_conversion_unavailable'));
        }
      },
    );
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
    if (session.hasFeature('quick_transactions')) return;
    try {
      final res = await ApiClient.get('/api/limits/daily');
      if (res.statusCode == 200) {
        setState(() {
          _dailyLimits = jsonDecode(res.body);
        });
      }
    } catch (_) {}
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
    final t = AppLocalizations.of(context).t;
    final seen = <String>{};
    final options = <Map<String, String>>[
      {'email': 'all', 'label': t('all_people_label')}
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

  String _formatDisplayAmount(dynamic amount, String? originalCurrency) {
    final numericAmount = amount is num
        ? amount.toDouble()
        : double.tryParse((amount ?? 0).toString()) ?? 0.0;
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
      return '$originalSymbol${numericAmount.toStringAsFixed(2)}';
    }
    final converted = currencyData?.convert(
          numericAmount,
          sourceCurrency,
          targetCurrency,
        ) ??
        numericAmount;
    final symbol =
        currencyData?.symbolFor(targetCurrency) ?? targetCurrency;
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  double _displayNumericAmount(Map<String, dynamic> transaction) {
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

  bool _hasMissingConversionForQuickTransactions() {
    if (selectedCurrency.toUpperCase() == 'INR') return false;
    if (currencyData == null) return true;
    for (final transaction in filteredTransactions) {
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
    if (!session.hasFeature('quick_transactions')) {
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

    // Rule: if daily limit is expired â†’ hard block; free attempts are also paused.
    if (!session.hasFeature('quick_transactions') &&
        transaction == null &&
        dailyQuickRemaining != null &&
        dailyQuickRemaining <= 0) {
      showDailyLimitDialog(context,
          message: AppLocalizations.of(context)
              .t('daily_quick_transactions_limit_reached_message'));
      return;
    }

    // Daily limit OK but free attempts exhausted â†’ offer coins.
    final shouldUseCoins = !session.hasFeature('quick_transactions') &&
        transaction == null &&
        (session.freeQuickTransactionsRemaining ?? 0) <= 0;

    if (shouldUseCoins) {
      final int coinCost = session.quickTransactionCoinCost;
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
        featureName:
            AppLocalizations.of(context).t('quick_transaction_feature_name'),
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
          dailyRemaining: _dailyLimits?['limits']?['quickTransactions']
              ?['remaining'],
          isSubscribed: session.hasFeature('quick_transactions'),
        ),
      ),
    );

    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
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
        title: Text(t('error')),
        description: Text(result),
      ).show(context);
    } else if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      setState(() => _bannerRefreshTrigger++);
      session.loadFreebieCounts();
      final giftCardAwarded = result['giftCardAwarded'] as bool?;
      final awardedCard = result['awardedCard'];
      final txn = result['transaction'] ?? result;

      final amt = (txn['amount'] as num?)?.toDouble();
      final recipient =
          (txn['counterpartyEmail'] ?? txn['counterpartyName'] ?? '')
              .toString();
      final role = (txn['role'] ?? '').toString();
      final extraDetails = <String, String>{
        if (role.isNotEmpty) t('role_label_colon'): role,
        if (giftCardAwarded == true && awardedCard != null)
          t('bonus_label_colon'): t('gift_card_won_emoji'),
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            title: transaction != null
                ? t('transaction_updated_exclaim')
                : t('transaction_created_exclaim'),
            amount: amt,
            recipientName: recipient.isNotEmpty ? recipient : null,
            transactionType: t('quick_transaction_feature_name'),
            extraDetails: extraDetails,
          ),
        ),
      );

      if (giftCardAwarded == true && awardedCard != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ElegantNotification.success(
              title: Text(t('congratulations_title')),
              description: Text(t('won_gift_card_message')),
              action: GestureDetector(
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child:
                    Text(t('view_label'), style: TextStyle(color: Colors.blue)),
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
      final aPinned =
          _pinnedTransactionIds.contains((a['_id'] ?? '').toString());
      final bPinned =
          _pinnedTransactionIds.contains((b['_id'] ?? '').toString());
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
        _categoryFilter != 'all' ||
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

  void _resetFilters() {
    setState(() {
      searchQuery = '';
      _searchController.clear();
      filterBy = 'all';
      _roleFilter = 'all';
      _dateFilter = 'all';
      _selectedCounterparty = 'all';
      _categoryFilter = 'all';
      _showFavouritesOnly = false;
      _showAll = false;
    });
    fetchQuickTransactions();
  }

  Future<void> fetchQuickTransactions({bool append = false}) async {
    if (append) {
      setState(() => _qtLoadingMore = true);
    } else {
      _qtPage = 1;
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      // Build query params from current filter state
      final params = <String, String>{};
      if (searchQuery.isNotEmpty) params['search'] = searchQuery;
      if (sortBy != 'created_desc') params['sortBy'] = sortBy;
      if (filterBy != 'all') params['filterBy'] = filterBy;
      if (_roleFilter != 'all')
        params['role'] = _roleFilter == 'lent' ? 'lender' : 'borrower';
      if (_dateFilter != 'all') params['dateFilter'] = _dateFilter;
      if (_showFavouritesOnly) params['favouritesOnly'] = 'true';
      if (_selectedCounterparty != 'all')
        params['counterparty'] = _selectedCounterparty;
      if (_categoryFilter != 'all') params['category'] = _categoryFilter;

      final fetchPage = append ? _qtPage + 1 : 1;
      params['page'] = fetchPage.toString();
      params['limit'] = _qtPageSize.toString();

      final queryString = params.isEmpty
          ? ''
          : '?' +
              params.entries
                  .map((e) =>
                      '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
                  .join('&');

      final res = await ApiClient.get('/api/quick-transactions$queryString');
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        final rawTransactions = body['quickTransactions'];
        final fetchedTransactions = rawTransactions is List
            ? rawTransactions.map((t) => Map<String, dynamic>.from(t is Map ? t : {})).toList()
            : <Map<String, dynamic>>[];
        setState(() {
          if (append) {
            transactions = [...transactions, ...fetchedTransactions];
            _qtPage = fetchPage;
          } else {
            transactions = fetchedTransactions;
            _qtPage = 1;
          }
          filteredTransactions = List.from(transactions);
          _qtHasMore = body['hasMore'] == true;
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
          _qtLoadingMore = false;
        });
      } else {
        setState(() {
          error = AppLocalizations.of(context).t('failed_to_load_transactions');
          loading = false;
          _qtLoadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        error = AppLocalizations.of(context).t('failed_to_load_transactions');
        loading = false;
        _qtLoadingMore = false;
      });
    }
  }

  Future<void> createOrEditQuickTransaction(
      {Map<String, dynamic>? transaction}) async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (_blockedEmails.isEmpty) {
      await _loadBlockedUsers();
    }
    if (!session.hasFeature('quick_transactions')) {
      await Future.wait([
        session.loadFreebieCounts(),
        _loadDailyLimits(),
      ]);
    }
    final dailyQuickRemaining =
        _dailyLimits?['limits']?['quickTransactions']?['remaining'] as int?;

    // Daily limit expired â†’ hard block (free attempts also paused until tomorrow).
    if (!session.hasFeature('quick_transactions') &&
        transaction == null &&
        dailyQuickRemaining != null &&
        dailyQuickRemaining <= 0) {
      showDailyLimitDialog(context,
          message: t('daily_quick_transactions_limit_reached_message'));
      return;
    }

    // Daily limit OK but free attempts exhausted â†’ offer coins.
    final shouldUseCoins = !session.hasFeature('quick_transactions') &&
        transaction == null &&
        (session.freeQuickTransactionsRemaining ?? 0) <= 0;

    if (shouldUseCoins) {
      final int coinCost = session.quickTransactionCoinCost;
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
        featureName: t('quick_transaction_feature_name'),
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
          dailyRemaining: _dailyLimits?['limits']?['quickTransactions']
              ?['remaining'],
          isSubscribed: session.hasFeature('quick_transactions'),
        ),
      ),
    );

    if (result is String) {
      ElegantNotification.error(
        title: Text(t('error')),
        description: Text(result),
      ).show(context);
    } else if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      setState(() => _bannerRefreshTrigger++);
      session.loadFreebieCounts();
      final giftCardAwarded = result['giftCardAwarded'] as bool?;
      final awardedCard = result['awardedCard'];
      final txn = result['transaction'] ?? result;

      final amt = (txn['amount'] as num?)?.toDouble();
      final recipient =
          (txn['counterpartyEmail'] ?? txn['counterpartyName'] ?? '')
              .toString();
      final role = (txn['role'] ?? '').toString();
      final extraDetails = <String, String>{
        if (role.isNotEmpty) t('role_label_colon'): role,
        if (giftCardAwarded == true && awardedCard != null)
          t('bonus_label_colon'): t('gift_card_won_emoji'),
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessPage(
            title: transaction != null
                ? t('transaction_updated_exclaim')
                : t('transaction_created_exclaim'),
            amount: amt,
            recipientName: recipient.isNotEmpty ? recipient : null,
            transactionType: t('quick_transaction_feature_name'),
            extraDetails: extraDetails,
          ),
        ),
      );

      if (giftCardAwarded == true && awardedCard != null) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            ElegantNotification.success(
              title: Text(t('congratulations_title')),
              description: Text(t('won_gift_card_message')),
              action: GestureDetector(
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => GiftCardPage())),
                child:
                    Text(t('view_label'), style: TextStyle(color: Colors.blue)),
              ),
            ).show(context);
          }
        });
      }
    }
  }

  Future<void> deleteQuickTransaction(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('delete_quick_transaction_title'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(dialogContext))),
        content: Text(t('confirm_delete_quick_transaction'),
            style:
                TextStyle(color: AppThemeColors.secondaryText(dialogContext))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel'),
                style: TextStyle(
                    color: AppThemeColors.secondaryText(dialogContext))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text(t('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!transactions.any((txn) => txn['_id'] == id)) return;

      final res = await ApiClient.delete('/api/quick-transactions/$id');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          transactions.removeWhere((txn) => txn['_id'] == id);
          filteredTransactions = List.from(transactions);
          _applyPinSort();
        });
        ElegantNotification.success(
          title: Text(t('deleted_label')),
          description: Text(t('quick_transaction_deleted_message')),
        ).show(context);
      } else {
        final error = json.decode(res.body)['error'];
        ElegantNotification.error(
          title: Text(t('error')),
          description: Text(error),
        ).show(context);
      }
    }
  }

  Future<void> clearQuickTransaction(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('clear_quick_transaction_title'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(dialogContext))),
        content: Text(t('confirm_clear_transaction_message'),
            style:
                TextStyle(color: AppThemeColors.secondaryText(dialogContext))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel'),
                style: TextStyle(
                    color: AppThemeColors.secondaryText(dialogContext))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                Text(t('clear'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final index = transactions.indexWhere((txn) => txn['_id'] == id);
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
          content: Text(t('quick_transaction_cleared_message')),
          action: SnackBarAction(
            label: t('undo_label'),
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
            title: Text(t('success')),
            description: Text(t('transaction_cleared_success_message')),
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
            title: Text(t('error')),
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
          dailyRemaining: _dailyLimits?['limits']?['quickTransactions']
              ?['remaining'],
          isSubscribed:
              Provider.of<SessionProvider>(context, listen: false).isSubscribed,
        ),
      ),
    );

    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    if (result is Map<String, dynamic>) {
      fetchQuickTransactions();
      Provider.of<SessionProvider>(context, listen: false).loadFreebieCounts();
      ElegantNotification.success(
        title: Text(t('success')),
        description: Text(t('transaction_duplicated_success_message')),
      ).show(context);
    } else if (result is String && mounted) {
      ElegantNotification.error(
        title: Text(t('error')),
        description: Text(result),
      ).show(context);
    }
  }

  String _buildReceiptText(Map<String, dynamic> transaction, {String appLink = ''}) {
    final t = AppLocalizations.of(context).t;
    final counterparty = _counterpartyForViewer(transaction);
    final counterpartyName =
        (counterparty?['name'] ?? counterparty?['email'] ?? t('unknown_label'))
            .toString();
    final viewerRole = _roleForViewer(transaction) == 'lender'
        ? t('you_lent_label')
        : t('you_borrowed_label');
    final status =
        transaction['cleared'] == true ? t('cleared') : t('pending_label');
    final lines = [
      t('lenden_quick_transaction_label'),
      '${t('amount_colon_label')} ${_formatDisplayAmount(transaction['amount'], transaction['currency']?.toString())}',
      '${t('currency_colon_label')} ${transaction['currency'] ?? 'INR'}',
      '${t('role_label_colon')} $viewerRole',
      '${t('counterparty_colon_label')} $counterpartyName',
      '${t('description_colon_label')} ${transaction['description'] ?? ''}',
      '${t('date_colon_label')} ${transaction['date']?.toString().split('T').first ?? ''}',
      '${t('time_colon_label')} ${transaction['time'] ?? ''}',
      '${t('status_colon_label')} $status',
    ];
    if (appLink.isNotEmpty) {
      lines.addAll(['â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€', 'ðŸ“± Shared via LenDen', appLink]);
    }
    return lines.join('\n');
  }

  Future<void> _showReceiptDialog(Map<String, dynamic> transaction) async {
    final t = AppLocalizations.of(context).t;
    final appLink = await fetchAppInviteLink();
    final receiptText = _buildReceiptText(transaction, appLink: appLink);
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t('quick_receipt_title'),
            style: TextStyle(color: AppThemeColors.primaryText(dialogContext))),
        content: SingleChildScrollView(
          child: Text(
            receiptText,
            style: TextStyle(
                height: 1.5, color: AppThemeColors.primaryText(dialogContext)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('close')),
          ),
          ElevatedButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: receiptText));
              if (!mounted) return;
              Navigator.pop(dialogContext);
              ElegantNotification.success(
                title: Text(t('copied_label')),
                description:
                    Text(t('quick_transaction_receipt_copied_message')),
              ).show(context);
            },
            child: Text(t('copy_label')),
          ),
          ElevatedButton(
            onPressed: () async {
              await Share.share(
                receiptText,
                subject: t('lenden_quick_transaction_label'),
              );
              if (!mounted) return;
              Navigator.pop(dialogContext);
            },
            child: Text(t('share')),
          ),
        ],
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupDisplayedTransactions(
      List<Map<String, dynamic>> items) {
    final t = AppLocalizations.of(context).t;
    final todayLabel = t('today');
    final yesterdayLabel = t('yesterday');
    final thisWeekLabel = t('this_week');
    final olderLabel = t('older_label');
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final transaction in items) {
      final rawDate =
          (transaction['date'] ?? transaction['createdAt'] ?? '').toString();
      final date = DateTime.tryParse(rawDate)?.toLocal();
      final now = DateTime.now();
      String label = olderLabel;
      if (date != null) {
        if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          label = todayLabel;
        } else if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.subtract(const Duration(days: 1)).day) {
          label = yesterdayLabel;
        } else {
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          final start =
              DateTime(weekStart.year, weekStart.month, weekStart.day);
          if (!date.isBefore(start)) {
            label = thisWeekLabel;
          }
        }
      }
      grouped.putIfAbsent(label, () => []).add(transaction);
    }
    final order = [todayLabel, yesterdayLabel, thisWeekLabel, olderLabel];
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
    final t = AppLocalizations.of(context).t;
    final status = _settlementStatus(transaction);
    if (status == 'pending') return t('settlement_pending_label');
    if (status == 'accepted' || transaction['cleared'] == true) {
      return t('settled_label');
    }
    if (status == 'rejected') return t('settlement_rejected_label');
    return t('no_settlement_label');
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
    final t = AppLocalizations.of(context).t;
    final id = (transaction['_id'] ?? '').toString();
    final counterparty = _counterpartyForViewer(transaction);
    final email = (counterparty?['email'] ?? '').toString();
    final amount = ((transaction['amount'] ?? 0) as num).toDouble();
    // /pay is one atomic call: debits the payer's wallet, credits the
    // counterparty's, and marks the transaction settled server-side â€” no
    // separate /clear call trusting the client afterward.
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: email,
      amount: amount,
      description: transaction['description']?.toString() ??
          t('quick_transaction_settlement_label'),
      payEndpoint: '/api/quick-transactions/$id/pay',
      onSuccess: () {
        final index = transactions.indexWhere((txn) => txn['_id'] == id);
        if (index != -1) {
          setState(() {
            transactions[index]['cleared'] = true;
            filteredTransactions = List.from(transactions);
            _applyPinSort();
          });
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentSuccessPage(
              title: t('payment_successful_exclaim'),
              amount: amount,
              recipientName: email.isNotEmpty ? email : null,
              transactionType: t('quick_transaction_settlement_label'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _requestSettlement(Map<String, dynamic> transaction) async {
    final t = AppLocalizations.of(context).t;
    final res = await ApiClient.post(
      '/api/quick-transactions/${transaction['_id']}/request-settlement',
      body: {},
    );
    final body = jsonDecode(res.body);
    if (!mounted) return;
    if (res.statusCode == 200) {
      // Refresh the list so users are re-enriched (raw API has string users, not objects)
      fetchQuickTransactions();
      ElegantNotification.success(
        title: Text(t('settlement_requested_title')),
        description: Text(t('other_user_can_accept_or_reject_message')),
      ).show(context);
    } else {
      ElegantNotification.error(
        title: Text(t('error')),
        description: Text(
            (body['error'] ?? t('unable_to_request_settlement_message'))
                .toString()),
      ).show(context);
    }
  }

  Future<void> _respondSettlement(
      Map<String, dynamic> transaction, String action) async {
    final t = AppLocalizations.of(context).t;
    if (action == 'accept') {
      // Accepting pays the requester directly â€” /pay atomically transfers the
      // wallet money and flips settlementStatus pending â†’ accepted together,
      // so there's no separate unverified "confirm settlement" call after.
      final id = (transaction['_id'] ?? '').toString();
      final counterparty = _counterpartyForViewer(transaction);
      final email = (counterparty?['email'] ?? '').toString();
      final amount = ((transaction['amount'] ?? 0) as num).toDouble();
      LendenPaymentHelper.showPaymentSheet(
        context,
        counterpartyEmail: email,
        amount: amount,
        description: transaction['description']?.toString() ??
            t('quick_transaction_settlement_label'),
        payEndpoint: '/api/quick-transactions/$id/pay',
        onSuccess: () {
          fetchQuickTransactions();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PaymentSuccessPage(
                title: t('payment_successful_exclaim'),
                amount: amount,
                recipientName: email.isNotEmpty ? email : null,
                transactionType: t('quick_transaction_settlement_label'),
              ),
            ),
          );
        },
      );
      return;
    }

    // Reject â€” no payment needed, update backend directly
    final res = await ApiClient.post(
      '/api/quick-transactions/${transaction['_id']}/respond-settlement',
      body: {'action': 'reject'},
    );
    final body = jsonDecode(res.body);
    if (!mounted) return;
    if (res.statusCode == 200) {
      fetchQuickTransactions();
      ElegantNotification.success(
        title: Text(t('settlement_rejected_title')),
        description: Text(
            (body['message'] ?? t('settlement_rejected_success_message'))
                .toString()),
      ).show(context);
    } else {
      ElegantNotification.error(
        title: Text(t('error')),
        description: Text(
            (body['error'] ?? t('unable_to_reject_settlement_message'))
                .toString()),
      ).show(context);
    }
  }

  Widget _buildAttemptsChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  void _showSortOptions() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeColors.cardBg(context),
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
              t('sort_by_label'),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context)),
            ),
            SizedBox(height: 16),
            _buildSortOption(t('date_created_newest_label'), 'created_desc'),
            _buildSortOption(t('date_created_oldest_label'), 'created_asc'),
            _buildSortOption(t('date_updated_newest_label'), 'updated_desc'),
            _buildSortOption(t('date_updated_oldest_label'), 'updated_asc'),
            _buildSortOption(t('amount_low_to_high_label'), 'amount_asc'),
            _buildSortOption(t('amount_high_to_low_label'), 'amount_desc'),
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
        builder: (context) => QuickTransactionFilterPage(
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
        _categoryFilter = (result['category'] ?? 'all').toString();
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
          color:
              isSelected ? AppColors.cyan : AppThemeColors.primaryText(context),
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

  // â”€â”€â”€ Compact filter bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildFilterBar(String Function(String) t) {
    final counterpartyOptions = _counterpartyOptions();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.scaffoldBg(context),
        border: Border(bottom: BorderSide(color: AppThemeColors.divider(context), width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: search + filter + sort
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppThemeColors.divider(context)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 10),
                      Icon(Icons.search, size: 17, color: AppThemeColors.mutedText(context)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context)),
                          decoration: InputDecoration(
                            hintText: t('search_by_description_amount_user_hint'),
                            hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            isDense: true,
                          ),
                          onChanged: (v) {
                            setState(() => searchQuery = v);
                            _searchDebounceTimer?.cancel();
                            _searchDebounceTimer = Timer(const Duration(milliseconds: 300), fetchQuickTransactions);
                          },
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => searchQuery = '');
                            fetchQuickTransactions();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Icon(Icons.close_rounded, size: 16, color: AppThemeColors.mutedText(context)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Filter button
              _buildBarIconBtn(
                icon: _hasActiveFilters() ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
                color: _hasActiveFilters() ? AppColors.cyan : AppThemeColors.secondaryText(context),
                onTap: _showFilterOptions,
                badge: _hasActiveFilters(),
              ),
              const SizedBox(width: 6),
              // Sort button
              _buildBarIconBtn(
                icon: Icons.sort_rounded,
                color: sortBy != 'created_desc' ? AppColors.cyan : AppThemeColors.secondaryText(context),
                onTap: _showSortOptions,
              ),
              const SizedBox(width: 6),
              // Currency selector
              buildCurrencySelector(),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: role chips + person filter + favourites + reset
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMiniChip(t('all'), _roleFilter == 'all', Icons.apps_rounded, () => _applyRoleFilter('all')),
                const SizedBox(width: 6),
                _buildMiniChip(t('they_owe_label'), _roleFilter == 'lent', Icons.north_east_rounded, () => _applyRoleFilter('lent'), activeColor: const Color(0xFF1B58B8)),
                const SizedBox(width: 6),
                _buildMiniChip(t('i_owe_label'), _roleFilter == 'borrowed', Icons.south_west_rounded, () => _applyRoleFilter('borrowed'), activeColor: const Color(0xFFD95F02)),
                const SizedBox(width: 6),
                _buildMiniChip(t('cleared'), filterBy == 'cleared', Icons.check_circle_rounded, () {
                  setState(() => filterBy = filterBy == 'cleared' ? 'all' : 'cleared');
                  fetchQuickTransactions();
                }, activeColor: Colors.green),
                const SizedBox(width: 6),
                _buildMiniChip(t('favourites_label'), _showFavouritesOnly, Icons.favorite_rounded, _toggleShowFavourites, activeColor: Colors.redAccent),
                if (counterpartyOptions.length > 1) ...[
                  const SizedBox(width: 6),
                  _buildPersonFilter(t, counterpartyOptions),
                ],
                if (_hasActiveFilters()) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _resetFilters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.restart_alt_rounded, size: 13, color: Colors.red),
                        const SizedBox(width: 4),
                        Text(t('reset_label'), style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarIconBtn({required IconData icon, required Color color, required VoidCallback onTap, bool badge = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: badge ? AppColors.cyan.withValues(alpha: 0.1) : AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: badge ? AppColors.cyan.withValues(alpha: 0.4) : AppThemeColors.divider(context)),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          if (badge)
            Positioned(
              top: -3, right: -3,
              child: Container(
                width: 9, height: 9,
                decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(String label, bool selected, IconData icon, VoidCallback onTap, {Color? activeColor}) {
    final color = activeColor ?? AppColors.cyan;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : AppThemeColors.divider(context)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: selected ? color : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? color : AppThemeColors.secondaryText(context))),
        ]),
      ),
    );
  }

  Widget _buildPersonFilter(String Function(String) t, List<Map<String, String>> options) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _selectedCounterparty != 'all' ? AppColors.cyan.withValues(alpha: 0.1) : AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _selectedCounterparty != 'all' ? AppColors.cyan : AppThemeColors.divider(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCounterparty,
          isDense: true,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _selectedCounterparty != 'all' ? AppColors.cyan : AppThemeColors.secondaryText(context)),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: _selectedCounterparty != 'all' ? AppColors.cyan : AppThemeColors.secondaryText(context)),
          items: options.map((item) => DropdownMenuItem<String>(
            value: item['email'],
            child: Text(item['label'] ?? t('all_people_label'), style: TextStyle(fontSize: 11, color: AppThemeColors.primaryText(context))),
          )).toList(),
          onChanged: (v) { if (v != null) _applyCounterpartyFilter(v); },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final displayedTransactions =
        _showAll ? filteredTransactions : filteredTransactions.take(3).toList();
    final groupedTransactions =
        _groupDisplayedTransactions(displayedTransactions);

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(context.sh(78)),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/user/dashboard');
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    t('quick_transactions_title'),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: AppThemeColors.primaryText(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
          actions: [
            // Stats button
            if (!loading && error == null && transactions.isNotEmpty)
              IconButton(
                icon: Icon(Icons.analytics_outlined, color: AppThemeColors.primaryText(context)),
                tooltip: t('open_quick_analytics_label'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsPage())),
              ),
            IconButton(
              icon: Icon(Icons.schedule_rounded, color: AppThemeColors.primaryText(context)),
              tooltip: t('scheduled_transactions_title'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ScheduledTransactionsPage()));
              },
            ),
            IconButton(
              icon: Icon(Icons.repeat_rounded, color: AppThemeColors.primaryText(context)),
              tooltip: t('recurring_templates_title'),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringTemplatesPage()));
              },
            ),
          ],
          flexibleSpace: ClipPath(
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            // â”€â”€ Compact filter bar â”€â”€
            _buildFilterBar(t),

            // â”€â”€ Budget banner + subscription badge (slim) â”€â”€
            BudgetLimitBanner(
              type: 'quick',
              refreshTrigger: _bannerRefreshTrigger,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetPlanningPage())),
              onViewMessages: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetMessagesPage())),
            ),
            Consumer<SessionProvider>(
              builder: (context, session, child) {
                if (session.hasFeature('quick_transactions')) return const SizedBox.shrink();
                final free = session.freeQuickTransactionsRemaining ?? 0;
                final dailyRemaining = _dailyLimits?['limits']?['quickTransactions']?['remaining'] as int?;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  child: Row(
                    children: [
                      Flexible(
                        child: _buildAttemptsChip(
                          icon: free > 0 ? Icons.confirmation_num_outlined : Icons.block_rounded,
                          label: free > 0
                              ? t('free_quick_transactions_remaining_message').replaceFirst('{count}', '$free')
                              : 'Free attempts exhausted',
                          color: free > 2 ? const Color(0xFF1976D2) : free > 0 ? Colors.orange : Colors.red,
                        ),
                      ),
                      if (free <= 0 && dailyRemaining != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: _buildAttemptsChip(
                            icon: Icons.monetization_on_outlined,
                            label: '$dailyRemaining coin attempts left',
                            color: dailyRemaining > 0 ? const Color(0xFF00695C) : Colors.red,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),

            // â”€â”€ Currency error â”€â”€
            if (_displayCurrencyError != null || _hasMissingConversionForQuickTransactions())
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFF6B6B)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Color(0xFFD62828), size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _displayCurrencyError ?? t('conversion_not_available_quick_transactions_message').replaceFirst('{currency}', selectedCurrency),
                        style: const TextStyle(color: Color(0xFFD62828), fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              ),

            // â”€â”€ Transaction list (fills remaining space) â”€â”€
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchQuickTransactions,
                color: AppColors.cyan,
                child: loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                  : error != null
                    ? errorStateWidget(context, error!, fetchQuickTransactions)
                    : filteredTransactions.isEmpty
                      ? _buildEmptyStateWidget(t)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 120),
                          children: [
                            // Stats strip (compact, shown inline at the top of list)
                            if (transactions.isNotEmpty)
                              _buildCompactStatsStrip(t),
                            const SizedBox(height: 10),
                            ...groupedTransactions.entries.expand((entry) {
                              final sectionIndex = groupedTransactions.keys.toList().indexOf(entry.key);
                              return <Widget>[
                                Padding(
                                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                                  child: Row(children: [
                                    Container(
                                      width: 3, height: 14,
                                      decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(entry.key, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppThemeColors.secondaryText(context), letterSpacing: 0.5)),
                                  ]),
                                ),
                                ...entry.value.asMap().entries.map((item) => Padding(
                                  key: ValueKey((item.value['_id'] ?? '').toString()),
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildQuickTransactionCard(item.value, sectionIndex + item.key),
                                )),
                              ];
                            }),
                            if (filteredTransactions.length > 3)
                              TextButton(
                                onPressed: () => setState(() => _showAll = !_showAll),
                                child: Text(
                                  _showAll ? t('show_less_label') : t('see_all_transactions_label'),
                                  style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold),
                                ),
                              ),
                            if (_qtHasMore && _showAll)
                              Center(
                                child: _qtLoadingMore
                                  ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppColors.cyan))
                                  : OutlinedButton.icon(
                                      onPressed: () => fetchQuickTransactions(append: true),
                                      icon: const Icon(Icons.expand_more, color: AppColors.cyan),
                                      label: Text(t('load_more_label'), style: const TextStyle(color: AppColors.cyan)),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: AppColors.cyan),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
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

  Widget _buildEmptyStateWidget(String Function(String) t) {
    final hasFilters = _hasActiveFilters();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _showFavouritesOnly ? Icons.star_border_rounded : hasFilters ? Icons.search_off_rounded : Icons.receipt_long_rounded,
              size: 38, color: AppColors.cyan,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _showFavouritesOnly
              ? t('no_favourite_transactions_found_message')
              : hasFilters ? t('no_transactions_found_message') : t('no_quick_transactions_yet_message'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _showFavouritesOnly
              ? t('mark_transaction_favourite_to_see_here_message')
              : hasFilters ? t('try_adjusting_search_or_filters_message') : t('tap_plus_button_to_create_first_one_message'),
            style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context)),
            textAlign: TextAlign.center,
          ),
          if (hasFilters) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.refresh_rounded, color: AppColors.cyan, size: 16),
              label: Text(t('reset_filters_label'), style: const TextStyle(color: AppColors.cyan)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.cyan), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            ),
          ],
        ],
      ),
    );
  }

  String _qtInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _buildCompactStatsStrip(String Function(String) t) {
    final total = filteredTransactions.length;
    final pending = filteredTransactions.where((x) => x['cleared'] != true).length;
    final lentCount = filteredTransactions.where((x) => _roleForViewer(x) == 'lender').length;
    final totalVal = filteredTransactions.fold<double>(0, (s, x) => s + _displayNumericAmount(x));

    // Compute largest transaction
    Map<String, dynamic>? largestTx;
    double largestAmt = 0;
    for (final tx in filteredTransactions) {
      final amt = _displayNumericAmount(tx).abs();
      if (amt > largestAmt) { largestAmt = amt; largestTx = tx; }
    }

    // Compute top counterparty
    final cpTotals = <String, double>{};
    final cpNames = <String, String>{};
    final cpAvatars = <String, String?>{};
    final cpTxCounts = <String, int>{};
    final currentEmail = _currentUserEmail();
    for (final tx in filteredTransactions) {
      final users = List<Map<String, dynamic>>.from(tx['users'] ?? []);
      final cp = users.firstWhere(
        (u) => (u['email'] ?? '').toString().toLowerCase().trim() != currentEmail,
        orElse: () => {},
      );
      final email = (cp['email'] ?? '').toString();
      if (email.isEmpty) continue;
      cpTotals[email] = (cpTotals[email] ?? 0) + _displayNumericAmount(tx).abs();
      cpNames[email] = (cp['name'] ?? email).toString();
      cpAvatars[email] ??= cp['avatar']?.toString();
      cpTxCounts[email] = (cpTxCounts[email] ?? 0) + 1;
    }
    String? topEmail;
    if (cpTotals.isNotEmpty) {
      topEmail = cpTotals.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }
    final topName = topEmail != null ? (cpNames[topEmail] ?? topEmail) : '';
    final topAvatar = topEmail != null ? cpAvatars[topEmail] : null;
    final topAmt = topEmail != null ? (cpTotals[topEmail] ?? 0) : 0.0;
    final topTxCount = topEmail != null ? (cpTxCounts[topEmail] ?? 0) : 0;

    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _buildStripCard('$total', t('transactions_label'), Icons.receipt_long_rounded, [const Color(0xFF0077B6), const Color(0xFF48CAE4)], null),
          _buildStripCard(_formatDisplayAmount(totalVal, selectedCurrency), t('quick_value_label'), Icons.currency_rupee_rounded, [const Color(0xFF06A77D), const Color(0xFF4ECDC4)], null),
          _buildStripCard('$pending', t('pending_label'), Icons.pending_actions_rounded, [const Color(0xFFF4B400), const Color(0xFFD97706)], null),
          _buildStripCard('$lentCount', t('you_lent_label'), Icons.north_east_rounded, [const Color(0xFF1B58B8), const Color(0xFF4B8EFD)], null),
          if (largestTx != null)
            _buildStripCard(
              _formatDisplayAmount(largestAmt, selectedCurrency),
              t('largest_quick_label'),
              Icons.leaderboard_rounded,
              [const Color(0xFFD95F02), const Color(0xFFFFA069)],
              () => _showLargestTxSheet(t, largestTx!),
            ),
          if (topEmail != null)
            _buildTopCpCard(t, topName, topAvatar, topAmt, topTxCount),
        ],
      ),
    );
  }

  Widget _buildStripCard(String value, String label, IconData icon, List<Color> colors, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 108,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 13, color: Colors.white70),
              if (onTap != null) ...[const Spacer(), const Icon(Icons.open_in_new_rounded, size: 11, color: Colors.white54)],
            ]),
            const Spacer(),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, color: Colors.white70, letterSpacing: 0.2), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildTopCpCard(String Function(String) t, String name, String? avatar, double amount, int txCount) {
    const colors = [Color(0xFF7C3AED), Color(0xFFA78BFA)];
    return GestureDetector(
      onTap: () => _showTopCpSheet(t, name, avatar, amount, txCount),
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
              backgroundColor: Colors.white24,
              child: (avatar == null || avatar.isEmpty)
                ? Text(_qtInitials(name), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))
                : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(t('top_counterparty_label'), style: const TextStyle(fontSize: 9, color: Colors.white70)),
                Text('$txCount txns', style: const TextStyle(fontSize: 9, color: Colors.white60)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  void _showLargestTxSheet(String Function(String) t, Map<String, dynamic> tx) {
    final cp = _counterpartyForViewer(tx);
    final role = _roleForViewer(tx);
    final isLender = role == 'lender';
    final amt = _formatDisplayAmount(_displayNumericAmount(tx).abs(), selectedCurrency);
    final desc = (tx['description'] ?? '').toString();
    final date = tx['date']?.toString().split('T').first ?? '';
    final cpName = (cp?['name'] ?? cp?['email'] ?? '').toString();
    final cpAvatar = cp?['avatar']?.toString();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(context), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFD95F02).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.leaderboard_rounded, color: Color(0xFFD95F02), size: 22),
            ),
            const SizedBox(width: 12),
            Text(t('largest_quick_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          ]),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLender ? const Color(0xFF1B58B8).withValues(alpha: 0.08) : const Color(0xFFD95F02).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isLender ? const Color(0xFF1B58B8).withValues(alpha: 0.2) : const Color(0xFFD95F02).withValues(alpha: 0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: cpAvatar != null && cpAvatar.isNotEmpty ? NetworkImage(cpAvatar) : null,
                  backgroundColor: isLender ? const Color(0xFF1B58B8) : const Color(0xFFD95F02),
                  child: (cpAvatar == null || cpAvatar.isEmpty) ? Text(_qtInitials(cpName), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cpName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                  if (date.isNotEmpty) Text(date, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                ])),
                Text(
                  '${isLender ? '+' : '-'} $amt',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isLender ? const Color(0xFF1B58B8) : const Color(0xFFD95F02)),
                ),
              ]),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(desc, style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(context); createOrEditQuickTransaction(transaction: tx); },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(t('edit_label')),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.cyan), foregroundColor: AppColors.cyan, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ]),
      ),
    );
  }

  void _showTopCpSheet(String Function(String) t, String name, String? avatar, double amount, int txCount) {
    final lentToThem = filteredTransactions.where((x) => _roleForViewer(x) == 'lender' && _counterpartyForViewer(x)?['name']?.toString() == name).length;
    final borrowedFromThem = filteredTransactions.where((x) => _roleForViewer(x) == 'borrower' && _counterpartyForViewer(x)?['name']?.toString() == name).length;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(context), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          // Profile header
          Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
              backgroundColor: const Color(0xFF7C3AED),
              child: (avatar == null || avatar.isEmpty)
                ? Text(_qtInitials(name), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))
                : null,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              Text(t('top_counterparty_label'), style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED), fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 20),
          // Stats row
          Row(children: [
            Expanded(child: _cpStatBox(t('total_label'), '$txCount ${t('transactions_label')}', Icons.receipt_long_rounded, const Color(0xFF7C3AED))),
            const SizedBox(width: 10),
            Expanded(child: _cpStatBox(t('quick_value_label'), _formatDisplayAmount(amount, selectedCurrency), Icons.currency_rupee_rounded, const Color(0xFF06A77D))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _cpStatBox(t('you_lent_label'), '$lentToThem txns', Icons.north_east_rounded, const Color(0xFF1B58B8))),
            const SizedBox(width: 10),
            Expanded(child: _cpStatBox(t('i_owe_label'), '$borrowedFromThem txns', Icons.south_west_rounded, const Color(0xFFD95F02))),
          ]),
        ]),
      ),
    );
  }

  Widget _cpStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context))),
        ])),
      ]),
    );
  }

  Widget _buildQuickTransactionCard(Map<String, dynamic> transaction, int i) {
    final t = AppLocalizations.of(context).t;
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
        'name': transaction['creatorEmail'] ?? t('unknown_label'),
        'email': transaction['creatorEmail'] ?? t('unknown_label'),
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
                label: t('settle_label'),
              ),
            SlidableAction(
              onPressed: (_) => _showReceiptDialog(transaction),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: Icons.share_rounded,
              label: t('share'),
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
                label: t('edit'),
              ),
            if (isCleared)
              SlidableAction(
                onPressed: (_) => deleteQuickTransaction(transaction['_id']),
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                icon: Icons.delete,
                label: t('delete'),
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
                                '${_formatDisplayAmount(transaction['amount'], transaction['currency']?.toString())} â€¢ ${(currencyData?.canConvert((transaction['currency'] ?? 'INR').toString(), selectedCurrency) ?? ((transaction['currency'] ?? 'INR').toString().toUpperCase() == selectedCurrency.toUpperCase())) ? selectedCurrency : (transaction['currency'] ?? 'INR')}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ), // note cards keep a fixed light bg (_getNoteColor); black87 stays readable regardless of theme
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _togglePinTransaction(
                                (transaction['_id'] ?? '').toString()),
                            icon: Icon(
                              isPinned ? Icons.star : Icons.star_border_rounded,
                              color: isPinned
                                  ? Colors.amber[700]
                                  : Colors.grey[600],
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
                              t('cleared'),
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
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text(t('edit')),
                                ),
                              if (!isCleared &&
                                  (settlementStatus == 'none' ||
                                      settlementStatus == 'rejected') &&
                                  roleForViewer == 'lender')
                                PopupMenuItem(
                                  value: 'request_settlement',
                                  child: Text(t('request_settlement_label')),
                                ),
                              if (!isCleared && roleForViewer == 'borrower')
                                PopupMenuItem(
                                  value: 'pay_now',
                                  child: Row(children: [
                                    const Icon(Icons.payment_rounded,
                                        size: 16, color: AppColors.cyan),
                                    const SizedBox(width: 8),
                                    Text(t('pay_now_real_money_label'),
                                        style: const TextStyle(
                                            color: AppColors.cyan,
                                            fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              if (_canRespondToSettlement(transaction))
                                PopupMenuItem(
                                  value: 'accept_settlement',
                                  child: Text(t('accept_settlement_label')),
                                ),
                              if (_canRespondToSettlement(transaction))
                                PopupMenuItem(
                                  value: 'reject_settlement',
                                  child: Text(t('reject_settlement_label')),
                                ),
                              PopupMenuItem(
                                value: 'duplicate',
                                child: Text(t('duplicate_label')),
                              ),
                              PopupMenuItem(
                                value: 'share',
                                child: Text(t('share_receipt_label')),
                              ),
                              PopupMenuItem(
                                value: 'pin',
                                child: Text(isPinned
                                    ? t('unpin_label')
                                    : t('pin_label')),
                              ),
                              if (isCleared)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(t('delete')),
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
                                ? t('cleared')
                                : settlementStatus == 'pending'
                                    ? t('pending_label')
                                    : t('open_label'),
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
                                ? t('you_lent_label')
                                : t('you_borrowed_label'),
                            roleForViewer == 'lender'
                                ? const Color(0xFF1B58B8)
                                : const Color(0xFFD95F02),
                            roleForViewer == 'lender'
                                ? Icons.north_east_rounded
                                : Icons.south_west_rounded,
                          ),
                          if (isPinned)
                            _buildStatusChip(
                              t('pinned_label'),
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
                          _buildStatusChip(
                            _catLabel((transaction['category'] ?? 'other').toString()),
                            Colors.deepPurple,
                            _catIcon((transaction['category'] ?? 'other').toString()),
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
                                      t('unknown_label'))
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
                            ? t('created_by_you_label')
                            : t('created_by_name_label').replaceFirst('{name}',
                                '${creatorName['name'] ?? creatorName['email'] ?? t('unknown_label')}'),
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
                              colors: [
                                Colors.orange,
                                Colors.white,
                                Colors.green
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.payment_rounded,
                                  color: Colors.white, size: 18),
                              label: Text(t('pay_now_real_money_label'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
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
                                    ? t('settlement_requested_by_you_label')
                                    : t('settlement_requested_by_other_user_label'),
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
                                        child: Text(
                                          t('reject_label'),
                                          style: const TextStyle(
                                              color: Colors.white),
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
                                        child: Text(
                                          t('accept'),
                                          style: const TextStyle(
                                              color: Colors.white),
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

