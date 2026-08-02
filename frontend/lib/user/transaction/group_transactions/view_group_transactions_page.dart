import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/currency_display.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../chats/group_chat_page.dart';
import 'create_group_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/wave_widget.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class ViewGroupTransactionsPage extends StatefulWidget {
  const ViewGroupTransactionsPage({super.key});

  @override
  State<ViewGroupTransactionsPage> createState() =>
      _ViewGroupTransactionsPageState();
}

class _ViewGroupTransactionsPageState extends State<ViewGroupTransactionsPage>
    with CurrencyDisplayMixin<ViewGroupTransactionsPage> {
  List<Map<String, dynamic>> userGroups = [];
  bool loading = true;
  String? error;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String selectedGroupFilter =
      'All Groups'; // 'All Groups', 'Joined Groups', 'Left Groups'
  bool _showFavouritesOnly = false;
  int createdGroupsCount = 0; // Track groups created by user
  String? _displayCurrencyError;
  List<Map<String, String>> _currencies = [
    {'code': 'INR', 'symbol': '₹'},
    {'code': 'USD', 'symbol': '\$'},
    {'code': 'EUR', 'symbol': '€'},
    {'code': 'GBP', 'symbol': '£'},
    {'code': 'JPY', 'symbol': '¥'},
    {'code': 'CNY', 'symbol': '¥'},
    {'code': 'CAD', 'symbol': '\$'},
    {'code': 'AUD', 'symbol': '\$'},
    {'code': 'CHF', 'symbol': 'Fr'},
    {'code': 'RUB', 'symbol': '₽'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSupportedCurrencies();
    loadCurrencies(onError: (_) {
      if (mounted) setState(() => _displayCurrencyError = AppLocalizations.of(context).t('currency_conversion_unavailable_message'));
    });
    _fetchUserGroups();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showJoinGroupDialog() async {
    final t = AppLocalizations.of(context).t;
    final codeController = TextEditingController();
    bool joining = false;

    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0077B6), AppColors.cyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('join_group_by_code_title'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(ctx),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the invite code shared by your group creator',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.secondaryText(ctx),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.45), width: 1.5),
                      color: AppColors.cyan.withValues(alpha: 0.05),
                    ),
                    child: TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: AppColors.cyan,
                      ),
                      decoration: InputDecoration(
                        hintText: t('enter_join_code_hint'),
                        hintStyle: TextStyle(
                          fontSize: 14,
                          letterSpacing: 1,
                          fontWeight: FontWeight.normal,
                          color: AppThemeColors.mutedText(ctx),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: joining
                          ? null
                          : () async {
                              final code = codeController.text.trim();
                              if (code.isEmpty) return;
                              setDialog(() => joining = true);
                              final res = await ApiClient.post('/api/group-transactions/join', body: {'joinCode': code});
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              if (res.statusCode == 200) {
                                showSnack(context, t('join_group_success'));
                                _fetchUserGroups();
                              } else {
                                final err = jsonDecode(res.body)['error'] ?? t('something_went_wrong');
                                showSnack(context, err.toString(), isError: true);
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: joining
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(t('join_group_button'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    codeController.dispose();
  }

  Future<void> _toggleFavourite(String groupId) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final email = session.user?['email'];
    if (email == null) return;

    // Optimistic update
    final groupIndex = userGroups.indexWhere((g) => g['_id'] == groupId);
    if (groupIndex == -1) return;
    final group = userGroups[groupIndex];
    final isFavourited = (group['favourite'] as List? ?? []).contains(email);
    setState(() {
      if (isFavourited) {
        (group['favourite'] as List).remove(email);
      } else {
        (group['favourite'] as List).add(email);
      }
    });

    try {
      final response = await ApiClient.put(
        '/api/group-transactions/$groupId/favourite',
        body: {'email': email},
      );
      if (response.statusCode != 200) {
        // Revert on failure and refetch
        setState(() {
          if (isFavourited) {
            (group['favourite'] as List).add(email);
          } else {
            (group['favourite'] as List).remove(email);
          }
        });
        _fetchUserGroups();
      } else if (_showFavouritesOnly) {
        // If showing favourites only, refetch so the toggled group disappears/appears
        _fetchUserGroups();
      }
    } catch (e) {
      // Revert on failure
      setState(() {
        if (isFavourited) {
          (group['favourite'] as List).add(email);
        } else {
          (group['favourite'] as List).remove(email);
        }
      });
    }
  }

  Future<void> _fetchUserGroups() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final params = <String, String>{};
      final searchText = _searchController.text.trim();
      if (searchText.isNotEmpty) params['search'] = searchText;
      if (_showFavouritesOnly) params['favouritesOnly'] = 'true';
      if (selectedGroupFilter == 'Joined Groups') {
        params['status'] = 'joined';
      } else if (selectedGroupFilter == 'Left Groups') {
        params['status'] = 'left';
      }

      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response =
          await ApiClient.get('/api/group-transactions/user-groups$query');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final allGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final createdCount = data['createdGroupsCount'] ?? 0;
        setState(() {
          userGroups = allGroups;
          createdGroupsCount = createdCount;
          loading = false;
        });
      } else {
        final t = AppLocalizations.of(context).t;
        setState(() {
          error = t('failed_to_load_group_transactions_retry_message');
          loading = false;
        });
      }
    } catch (e) {
      final t = AppLocalizations.of(context).t;
      setState(() {
        error = t('unable_to_connect_check_internet_message');
        loading = false;
      });
    }
  }

  // Helper function to format date and time
  String _formatDateTime(dynamic dateTime) {
    final t = AppLocalizations.of(context).t;
    if (dateTime == null) return t('unknown_label');

    try {
      DateTime date;
      if (dateTime is String) {
        date = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        date = dateTime;
      } else {
        return t('invalid_date_label');
      }

      // Format: "Dec 15, 2023 at 2:30 PM"
      String month = _getMonthName(date.month);
      String day = date.day.toString();
      String year = date.year.toString();
      String hour =
          date.hour > 12 ? (date.hour - 12).toString() : date.hour.toString();
      if (hour == '0') hour = '12';
      String minute = date.minute.toString().padLeft(2, '0');
      String period = date.hour >= 12 ? 'PM' : 'AM';

      return '$month $day, $year at $hour:$minute $period';
    } catch (e) {
      return t('invalid_date_label');
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[month - 1];
  }

  Future<void> _loadSupportedCurrencies() async {
    try {
      final res = await ApiClient.get('/api/currency-conversions/supported');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final currencies =
          List<Map<String, dynamic>>.from(data['currencies'] ?? const []);
      if (currencies.isEmpty) return;
      setState(() {
        _currencies = currencies
            .map(
              (item) => {
                'code': (item['code'] ?? 'INR').toString().toUpperCase(),
                'symbol': (item['symbol'] ?? item['code'] ?? '₹').toString(),
              },
            )
            .toList();
      });
    } catch (_) {}
  }

  String _currencySymbol(String? code) {
    final currencyCode = (code ?? 'INR').toUpperCase();
    final match = _currencies.firstWhere(
      (item) => item['code'] == currencyCode,
      orElse: () => const {'code': 'INR', 'symbol': '₹'},
    );
    return match['symbol'] ?? '₹';
  }

  double _expenseAmountInInr(Map<String, dynamic> expense) {
    return double.tryParse(
            (expense['amountInr'] ?? expense['amount'] ?? 0).toString()) ??
        0.0;
  }

  double _splitAmountInInr(Map<String, dynamic> splitItem) {
    return double.tryParse(
          (splitItem['amountInr'] ?? splitItem['amount'] ?? 0).toString(),
        ) ??
        0.0;
  }

  String _formatInr(num amount) => '₹${amount.toStringAsFixed(2)}';

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
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.wifi_off_rounded, size: 48, color: Colors.red[400]),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('oops_something_went_wrong_message'),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                    ),
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
                label: Text(t('retry'), style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _subtitleChip(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 10, top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.cyan),
          const SizedBox(width: 4),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                '$label: $value',
                style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w500),
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryStatChip(String label, String value,
      {required Color color, required IconData icon}) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDisplayAmountFromInr(num amount) {
    final targetCurrency = selectedCurrency.toUpperCase();
    if (targetCurrency != 'INR' &&
        !(currencyData?.canConvert('INR', targetCurrency) ?? false)) {
      return _formatInr(amount);
    }
    final converted = currencyData?.convert(
          amount,
          'INR',
          targetCurrency,
        ) ??
        amount.toDouble();
    final symbol = currencyData?.symbolFor(targetCurrency) ?? '₹';
    return '$symbol${converted.toStringAsFixed(2)}';
  }

  Map<String, dynamic>? _findGroupById(String groupId) {
    try {
      return userGroups.firstWhere((group) => group['_id'] == groupId);
    } catch (_) {
      return null;
    }
  }

  String? _lockedCurrencyForUserInGroup(String groupId, String? userEmail,
      {String? excludingExpenseId}) {
    final group = _findGroupById(groupId);
    if (group == null) return null;
    final expenses = List<Map<String, dynamic>>.from(group['expenses'] ?? []);
    for (final expense in expenses) {
      if (excludingExpenseId != null &&
          expense['_id']?.toString() == excludingExpenseId) {
        continue;
      }
      if (expense['currency'] != null) {
        return (expense['currency'] ?? 'INR').toString().toUpperCase();
      }
    }
    return null;
  }

  void _onGroupFilterChanged(String? newValue) {
    if (newValue != null) {
      setState(() => selectedGroupFilter = newValue);
      _fetchUserGroups();
    }
  }

  void _showGroupFiltersSheet() {
    final t = AppLocalizations.of(context).t;
    final filterLabels = {
      'All Groups': t('filter_all_groups_label'),
      'Joined Groups': t('filter_joined_groups_label'),
      'Left Groups': t('filter_left_groups_label'),
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_list, color: AppColors.cyan),
                        const SizedBox(width: 8),
                        Text(t('filters_label'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final option in const [
                      {'value': 'All Groups', 'icon': Icons.group},
                      {'value': 'Joined Groups', 'icon': Icons.group_add},
                      {'value': 'Left Groups', 'icon': Icons.group_remove},
                    ])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: option['value'] as String,
                        groupValue: selectedGroupFilter,
                        activeColor: AppColors.cyan,
                        title: Row(
                          children: [
                            Icon(option['icon'] as IconData,
                                color: AppColors.cyan, size: 18),
                            const SizedBox(width: 8),
                            Text(filterLabels[option['value']] ?? option['value'] as String),
                          ],
                        ),
                        onChanged: (value) {
                          _onGroupFilterChanged(value);
                          setSheetState(() {});
                        },
                      ),
                    const Divider(),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        t('show_favourites_only_label'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.cyan,
                        ),
                      ),
                      value: _showFavouritesOnly,
                      activeColor: AppColors.cyan,
                      onChanged: (bool value) {
                        setState(() => _showFavouritesOnly = value);
                        setSheetState(() {});
                        _fetchUserGroups();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Total pending balance across displayed groups using server-computed field
  double _calculateTotalPendingBalance() {
    return userGroups.fold(
      0.0,
      (sum, g) => sum + (g['userPendingBalance'] as num? ?? 0).toDouble(),
    );
  }

  // Total expenses across displayed groups using server-computed field
  int _calculateTotalExpenses() {
    return userGroups.fold(
      0,
      (sum, g) => sum + ((g['totalExpenses'] as num? ?? (g['expenses'] as List?)?.length ?? 0).toInt()),
    );
  }

  Future<void> _editExpense(String groupId, String expenseId,
      Map<String, dynamic> expenseData) async {
    final t = AppLocalizations.of(context).t;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await ApiClient.put(
          '/api/group-transactions/$groupId/expenses/$expenseId',
          body: expenseData);
      final data = res.body.isNotEmpty ? json.decode(res.body) : null;
      if (res.statusCode == 200) {
        // Refresh the groups data
        await _fetchUserGroups();
        // Show success message
        showSnack(context, '✅ ${t('expense_updated_successfully_message')}');
      } else {
        setState(() {
          error = data?['error'] ?? t('failed_to_update_expense_message');
        });
      }
    } catch (e) {
      setState(() {
        error = t('something_went_wrong_retry_message');
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  void _showEditExpenseDialog(Map<String, dynamic> expense, String groupId) {
    final t = AppLocalizations.of(context).t;
    final TextEditingController editDescController =
        TextEditingController(text: expense['description'] ?? '');
    final TextEditingController editAmountController =
        TextEditingController(text: (expense['amount'] ?? 0).toString());
    String editSplitType = 'equal';
    final currentUserEmail =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    final lockedCurrency = _lockedCurrencyForUserInGroup(
      groupId,
      currentUserEmail,
      excludingExpenseId: expense['_id']?.toString(),
    );
    String editCurrency = (expense['currency'] ?? lockedCurrency ?? 'INR')
        .toString()
        .toUpperCase();

    // Filter out members who have left the group from selected members
    List<String> editSelectedMembers =
        List<String>.from(expense['selectedMembers'] ?? []);
    // Note: In this view, we don't have access to group data, so we'll keep the original members
    // The backend will handle filtering out inactive members

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: AppThemeColors.cardBg(context),
          title: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.cyan, Color(0xFF48CAE4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.edit, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Text(
                  t('edit_expense_title'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          content: Container(
            width: double.maxFinite,
            height: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  Text(
                    t('description_label'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: editDescController,
                    decoration: InputDecoration(
                      hintText: t('enter_expense_description_hint'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.cyan, width: 2),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  Text(
                    t('currency_label'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: editCurrency,
                    decoration: InputDecoration(
                      helperText: lockedCurrency != null
                          ? t('currency_locked_to_message').replaceFirst('{currency}', lockedCurrency)
                          : t('currency_unlocked_other_groups_message'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.cyan, width: 2),
                      ),
                    ),
                    items: _currencies
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency['code'],
                            child: Text(
                                '${currency['symbol']} ${currency['code']}'),
                          ),
                        )
                        .toList(),
                    onChanged: lockedCurrency != null
                        ? null
                        : (value) {
                            setDialogState(() {
                              editCurrency = value ?? 'INR';
                            });
                          },
                  ),
                  SizedBox(height: 16),
                  Text(
                    t('amount_label'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: editAmountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: t('enter_amount_hint'),
                      prefixText: _currencySymbol(editCurrency),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.cyan, width: 2),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Member Selection
                  Text(
                    t('select_members_label'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    constraints: BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Column(
                        children:
                            editSelectedMembers.map<Widget>((memberEmail) {
                          return CheckboxListTile(
                            title: Text(memberEmail),
                            value: true,
                            onChanged: (bool? value) {
                              setDialogState(() {
                                if (value == false) {
                                  editSelectedMembers.remove(memberEmail);
                                }
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Split Type
                  Text(
                    t('split_type_label'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                    ),
                  ),
                  SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: editSplitType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.cyan, width: 2),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'equal', child: Text(t('equal_split_label'))),
                      DropdownMenuItem(
                          value: 'custom', child: Text(t('custom_split_label'))),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        editSplitType = value!;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: 16, right: 8),
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        t('cancel'),
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: 8, right: 16),
                    child: ElevatedButton(
                      onPressed: () async {
                        if (editDescController.text.trim().isEmpty) {
                          showSnack(context, t('enter_a_description_message'), isError: true);
                          return;
                        }

                        final amount =
                            double.tryParse(editAmountController.text);
                        if (amount == null || amount <= 0) {
                          showSnack(context, t('enter_a_valid_amount'), isError: true);
                          return;
                        }

                        if (editSelectedMembers.isEmpty) {
                          showSnack(context, t('select_at_least_one_member_message'), isError: true);
                          return;
                        }

                        Navigator.of(context).pop();

                        final expenseData = {
                          'description': editDescController.text.trim(),
                          'amount': amount,
                          'currency': editCurrency,
                          'selectedMembers': editSelectedMembers,
                          'splitType': editSplitType,
                        };

                        await _editExpense(
                            groupId, expense['_id'], expenseData);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        t('update_label'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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
    );
  }

  void _showAllExpensesDialog(
      List<Map<String, dynamic>> expenses, String groupTitle, String groupId) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppThemeColors.cardBg(context),
        title: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.cyan, Color(0xFF48CAE4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                t('all_expenses_title_message').replaceFirst('{groupTitle}', groupTitle),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        content: Container(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppColors.cyan, size: 20),
                      SizedBox(width: 8),
                      Text(
                        t('total_expenses_count_label').replaceFirst('{count}', '${expenses.length}'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                ...expenses.map<Widget>((expense) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppThemeColors.surfaceBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.cyan,
                        child: Icon(
                          Icons.receipt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        expense['description'] ?? t('no_description_label'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.cyan,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t('amount_colon_label')} ${_formatDisplayAmountFromInr(_expenseAmountInInr(Map<String, dynamic>.from(expense)))}',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            t('added_by_colon_label').replaceFirst('{email}', expense['addedBy'] ?? t('unknown_label')),
                            style: TextStyle(
                              color: AppThemeColors.secondaryText(context),
                              fontSize: 12,
                            ),
                          ),
                          if (expense['createdAt'] != null ||
                              expense['date'] != null)
                            Row(
                              children: [
                                Icon(Icons.access_time,
                                    color: AppThemeColors.mutedText(context), size: 12),
                                SizedBox(width: 4),
                                Text(
                                  _formatDateTime(
                                      expense['createdAt'] ?? expense['date']),
                                  style: TextStyle(
                                    color: AppThemeColors.mutedText(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      trailing: Builder(
                        builder: (context) {
                          final currentUserEmail = Provider.of<SessionProvider>(
                                  context,
                                  listen: false)
                              .user?['email'];
                          final expenseAddedBy = expense['addedBy'];
                          final shouldShowEdit =
                              expenseAddedBy == currentUserEmail;

                          return shouldShowEdit
                              ? IconButton(
                                  icon: Icon(Icons.edit,
                                      color: AppColors.cyan),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _showEditExpenseDialog(expense, groupId);
                                  },
                                )
                              : SizedBox.shrink();
                        },
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(
                t('close'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((_) {});
  }

  Future<void> _openCreateGroup() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('group_creation')) {
      int? dailyRemaining;
      await Future.wait([
        session.loadFreebieCounts(),
        ApiClient.get('/api/limits/daily').then((res) {
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            dailyRemaining = data['limits']?['groups']?['remaining'];
          }
        }),
      ]);
      if (!mounted) return;
      if (dailyRemaining != null && dailyRemaining! <= 0) {
        showDailyLimitDialog(context,
            message: t('daily_group_creation_limit_reached_message'));
        return;
      }
      final freeRemaining = session.freeGroupsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: t('group_creation_feature_label'), coinCost: session.groupCreationCoinCost, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateGroupPage(useCoins: true)));
        return;
      }
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CreateGroupPage()));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentUserEmail = session.user?['email'];

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(context.sh(156)),
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Text(t('group_transactions_title_label'),
                  style: TextStyle(
                      color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
            ],
          ),
          iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
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
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedCurrency,
                    dropdownColor: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    items: (currencyData?.currencies ?? _currencies)
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency['code'],
                            child: Text(
                              '${currency['symbol']} ${currency['code']}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setCurrency(value);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? _buildErrorState(error!, _fetchUserGroups)
              : userGroups.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.group_outlined,
                              size: 64, color: AppThemeColors.secondaryText(context)),
                          SizedBox(height: 16),
                          Text(
                            t('no_group_transactions_found_message'),
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            t('not_part_of_any_group_transactions_message'),
                            style: TextStyle(color: AppThemeColors.secondaryText(context)),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchUserGroups,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                        children: [
                          // Search and Filter Row
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                if (_displayCurrencyError != null ||
                                    (selectedCurrency != 'INR' &&
                                        !(currencyData?.canConvert(
                                              'INR',
                                              selectedCurrency,
                                            ) ??
                                            false)))
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F1),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: const Color(0xFFFF6B6B)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.error_outline,
                                          color: Color(0xFFD62828),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _displayCurrencyError ??
                                                t('conversion_to_currency_unavailable_message').replaceFirst('{currency}', selectedCurrency),
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
                                Row(
                                  children: [
                                    // Search Bar
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFFFF9933),
                                              Color(0xFFFFFFFF),
                                              Color(0xFF138808)
                                            ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppColors.cyan
                                                  .withValues(alpha: 0.1),
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Container(
                                          margin: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: AppThemeColors.cardBg(context),
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          child: TextField(
                                            controller: _searchController,
                                            decoration: InputDecoration(
                                              labelText: t('search_groups_label'),
                                              labelStyle: TextStyle(
                                                color: AppColors.cyan,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                borderSide: BorderSide.none,
                                              ),
                                              filled: true,
                                              fillColor: Colors.transparent,
                                              prefixIcon: Container(
                                                margin: EdgeInsets.all(8),
                                                padding: EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.cyan
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  Icons.search,
                                                  color: AppColors.cyan,
                                                  size: 20,
                                                ),
                                              ),
                                              suffixIcon: _searchController
                                                      .text.isNotEmpty
                                                  ? IconButton(
                                                      icon: Icon(Icons.clear,
                                                          color: Color(
                                                              0xFF00B4D8)),
                                                      onPressed: () {
                                                        _searchController
                                                            .clear();
                                                      },
                                                    )
                                                  : null,
                                              contentPadding:
                                                  EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 16),
                                              hintText:
                                                  t('search_groups_hint'),
                                              hintStyle: TextStyle(
                                                color: Color(0xFF6B7280),
                                                fontSize: 14,
                                              ),
                                            ),
                                            onChanged: (value) {
                                              _searchDebounceTimer?.cancel();
                                              _searchDebounceTimer = Timer(
                                                const Duration(milliseconds: 300),
                                                _fetchUserGroups,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),

                                    // Filters menu (group filter + favourites)
                                    Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.cyan,
                                            Color(0xFF48CAE4),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        border: Border.all(
                                          color: AppColors.cyan
                                              .withValues(alpha: 0.3),
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.cyan
                                                .withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.more_vert,
                                            color: Colors.white),
                                        tooltip: t('filters_label'),
                                        onPressed: _showGroupFiltersSheet,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Summary Header
                          Container(
                            margin: EdgeInsets.all(16),
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.cyan, Color(0xFF48CAE4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFFF9933),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                          Icons.account_balance_wallet,
                                          color: Colors.white,
                                          size: 18),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      t('total_summary_label'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 14),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _summaryStatChip(t('total_groups_label'),
                                          '${userGroups.length}',
                                          color: const Color(0xFFFF9933),
                                          icon: Icons.groups_rounded),
                                      _summaryStatChip(
                                          t('created_label'), '$createdGroupsCount',
                                          color: const Color(0xFFFF9933),
                                          icon: Icons.add_circle_rounded),
                                      _summaryStatChip(t('expenses_label'),
                                          '${_calculateTotalExpenses()}',
                                          color: const Color(0xFFFF9933),
                                          icon: Icons.receipt_long_rounded),
                                      _summaryStatChip(
                                          t('pending_label'),
                                          _formatDisplayAmountFromInr(
                                              _calculateTotalPendingBalance()),
                                          color: const Color(0xFFFF9933),
                                          icon: Icons.hourglass_bottom_rounded),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Groups List
                          userGroups.isEmpty &&
                                  _searchController.text.isNotEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 60),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.search_off,
                                          size: 64, color: AppThemeColors.secondaryText(context)),
                                      SizedBox(height: 16),
                                      Text(
                                        t('no_groups_found_message'),
                                        style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        t('try_adjusting_search_terms_message'),
                                        style: TextStyle(
                                            color: AppThemeColors.secondaryText(context)),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 16),
                                  itemCount: userGroups.length,
                                  itemBuilder: (context, index) {
                                          final group = userGroups[index];
                                          final expenses =
                                              group['expenses'] ?? [];
                                          final members =
                                              group['members'] ?? [];
                                          final creator = group['creator'];
                                          final isFavourite =
                                              (group['favourite'] as List? ??
                                                      [])
                                                  .contains(currentUserEmail);

                                          // Use server-computed pending balance
                                          final userPendingBalance =
                                              (group['userPendingBalance'] as num? ?? 0).toDouble();
                                          final userTotalSplit = userPendingBalance;

                                          return Card(
                                            margin: EdgeInsets.only(bottom: 16),
                                            elevation: 4,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            child: Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Color(0xFFFF9933),
                                                    Color(0xFFFFFFFF),
                                                    Color(0xFF138808)
                                                  ],
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Container(
                                                margin: const EdgeInsets.all(2),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .cardColor,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: ExpansionTile(
                                                  leading: CircleAvatar(
                                                    backgroundColor:
                                                        AppColors.cyan,
                                                    backgroundImage: (group[
                                                                    'groupImageUrl'] !=
                                                                null &&
                                                            group['groupImageUrl']
                                                                .toString()
                                                                .isNotEmpty)
                                                        ? NetworkImage(group[
                                                                'groupImageUrl']
                                                            .toString())
                                                        : null,
                                                    child: (group['groupImageUrl'] !=
                                                                null &&
                                                            group['groupImageUrl']
                                                                .toString()
                                                                .isNotEmpty)
                                                        ? null
                                                        : Text(
                                                            (group['title'] ?? 'G')[0]
                                                                .toUpperCase(),
                                                            style: TextStyle(
                                                                color: Colors.white,
                                                                fontWeight:
                                                                    FontWeight.bold),
                                                          ),
                                                  ),
                                                  title: Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          group['title'] ??
                                                              t('untitled_group_label'),
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              fontSize: 16),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      IconButton(
                                                        padding: EdgeInsets.zero,
                                                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                                        icon: Icon(
                                                          isFavourite
                                                              ? Icons.star
                                                              : Icons.star_border,
                                                          color: isFavourite
                                                              ? Colors.amber
                                                              : AppThemeColors.secondaryText(context),
                                                          size: 20,
                                                        ),
                                                        onPressed: () =>
                                                            _toggleFavourite(
                                                                group['_id']),
                                                      ),
                                                      const SizedBox(width: 14),
                                                      IconButton(
                                                        padding: EdgeInsets.zero,
                                                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                                        icon: Icon(Icons.chat,
                                                            color: Colors.blue, size: 20),
                                                        onPressed: () {
                                                          Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (context) =>
                                                                  GroupChatPage(
                                                                groupTransactionId:
                                                                    group['_id'],
                                                                groupTitle: group[
                                                                        'title'] ??
                                                                    t('group_chat_label'),
                                                                members: group[
                                                                        'members'] ??
                                                                    [],
                                                                groupImageUrl: group[
                                                                        'groupImageUrl']
                                                                    ?.toString(),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  subtitle: Padding(
                                                    padding: const EdgeInsets.only(top: 4),
                                                    child: Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: [
                                                        _subtitleChip(Icons.person_outline, t('creator_label'), creator?['email'] ?? t('unknown_label')),
                                                        _subtitleChip(Icons.group_outlined, t('members_label'), '${members.length}'),
                                                        _subtitleChip(Icons.receipt_outlined, t('expenses_label'), '${expenses.length}'),
                                                        _subtitleChip(Icons.chat_bubble_outline, t('messages_label'), '${group['messageCount'] ?? 0}'),
                                                      ],
                                                    ),
                                                  ),
                                                  children: [
                                                    Container(
                                                      padding:
                                                          EdgeInsets.all(16),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          // Group Summary
                                                          Container(
                                                            padding:
                                                                EdgeInsets.all(
                                                                    12),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Color(
                                                                      0xFF00B4D8)
                                                                  .withValues(alpha: 
                                                                      0.1),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  t('your_summary_label'),
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                    color: Color(
                                                                        0xFF00B4D8),
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                    height: 8),
                                                                Row(
                                                                  children: [
                                                                    Expanded(child: Text(t('total_split_amount_label'))),
                                                                    Flexible(
                                                                      child: Text(
                                                                        _formatDisplayAmountFromInr(userTotalSplit),
                                                                        style: TextStyle(
                                                                          fontWeight: FontWeight.bold,
                                                                          color: Colors.green[700],
                                                                        ),
                                                                        overflow: TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                SizedBox(height: 4),
                                                                Row(
                                                                  children: [
                                                                    Expanded(child: Text(t('pending_balance_label'))),
                                                                    Flexible(
                                                                      child: Text(
                                                                        _formatDisplayAmountFromInr(userPendingBalance),
                                                                        style: TextStyle(
                                                                          fontWeight: FontWeight.bold,
                                                                          color: userPendingBalance > 0
                                                                              ? Colors.red[700]
                                                                              : Colors.green[700],
                                                                        ),
                                                                        overflow: TextOverflow.ellipsis,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          SizedBox(height: 16),

                                                          // Action Buttons
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .end,
                                                            children: [
                                                              Container(
                                                                decoration:
                                                                    BoxDecoration(
                                                                  gradient:
                                                                      LinearGradient(
                                                                    colors: [
                                                                      Color(
                                                                          0xFFFF9933),
                                                                      Color(
                                                                          0xFFFFFFFF),
                                                                      Color(
                                                                          0xFF138808)
                                                                    ],
                                                                    begin: Alignment
                                                                        .topCenter,
                                                                    end: Alignment
                                                                        .bottomCenter,
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              12),
                                                                ),
                                                                child:
                                                                    ElevatedButton
                                                                        .icon(
                                                                  icon: Icon(
                                                                      Icons
                                                                          .receipt_long,
                                                                      size: 18,
                                                                      color: AppThemeColors
                                                                          .primaryText(context)),
                                                                  label: Text(
                                                                      t('generate_receipt_label'),
                                                                      style: TextStyle(
                                                                          color:
                                                                              AppThemeColors.primaryText(context))),
                                                                  style: ElevatedButton
                                                                      .styleFrom(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .transparent,
                                                                    shadowColor:
                                                                        Colors
                                                                            .transparent,
                                                                    shape:
                                                                        RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              12),
                                                                    ),
                                                                  ),
                                                                  onPressed:
                                                                      () {
                                                                    _showGroupReceiptOptionsDialog(
                                                                        group);
                                                                  },
                                                                ),
                                                              ),
                                                            ],
                                                          ),

                                                          SizedBox(height: 16),

                                                          // Expenses List
                                                          if (expenses
                                                              .isNotEmpty) ...[
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  t('recent_expenses_label'),
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        16,
                                                                  ),
                                                                ),
                                                                Spacer(),
                                                                if (expenses
                                                                        .length >
                                                                    3)
                                                                  TextButton(
                                                                    onPressed: () => _showAllExpensesDialog(
                                                                        expenses,
                                                                        group['title'] ??
                                                                            t('group_label'),
                                                                        group[
                                                                            '_id']),
                                                                    child: Text(
                                                                      t('view_all_count_label').replaceFirst('{count}', '${expenses.length}'),
                                                                      style:
                                                                          TextStyle(
                                                                        color: Color(
                                                                            0xFF00B4D8),
                                                                        fontWeight:
                                                                            FontWeight.bold,
                                                                      ),
                                                                    ),
                                                                  ),
                                                              ],
                                                            ),
                                                            SizedBox(height: 8),
                                                            ...expenses
                                                                .take(3)
                                                                .map<Widget>(
                                                                    (expense) {
                                                              return Container(
                                                                margin: EdgeInsets
                                                                    .only(
                                                                        bottom:
                                                                            8),
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            12),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: AppThemeColors
                                                                      .surfaceBg(context),
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                  border: Border.all(
                                                                      color: AppThemeColors
                                                                          .border(context)),
                                                                ),
                                                                child: Column(
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  children: [
                                                                    Row(
                                                                      children: [
                                                                        Icon(Icons.receipt, color: AppColors.cyan, size: 20),
                                                                        SizedBox(width: 8),
                                                                        Expanded(
                                                                          child: Text(
                                                                            expense['description'] ?? t('no_description_label'),
                                                                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                                            overflow: TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                        SizedBox(width: 8),
                                                                        Flexible(
                                                                          flex: 0,
                                                                          child: Text(
                                                                            _formatDisplayAmountFromInr(
                                                                              _expenseAmountInInr(Map<String, dynamic>.from(expense)),
                                                                            ),
                                                                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700]),
                                                                            overflow: TextOverflow.ellipsis,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                    SizedBox(height: 4),
                                                                    Text(
                                                                      t('added_by_colon_label').replaceFirst('{email}', expense['addedBy'] ?? t('unknown_label')),
                                                                      style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12),
                                                                      overflow: TextOverflow.ellipsis,
                                                                      maxLines: 1,
                                                                    ),
                                                                    if (expense['createdAt'] != null || expense['date'] != null)
                                                                      Row(
                                                                        children: [
                                                                          Icon(Icons.access_time, color: AppThemeColors.mutedText(context), size: 12),
                                                                          SizedBox(width: 4),
                                                                          Expanded(
                                                                            child: Text(
                                                                              _formatDateTime(expense['createdAt'] ?? expense['date']),
                                                                              style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11),
                                                                              overflow: TextOverflow.ellipsis,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),

                                                                    // Split Details
                                                                    if (expense['split'] !=
                                                                            null &&
                                                                        expense['split']
                                                                            .isNotEmpty) ...[
                                                                      SizedBox(
                                                                          height:
                                                                              8),
                                                                      Container(
                                                                        padding:
                                                                            EdgeInsets.all(8),
                                                                        decoration:
                                                                            BoxDecoration(
                                                                          color:
                                                                              AppColors.cyan.withValues(alpha: 0.05),
                                                                          borderRadius:
                                                                              BorderRadius.circular(6),
                                                                          border:
                                                                              Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
                                                                        ),
                                                                        child:
                                                                            Column(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.start,
                                                                          children: [
                                                                            Row(
                                                                              children: [
                                                                                Icon(Icons.people_outline, color: AppColors.cyan, size: 14),
                                                                                SizedBox(width: 4),
                                                                                Text(
                                                                                  t('split_details_label'),
                                                                                  style: TextStyle(
                                                                                    fontSize: 12,
                                                                                    fontWeight: FontWeight.w600,
                                                                                    color: AppColors.cyan,
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                            SizedBox(height: 4),
                                                                            ...(expense['split'] as List).map<Widget>((splitItem) {
                                                                              final member = members.firstWhere(
                                                                                (m) => m['_id'] == splitItem['user'],
                                                                                orElse: () => {
                                                                                  'email': t('unknown_user_label')
                                                                                },
                                                                              );
                                                                              final isCurrentUser = member['email'] == currentUserEmail;
                                                                              final isSettled = splitItem['settled'] == true;

                                                                              return Padding(
                                                                                padding: EdgeInsets.only(bottom: 2),
                                                                                child: Row(
                                                                                  children: [
                                                                                    Expanded(
                                                                                      child: Text(
                                                                                        '• ${member['email']}',
                                                                                        style: TextStyle(
                                                                                          fontSize: 11,
                                                                                          color: AppThemeColors.secondaryText(context),
                                                                                          fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                                                                        ),
                                                                                        overflow: TextOverflow.ellipsis,
                                                                                      ),
                                                                                    ),
                                                                                    SizedBox(width: 4),
                                                                                    Text(
                                                                                      _formatDisplayAmountFromInr(_splitAmountInInr(Map<String, dynamic>.from(splitItem))),
                                                                                      style: TextStyle(
                                                                                        fontSize: 11,
                                                                                        fontWeight: FontWeight.w600,
                                                                                        color: isSettled ? Colors.grey[500] : (isCurrentUser ? AppColors.cyan : Colors.green[700]),
                                                                                        decoration: isSettled ? TextDecoration.lineThrough : null,
                                                                                      ),
                                                                                    ),
                                                                                    if (isCurrentUser)
                                                                                      Text(t('you_suffix_label'), style: TextStyle(fontSize: 10, color: AppColors.cyan, fontStyle: FontStyle.italic)),
                                                                                    if (isSettled)
                                                                                      Text(' ✓', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                                                                                  ],
                                                                                ),
                                                                              );
                                                                            }).toList(),
                                                                          ],
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ],
                                                                ),
                                                              );
                                                            }).toList(),
                                                          ] else ...[
                                                            Container(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(16),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: AppThemeColors
                                                                    .surfaceBg(context),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              child: Center(
                                                                child: Text(
                                                                  t('no_expenses_in_group_yet_message'),
                                                                  style:
                                                                      TextStyle(
                                                                    color: AppThemeColors
                                                                        .secondaryText(context),
                                                                    fontStyle:
                                                                        FontStyle
                                                                            .italic,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                        ],
                      ),
                      ),
                    ),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'join_group',
            onPressed: _showJoinGroupDialog,
            backgroundColor: AppThemeColors.cardBg(context),
            elevation: 2,
            tooltip: 'Join Group',
            child: Icon(Icons.link_rounded, color: AppColors.cyan),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.orange, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: FloatingActionButton(
              heroTag: 'add_group',
              onPressed: _openCreateGroup,
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupReceiptOptionsDialog(Map<String, dynamic> group) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 20),
              Text(
                t('generate_group_receipt_title'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Colors.blue[600],
                ),
              ),
              SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  t('choose_option_generate_receipt_for_group_message').replaceFirst('{groupTitle}', group['title']?.toString() ?? ''),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(context)),
                ),
              ),
              SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: Icon(Icons.email, color: Colors.white),
                      label: Text(t('send_to_email_label'),
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _sendGroupReceiptByEmail(group);
                      },
                    ),
                    ElevatedButton.icon(
                      icon: Icon(Icons.download, color: Colors.white),
                      label: Text(t('download_locally_label'),
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[600],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding:
                            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _downloadGroupReceiptLocally(group);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _sendGroupReceiptByEmail(Map<String, dynamic> group) async {
    final t = AppLocalizations.of(context).t;
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    if (email == null) {
      showSnack(context, t('user_email_not_found_message'), isError: true);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text(t('sending_to_email_message')),
              ],
            ),
          ),
        );
      },
    );

    try {
      final response = await ApiClient.post(
          '/api/group-transactions/${group['_id']}/receipt',
          body: {'email': email, 'action': 'email'});
      Navigator.pop(context); // Close the loading dialog
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : null;
      if (response.statusCode == 200) {
        showSnack(context, t('receipt_sent_to_email_message'));
      } else {
        String errorMessage = data?['error'] ?? t('failed_to_send_receipt_message');
        showSnack(context, errorMessage, isError: true);
      }
    } catch (e) {
      Navigator.pop(context); // Close the loading dialog
      showSnack(context, t('network_error_message').replaceFirst('{error}', e.toString()), isError: true);
    }
  }

  void _downloadGroupReceiptLocally(Map<String, dynamic> group) async {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text(t('downloading_locally_message')),
              ],
            ),
          ),
        );
      },
    );

    try {
      final user = Provider.of<SessionProvider>(context, listen: false).user;
      final email = user?['email'];

      final response = await ApiClient.post(
          '/api/group-transactions/${group['_id']}/receipt',
          body: {'email': email, 'action': 'download'});
      Navigator.pop(context); // Close the loading dialog
      if (response.statusCode == 200) {
        final output = await getTemporaryDirectory();
        final file = File('${output.path}/group-receipt-${group['_id']}.pdf');
        await file.writeAsBytes(response.bodyBytes);
        OpenFile.open(file.path);
        showSnack(context, t('receipt_downloaded_to_path_message').replaceFirst('{path}', file.path));
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        String errorMessage = data?['error'] ?? t('failed_to_download_receipt_message');
        showSnack(context, errorMessage, isError: true);
      }
    } catch (e) {
      Navigator.pop(context); // Close the loading dialog
      showSnack(context, t('network_error_message').replaceFirst('{error}', e.toString()), isError: true);
    }
  }
}
