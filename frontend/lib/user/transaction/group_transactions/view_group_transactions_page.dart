import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/display_currency_helper.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../../chats/group_chat_page.dart';
import 'create_group_page.dart';
import '../../../widgets/stylish_dialog.dart';

class ViewGroupTransactionsPage extends StatefulWidget {
  const ViewGroupTransactionsPage({super.key});

  @override
  State<ViewGroupTransactionsPage> createState() =>
      _ViewGroupTransactionsPageState();
}

class _ViewGroupTransactionsPageState extends State<ViewGroupTransactionsPage> {
  List<Map<String, dynamic>> userGroups = [];
  bool loading = true;
  String? error;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  String selectedGroupFilter =
      'All Groups'; // 'All Groups', 'Joined Groups', 'Left Groups'
  bool _showFavouritesOnly = false;
  int createdGroupsCount = 0; // Track groups created by user
  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
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
    _loadDisplayCurrencies();
    _fetchUserGroups();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
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
        setState(() {
          error = 'Failed to load group transactions. Please try again.';
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

  // Helper function to format date and time
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'Unknown';

    try {
      DateTime date;
      if (dateTime is String) {
        date = DateTime.parse(dateTime);
      } else if (dateTime is DateTime) {
        date = dateTime;
      } else {
        return 'Invalid date';
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
      return 'Invalid date';
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
                  color: Colors.white,
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
                      'Oops! Something went wrong',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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

  Widget _summaryStatChip(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _formatDisplayAmountFromInr(num amount) {
    final targetCurrency = _selectedDisplayCurrency.toUpperCase();
    if (targetCurrency != 'INR' &&
        !(_displayCurrencyData?.canConvert('INR', targetCurrency) ?? false)) {
      return _formatInr(amount);
    }
    final converted = _displayCurrencyData?.convert(
          amount,
          'INR',
          targetCurrency,
        ) ??
        amount.toDouble();
    final symbol = _displayCurrencyData?.symbolFor(targetCurrency) ?? '₹';
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
        showSnack(context, '✅ Expense updated successfully!');
      } else {
        setState(() {
          error = data?['error'] ?? 'Failed to update expense';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Something went wrong. Please try again.';
      });
    } finally {
      setState(() {
        loading = false;
      });
    }
  }

  void _showEditExpenseDialog(Map<String, dynamic> expense, String groupId) {
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
          backgroundColor: Colors.white,
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
                  'Edit Expense',
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
                    'Description',
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
                      hintText: 'Enter expense description',
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
                    'Currency',
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
                          ? 'Locked to $lockedCurrency because the first expense in this group used that currency.'
                          : 'You can use a different currency in other groups.',
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
                    'Amount',
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
                      hintText: 'Enter amount',
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
                    'Select Members',
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
                    'Split Type',
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
                          value: 'equal', child: Text('Equal Split')),
                      DropdownMenuItem(
                          value: 'custom', child: Text('Custom Split')),
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
                        'Cancel',
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
                          showSnack(context, 'Please enter a description', isError: true);
                          return;
                        }

                        final amount =
                            double.tryParse(editAmountController.text);
                        if (amount == null || amount <= 0) {
                          showSnack(context, 'Please enter a valid amount', isError: true);
                          return;
                        }

                        if (editSelectedMembers.isEmpty) {
                          showSnack(context, 'Please select at least one member', isError: true);
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
                        'Update',
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
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
                'All Expenses - $groupTitle',
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
                        'Total Expenses: ${expenses.length}',
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
                      color: Colors.white,
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
                        expense['description'] ?? 'No description',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.cyan,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount: ${_formatDisplayAmountFromInr(_expenseAmountInInr(Map<String, dynamic>.from(expense)))}',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Added by: ${expense['addedBy'] ?? 'Unknown'}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          if (expense['createdAt'] != null ||
                              expense['date'] != null)
                            Row(
                              children: [
                                Icon(Icons.access_time,
                                    color: Colors.grey[500], size: 12),
                                SizedBox(width: 4),
                                Text(
                                  _formatDateTime(
                                      expense['createdAt'] ?? expense['date']),
                                  style: TextStyle(
                                    color: Colors.grey[500],
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
                'Close',
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
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.isSubscribed) {
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
            message:
                'You\'ve reached today\'s limit of 1 group creation. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
        return;
      }
      final freeRemaining = session.freeGroupsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: 'group creation', coinCost: 20, currentCoins: coins);
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
    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentUserEmail = session.user?['email'];

    return Scaffold(
      appBar: AppBar(
        title: Text('View Group Transactions'),
        backgroundColor: AppColors.cyan,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDisplayCurrency,
                  dropdownColor: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  items: (_displayCurrencyData?.currencies ?? _currencies)
                      .map(
                        (currency) => DropdownMenuItem(
                          value: currency['code'],
                          child: Text(
                            '${currency['symbol']} ${currency['code']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
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
          ),
        ],
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
                              size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No Group Transactions Found',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'You are not part of any group transactions yet.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchUserGroups,
                      child: Column(
                        children: [
                          // Search and Filter Row
                          Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Column(
                              children: [
                                if (_displayCurrencyError != null ||
                                    (_selectedDisplayCurrency != 'INR' &&
                                        !(_displayCurrencyData?.canConvert(
                                              'INR',
                                              _selectedDisplayCurrency,
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
                                                'Conversion to $_selectedDisplayCurrency is not available yet. Showing INR values instead.',
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
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(18),
                                          ),
                                          child: TextField(
                                            controller: _searchController,
                                            decoration: InputDecoration(
                                              labelText: 'Search Groups',
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
                                                  'Search by group name, members, or expenses...',
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

                                    // Groups Filter Dropdown
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(20),
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
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: selectedGroupFilter,
                                          onChanged: _onGroupFilterChanged,
                                          icon: Icon(Icons.arrow_drop_down,
                                              color: Colors.white),
                                          dropdownColor: AppColors.cyan,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          items: [
                                            DropdownMenuItem(
                                              value: 'All Groups',
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.group,
                                                      color: Colors.white,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text('All Groups'),
                                                ],
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Joined Groups',
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.group_add,
                                                      color: Colors.white,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Joined Groups'),
                                                ],
                                              ),
                                            ),
                                            DropdownMenuItem(
                                              value: 'Left Groups',
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.group_remove,
                                                      color: Colors.white,
                                                      size: 18),
                                                  SizedBox(width: 8),
                                                  Text('Left Groups'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 8.0),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    gradient: const LinearGradient(
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
                                        color: Colors.grey.withValues(alpha: 0.5),
                                        spreadRadius: 1,
                                        blurRadius: 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: SwitchListTile(
                                      title: const Text(
                                        'Show Favourites Only',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.cyan,
                                        ),
                                      ),
                                      value: _showFavouritesOnly,
                                      onChanged: (bool value) {
                                        setState(() => _showFavouritesOnly = value);
                                        _fetchUserGroups();
                                      },
                                      activeColor: AppColors.cyan,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Summary Header
                          Container(
                            margin: EdgeInsets.all(16),
                            padding: EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.cyan, Color(0xFF48CAE4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.account_balance_wallet,
                                        color: Colors.white, size: 24),
                                    SizedBox(width: 8),
                                    Text(
                                      'Total Summary',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 12),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _summaryStatChip('Total Groups', '${userGroups.length}'),
                                      _summaryStatChip('Created', '$createdGroupsCount'),
                                      _summaryStatChip('Expenses', '${_calculateTotalExpenses()}'),
                                      _summaryStatChip('Pending', _formatDisplayAmountFromInr(_calculateTotalPendingBalance())),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Groups List
                          Expanded(
                            child:
                                userGroups.isEmpty &&
                                        _searchController.text.isNotEmpty
                                    ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.search_off,
                                                size: 64, color: Colors.grey),
                                            SizedBox(height: 16),
                                            Text(
                                              'No Groups Found',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'Try adjusting your search terms.',
                                              style: TextStyle(
                                                  color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
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
                                                    child: Text(
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
                                                              'Untitled Group',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              fontSize: 16),
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      IconButton(
                                                        padding: EdgeInsets.zero,
                                                        constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                                        icon: Icon(
                                                          isFavourite
                                                              ? Icons.star
                                                              : Icons.star_border,
                                                          color: isFavourite
                                                              ? Colors.amber
                                                              : Colors.grey,
                                                          size: 20,
                                                        ),
                                                        onPressed: () =>
                                                            _toggleFavourite(
                                                                group['_id']),
                                                      ),
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
                                                                    'Group Chat',
                                                                members: group[
                                                                        'members'] ??
                                                                    [],
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
                                                        _subtitleChip(Icons.person_outline, 'Creator', creator?['email'] ?? 'Unknown'),
                                                        _subtitleChip(Icons.group_outlined, 'Members', '${members.length}'),
                                                        _subtitleChip(Icons.receipt_outlined, 'Expenses', '${expenses.length}'),
                                                        _subtitleChip(Icons.chat_bubble_outline, 'Messages', '${group['messageCount'] ?? 0}'),
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
                                                                  'Your Summary',
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
                                                                    Expanded(child: Text('Total Split Amount:')),
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
                                                                    Expanded(child: Text('Pending Balance:')),
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
                                                                      color: Colors
                                                                          .black),
                                                                  label: Text(
                                                                      'Generate Receipt',
                                                                      style: TextStyle(
                                                                          color:
                                                                              Colors.black)),
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
                                                                  'Recent Expenses',
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
                                                                            'Group',
                                                                        group[
                                                                            '_id']),
                                                                    child: Text(
                                                                      'View All (${expenses.length})',
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
                                                                  color: Colors
                                                                      .grey[50],
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              8),
                                                                  border: Border.all(
                                                                      color: Colors
                                                                              .grey[
                                                                          300]!),
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
                                                                            expense['description'] ?? 'No description',
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
                                                                      'Added by: ${expense['addedBy'] ?? 'Unknown'}',
                                                                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                                                      overflow: TextOverflow.ellipsis,
                                                                      maxLines: 1,
                                                                    ),
                                                                    if (expense['createdAt'] != null || expense['date'] != null)
                                                                      Row(
                                                                        children: [
                                                                          Icon(Icons.access_time, color: Colors.grey[500], size: 12),
                                                                          SizedBox(width: 4),
                                                                          Expanded(
                                                                            child: Text(
                                                                              _formatDateTime(expense['createdAt'] ?? expense['date']),
                                                                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
                                                                                  'Split Details:',
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
                                                                                  'email': 'Unknown User'
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
                                                                                          color: Colors.grey[600],
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
                                                                                      Text(' (You)', style: TextStyle(fontSize: 10, color: AppColors.cyan, fontStyle: FontStyle.italic)),
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
                                                                color: Colors
                                                                    .grey[100],
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              child: Center(
                                                                child: Text(
                                                                  'No expenses in this group yet',
                                                                  style:
                                                                      TextStyle(
                                                                    color: Colors
                                                                            .grey[
                                                                        600],
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
                          ),
                        ],
                      ),
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
          onPressed: _openCreateGroup,
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  void _showGroupReceiptOptionsDialog(Map<String, dynamic> group) {
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
                'Generate Group Receipt',
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
                  'Choose an option to generate the receipt for the group "${group['title']}".',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black87),
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
                      label: Text('Send to Email',
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
                      label: Text('Download Locally',
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
    final user = Provider.of<SessionProvider>(context, listen: false).user;
    final email = user?['email'];
    if (email == null) {
      showSnack(context, 'User email not found.', isError: true);
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
                Text("Sending to email..."),
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
        showSnack(context, 'Receipt sent to your email!');
      } else {
        String errorMessage = data?['error'] ?? 'Failed to send receipt';
        showSnack(context, errorMessage, isError: true);
      }
    } catch (e) {
      Navigator.pop(context); // Close the loading dialog
      showSnack(context, 'Network error: ${e.toString()}', isError: true);
    }
  }

  void _downloadGroupReceiptLocally(Map<String, dynamic> group) async {
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
                Text("Downloading locally..."),
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
        showSnack(context, 'Receipt downloaded to ${file.path}');
      } else {
        final data =
            response.body.isNotEmpty ? jsonDecode(response.body) : null;
        String errorMessage = data?['error'] ?? 'Failed to download receipt';
        showSnack(context, errorMessage, isError: true);
      }
    } catch (e) {
      Navigator.pop(context); // Close the loading dialog
      showSnack(context, 'Network error: ${e.toString()}', isError: true);
    }
  }
}
