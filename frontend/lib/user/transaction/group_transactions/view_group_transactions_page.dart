import 'package:flutter/material.dart';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../utils/share_utils.dart';
import 'package:share_plus/share_plus.dart';
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
import 'group_detail_page.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../widgets/wave_widget.dart';
import '../../../widgets/free_attempts_banner.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/share_as_note_sheet.dart';
import '../../../utils/community_helpers.dart';
import 'group_overview_page.dart';
import '../../../utils/transaction_constants.dart';

final _oidRe = RegExp(r'^[0-9a-f]{24}$');
String _sanitizeUser(dynamic v, {String fallback = 'Deleted Account'}) {
  if (v == null) return fallback;
  if (v is Map) {
    final name = (v['name'] ?? v['username'] ?? '').toString();
    if (name.isNotEmpty && !_oidRe.hasMatch(name)) return name;
    final email = (v['email'] ?? '').toString();
    if (email.isNotEmpty && !_oidRe.hasMatch(email)) return email;
    return fallback;
  }
  final s = v.toString();
  return _oidRe.hasMatch(s) ? fallback : s;
}

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
  bool _showPendingOnly = false;
  String _groupSort = 'default'; // 'default' | 'name_asc' | 'expenses_desc' | 'pending_desc'
  String _selectedMemberFilter = 'all';
  int createdGroupsCount = 0; // Track groups created by user
  String? _displayCurrencyError;
  List<Map<String, String>> _currencies = List<Map<String, String>>.from(kTxCurrencies);

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

  Future<void> _showJoinByCodeDialog() async {
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
              gradient: AppColors.tricolorGradient,
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
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0077B6), AppColors.cyan],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
                    ),
                    child: const Icon(Icons.group_add_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 16),
                  Text(t('join_group_by_code_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppThemeColors.primaryText(ctx))),
                  const SizedBox(height: 6),
                  Text('Enter the invite code shared by your group creator', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx), height: 1.4)),
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
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6, color: AppColors.cyan),
                      decoration: InputDecoration(
                        hintText: t('enter_join_code_hint'),
                        hintStyle: TextStyle(fontSize: 14, letterSpacing: 1, fontWeight: FontWeight.normal, color: AppThemeColors.mutedText(ctx)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: joining ? null : () async {
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
                        backgroundColor: AppColors.cyan, foregroundColor: Colors.white,
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

  Widget _groupImgPlaceholder(Color color, String title) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.4)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(
            title.isNotEmpty ? title[0].toUpperCase() : 'G',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: Colors.white38,
              height: 1,
            ),
          ),
        ),
      );


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

  List<Map<String, dynamic>> _memberOptions() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final myEmail = session.user?['email']?.toString() ?? '';
    final seen = <String>{};
    final opts = <Map<String, dynamic>>[{'email': 'all', 'name': 'All'}];
    for (final g in userGroups) {
      for (final m in (g['members'] as List? ?? [])) {
        final email = (m is Map ? (m['email'] ?? '') : '').toString();
        final name = (m is Map ? (m['name'] ?? m['username'] ?? email.split('@').first) : '').toString();
        if (email.isNotEmpty && email != myEmail && !seen.contains(email)) {
          seen.add(email);
          final pic = (m is Map ? (m['profileImage'] ?? m['profilePicture'] ?? '') : '').toString();
          opts.add({'email': email, 'name': name, 'profileImage': pic});
        }
      }
    }
    return opts;
  }

  List<Map<String, dynamic>> get _sortedGroups {
    var list = List<Map<String, dynamic>>.from(userGroups);
    // Member filter
    if (_selectedMemberFilter != 'all') {
      list = list.where((g) => (g['members'] as List? ?? []).any((m) =>
        m is Map && m['email']?.toString() == _selectedMemberFilter)).toList();
    }
    if (_showPendingOnly) {
      list = list.where((g) => (g['userPendingBalance'] as num? ?? 0).toDouble() != 0).toList();
    }
    switch (_groupSort) {
      case 'name_asc':
        list.sort((a, b) => (a['title'] ?? '').toString().compareTo((b['title'] ?? '').toString()));
        break;
      case 'expenses_desc':
        list.sort((a, b) {
          final ae = (b['expenses'] as List?)?.length ?? 0;
          final be = (a['expenses'] as List?)?.length ?? 0;
          return ae.compareTo(be);
        });
        break;
      case 'pending_desc':
        list.sort((a, b) {
          final ap = (b['userPendingBalance'] as num?)?.toDouble() ?? 0;
          final bp = (a['userPendingBalance'] as num?)?.toDouble() ?? 0;
          return ap.compareTo(bp);
        });
        break;
    }
    return list;
  }

  Future<void> _addExpense(String groupId, Map<String, dynamic> expenseData) async {
    final t = AppLocalizations.of(context).t;
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiClient.post('/api/group-transactions/$groupId/expenses', body: expenseData);
      final data = res.body.isNotEmpty ? json.decode(res.body) : null;
      if (res.statusCode == 200 || res.statusCode == 201) {
        await _fetchUserGroups();
        if (mounted) showSnack(context, '✅ Expense added successfully');
      } else {
        setState(() { error = data?['error'] ?? t('something_went_wrong_retry_message'); });
      }
    } catch (e) {
      setState(() { error = t('something_went_wrong_retry_message'); });
    } finally {
      if (mounted) setState(() { loading = false; });
    }
  }

  void _showAddExpenseDialog(Map<String, dynamic> group) {
    final t = AppLocalizations.of(context).t;
    final groupId = group['_id']?.toString() ?? '';
    final descController = TextEditingController();
    final amountController = TextEditingController();
    final members = List<Map<String, dynamic>>.from(group['members'] ?? []);
    final lockedCurrency = _lockedCurrencyForUserInGroup(groupId, null);
    String currency = lockedCurrency ?? 'INR';
    List<String> selectedMembers = members.map((m) => (m['email'] ?? '').toString()).toList();
    String splitType = 'equal';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppThemeColors.cardBg(context),
          title: Row(children: [
            const Icon(Icons.add_circle_rounded, color: AppColors.cyan, size: 22),
            const SizedBox(width: 8),
            Text('Add Expense', style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: t('description_label'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: t('amount_label'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: currency,
                  onChanged: lockedCurrency != null ? null : (v) { if (v != null) setS(() => currency = v); },
                  items: (_currencies.map((c) => c['code']!).toList())
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: splitType,
                decoration: InputDecoration(
                  labelText: t('split_type_label'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: [
                  DropdownMenuItem(value: 'equal', child: Text(t('equal_split_label'))),
                  DropdownMenuItem(value: 'custom', child: Text(t('custom_split_label'))),
                ],
                onChanged: (v) { if (v != null) setS(() => splitType = v); },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(t('select_members_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              ...members.map((m) {
                final email = (m['email'] ?? '').toString();
                final name = (m['name'] ?? email).toString();
                return CheckboxListTile(
                  dense: true,
                  title: Text(name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(email, style: const TextStyle(fontSize: 11)),
                  value: selectedMembers.contains(email),
                  onChanged: (v) => setS(() {
                    if (v == true) { selectedMembers.add(email); } else { selectedMembers.remove(email); }
                  }),
                );
              }),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('cancel'))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                if (descController.text.trim().isEmpty) {
                  showSnack(context, t('enter_a_description_message'), isError: true);
                  return;
                }
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) {
                  showSnack(context, t('enter_a_valid_amount'), isError: true);
                  return;
                }
                if (selectedMembers.isEmpty) {
                  showSnack(context, t('select_at_least_one_member_message'), isError: true);
                  return;
                }
                Navigator.pop(ctx);
                await _addExpense(groupId, {
                  'description': descController.text.trim(),
                  'amount': amount,
                  'currency': currency,
                  'selectedMembers': selectedMembers,
                  'splitType': splitType,
                });
              },
              child: Text(t('add_label')),
            ),
          ],
        ),
      ),
    );
  }

  void _shareGroupAsNote(Map<String, dynamic> group) {
    final groupName = (group['title'] ?? 'Group').toString();
    final members = List.from(group['members'] ?? []);
    final expenses = List.from(group['expenses'] ?? []);
    final joinCode = (group['joinCode'] ?? '').toString().trim();
    final buf = StringBuffer();
    buf.writeln('Group: $groupName');
    buf.writeln('Members: ${members.length}');
    buf.writeln('Expenses: ${expenses.length}');
    if (joinCode.isNotEmpty) buf.writeln('Join Code: $joinCode');
    showShareAsNoteSheet(context, title: groupName, content: buf.toString().trim());
  }

  Future<void> _shareGroupInvite(Map<String, dynamic> group) async {
    final joinCode = (group['joinCode'] ?? '').toString().trim();
    final groupName = (group['title'] ?? 'the group').toString();
    final appLink = await fetchAppInviteLink();
    String msg = '👥 Join "$groupName" on LenDen!\n';
    if (joinCode.isNotEmpty) {
      msg += '🔑 Join Code: $joinCode\n';
    }
    msg += '\n📱 Download LenDen & use the join code to be part of the group.';
    if (appLink.isNotEmpty) {
      msg += '\n------------------\n$appLink';
    }
    await Share.share(msg, subject: 'Join $groupName on LenDen');
    ApiClient.post('/api/referral/share', body: {'channel': 'group_invite'}).ignore();
  }

  Future<void> _openCreateGroup() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('group_creation')) {
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
              dailyRemaining = data['limits']?['groups']?['remaining'];
            }
          }),
        ]);
      } finally {
        if (mounted) Navigator.pop(context);
      }
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

  // ── Currency picker ───────────────────────────────────────────────────────
  void _showCurrencyPicker(BuildContext ctx) {
    final currencies = currencyData?.currencies ?? kCurrencyFallbacks;
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppThemeColors.cardBg(ctx),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppThemeColors.border(sheetCtx),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              const Icon(Icons.currency_exchange_rounded, color: AppColors.cyan, size: 20),
              const SizedBox(width: 10),
              Text('Currency Mode',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(sheetCtx))),
            ]),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: currencies.length,
              itemBuilder: (_, i) {
                final c = currencies[i];
                final isSel = c['code'] == selectedCurrency;
                return ListTile(
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isSel ? AppColors.cyan.withValues(alpha: 0.12) : AppThemeColors.surfaceBg(sheetCtx),
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(c['symbol']!,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: isSel ? AppColors.cyan : AppThemeColors.secondaryText(sheetCtx)))),
                  ),
                  title: Text('${c['code']}  ${c['label'] ?? c['code']}',
                      style: TextStyle(fontSize: 14,
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                          color: AppThemeColors.primaryText(sheetCtx))),
                  trailing: isSel ? const Icon(Icons.check_circle_rounded, color: AppColors.cyan, size: 20) : null,
                  onTap: () { setCurrency(c['code']!); Navigator.pop(sheetCtx); },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(sheetCtx).padding.bottom + 12),
        ],
      ),
    );
  }

  // ── Share as Note ─────────────────────────────────────────────────────────
  void _shareGroupSummaryAsNote() {
    final buf = StringBuffer();
    buf.writeln('Group Transactions Summary');
    buf.writeln('Total groups: ${userGroups.length}');
    for (final g in userGroups.take(5)) {
      final title = (g['title'] ?? 'Group').toString();
      final memberCount = (g['members'] as List?)?.length ?? 0;
      buf.writeln('- $title ($memberCount member${memberCount == 1 ? '' : 's'})');
    }
    if (userGroups.length > 5) buf.writeln('...and ${userGroups.length - 5} more');
    showShareAsNoteSheet(context, title: 'My Groups on LenDen', content: buf.toString().trim());
  }

  // ── Single Group PDF Receipt ──────────────────────────────────────────────
  Future<void> _shareGroupPdf(Map<String, dynamic> group) async {
    const darkBg    = PdfColor.fromInt(0xFF0D1B2A);
    const cyan      = PdfColor.fromInt(0xFF00BCD4);
    const textDark  = PdfColor.fromInt(0xFF1A1A1A);
    const green     = PdfColor.fromInt(0xFF2E7D32);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const white70   = PdfColor(1, 1, 1, 0.7);


    final title    = (group['title'] ?? 'Group').toString();
    final members  = (group['members'] as List? ?? []);
    final expenses = (group['expenses'] as List? ?? []);
    final creator  = group['creator'];
    final rawId    = (group['_id'] ?? '').toString();
    final shortId  = rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
    final now      = DateTime.now();
    final genLabel = DateFormat('d MMM yyyy, h:mm a').format(now);

    final totalAmt = expenses.fold<double>(0, (s, e) =>
        s + ((e is Map ? (e['amount'] as num?) : null)?.toDouble() ?? 0));

    pw.Widget rowItem(String label, String value, {PdfColor? vc}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, color: const PdfColor(0.4, 0.4, 0.4))),
        pw.Flexible(child: pw.Text(value,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: vc ?? textDark),
            textAlign: pw.TextAlign.right)),
      ]),
    );

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
            pw.Text('Group Summary', style: pw.TextStyle(color: cyan, fontSize: 13)),
            pw.SizedBox(height: 8),
            pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Ref: #$shortId', style: pw.TextStyle(color: white70, fontSize: 10)),
              pw.Text('Generated: $genLabel', style: pw.TextStyle(color: white70, fontSize: 10)),
            ]),
          ]),
        ),
        pw.SizedBox(height: 20),

        // Overview
        pw.Container(
          decoration: const pw.BoxDecoration(color: lightGrey, borderRadius: pw.BorderRadius.all(pw.Radius.circular(10))),
          padding: const pw.EdgeInsets.all(16),
          child: pw.Column(children: [
            rowItem('Creator', _sanitizeUser(creator)),
            pw.Divider(color: const PdfColor(0.85, 0.85, 0.85)),
            rowItem('Members', '${members.length}'),
            pw.Divider(color: const PdfColor(0.85, 0.85, 0.85)),
            rowItem('Total Expenses', '${expenses.length}'),
            pw.Divider(color: const PdfColor(0.85, 0.85, 0.85)),
            rowItem('Total Amount', _formatDisplayAmountFromInr(totalAmt), vc: green),
          ]),
        ),
        pw.SizedBox(height: 20),

        // Members table
        if (members.isNotEmpty) ...[
          pw.Text('Members', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: cyan)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor(0.85, 0.85, 0.85), width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(2), 1: pw.FlexColumnWidth(3), 2: pw.FlexColumnWidth(1)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
                children: ['Name', 'Email', 'Role'].map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                )).toList(),
              ),
              ...members.map<pw.TableRow>((m) {
                final mUser  = m is Map ? m['user'] : null;
                final mName  = _sanitizeUser(mUser);
                final mEmail = mUser is Map ? (mUser['email'] ?? '').toString() : '';
                final mRole  = m is Map ? (m['role'] ?? 'member').toString() : 'member';
                return pw.TableRow(children: [mName, mEmail, mRole].map((v) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(v, style: pw.TextStyle(fontSize: 9)),
                )).toList());
              }),
            ],
          ),
          pw.SizedBox(height: 20),
        ],

        // Expenses table
        if (expenses.isNotEmpty) ...[
          pw.Text('Expenses', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: cyan)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: const PdfColor(0.85, 0.85, 0.85), width: 0.5),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2)},
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
                children: ['Description', 'Amount', 'Paid By'].map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(h, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                )).toList(),
              ),
              ...expenses.map<pw.TableRow>((e) {
                final eDesc   = e is Map ? (e['description'] ?? e['title'] ?? '').toString() : '';
                final eAmt    = (e is Map ? (e['amount'] as num?) : null)?.toDouble() ?? 0;
                final eCurr   = e is Map ? (e['currency'] ?? 'INR').toString() : 'INR';
                final ePaidBy = _sanitizeUser(e is Map ? e['paidBy'] : null);
                final eAmtStr = '${txPdfSymbol(eCurr)} ${eAmt.toStringAsFixed(2)}';
                return pw.TableRow(children: [eDesc, eAmtStr, ePaidBy].map((v) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(v, style: pw.TextStyle(fontSize: 9)),
                )).toList());
              }),
            ],
          ),
          pw.SizedBox(height: 20),
        ],

        pw.Divider(),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('LenDen — Expense Splitting Made Simple',
            style: pw.TextStyle(color: const PdfColor(0.6, 0.6, 0.6), fontSize: 9))),
      ],
    ));

    final bytes    = await doc.save();
    final filename = 'lenden_group_$shortId.pdf';
    await shareBytesFile(bytes: bytes, filename: filename, mimeType: 'application/pdf',
        subject: '$title – Group Summary');
  }

  // ── CSV Export ────────────────────────────────────────────────────────────
  Future<void> _exportCsv() async {
    if (userGroups.isEmpty) {
      ElegantNotification.error(
        title: const Text('Nothing to export', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('No groups to export'),
      ).show(context);
      return;
    }
    final buf = StringBuffer();
    buf.writeln('Group,Expense Description,Amount (INR),Currency,Added By,Date,Members');
    String cell(dynamic v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    for (final group in userGroups) {
      final groupTitle = (group['title'] ?? 'Unknown Group').toString();
      final expenses = List<Map<String, dynamic>>.from(group['expenses'] ?? []);
      if (expenses.isEmpty) {
        buf.writeln([cell(groupTitle), cell('—'), cell('0.00'), cell('INR'), cell('—'), cell('—'), cell('—')].join(','));
      }
      for (final expense in expenses) {
        final members = (expense['selectedMembers'] as List?)?.join('; ') ?? '';
        final dateStr = (expense['createdAt'] ?? expense['date'] ?? '').toString().split('T').first;
        buf.writeln([
          cell(groupTitle),
          cell(expense['description']),
          cell((_expenseAmountInInr(expense)).toStringAsFixed(2)),
          cell(expense['currency'] ?? 'INR'),
          cell(_sanitizeUser(expense['addedBy'])),
          cell(dateStr),
          cell(members),
        ].join(','));
      }
    }
    final now = DateTime.now();
    final filename = 'lenden_groups_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
    final ok = await shareTextFile(content: buf.toString(), filename: filename, subject: 'LenDen Group Transactions Export');
    if (!ok && mounted) {
      ElegantNotification.error(
        title: const Text('Export failed', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('Could not export the file'),
      ).show(context);
    }
  }

  // ── PDF Export ────────────────────────────────────────────────────────────
  Future<void> _exportPdf() async {
    if (userGroups.isEmpty) {
      ElegantNotification.error(
        title: const Text('Nothing to export', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('No groups to export'),
      ).show(context);
      return;
    }

    const darkBg    = PdfColor.fromInt(0xFF0D1B2A);
    const cyan      = PdfColor.fromInt(0xFF00BCD4);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const textDark  = PdfColor.fromInt(0xFF1A1A1A);
    const green     = PdfColor.fromInt(0xFF2E7D32);
    const white70   = PdfColor(1, 1, 1, 0.7);


    pw.Widget pCell(String text, {bool bold = false, PdfColor? color}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color ?? textDark)),
        );

    final now = DateTime.now();
    final genLabel = DateFormat('d MMM yyyy, h:mm a').format(now);
    final totalExpenses = userGroups.fold(0, (s, g) => s + ((g['expenses'] as List?)?.length ?? 0));
    final totalAmount = userGroups.fold(0.0, (s, g) {
      final expenses = List<Map<String, dynamic>>.from(g['expenses'] ?? []);
      return s + expenses.fold(0.0, (es, e) => es + _expenseAmountInInr(e));
    });

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
            pw.Text('Group Transactions Report', style: pw.TextStyle(color: cyan, fontSize: 13)),
            pw.SizedBox(height: 12),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('${userGroups.length} group${userGroups.length == 1 ? '' : 's'} · $totalExpenses expense${totalExpenses == 1 ? '' : 's'}', style: pw.TextStyle(color: white70, fontSize: 10)),
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
              pw.Text('Groups', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('${userGroups.length}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: textDark)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Total Expenses', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('$totalExpenses', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: textDark)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Total Amount (INR)', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              pw.Text('${txPdfSymbol('INR')}${totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
            ]),
          ]),
        ),

        // Per-group tables
        for (final group in userGroups) ...[
          pw.Container(
            decoration: const pw.BoxDecoration(color: darkBg, borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
            padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
            margin: const pw.EdgeInsets.only(bottom: 6),
            child: pw.Text((group['title'] ?? 'Unnamed Group').toString(),
                style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 11)),
          ),
          () {
            final expenses = List<Map<String, dynamic>>.from(group['expenses'] ?? []);
            if (expenses.isEmpty) {
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14, left: 4),
                child: pw.Text('No expenses recorded.', style: pw.TextStyle(color: PdfColors.grey600, fontSize: 9)),
              );
            }
            return pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2.2),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.4),
                3: const pw.FlexColumnWidth(1.2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE0E0E0)),
                  children: ['Description', 'Amount (INR)', 'Added By', 'Date']
                      .map((h) => pCell(h, bold: true)).toList(),
                ),
                for (int i = 0; i < expenses.length; i++) () {
                  final e = expenses[i];
                  final amt = _expenseAmountInInr(e);
                  final dateStr = (e['createdAt'] ?? e['date'] ?? '').toString().split('T').first;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: i.isEven ? lightGrey : null),
                    children: [
                      pCell((e['description'] ?? '—').toString()),
                      pCell('${txPdfSymbol('INR')}${amt.toStringAsFixed(2)}', color: green),
                      pCell(_sanitizeUser(e['addedBy'], fallback: '—')),
                      pCell(dateStr),
                    ],
                  );
                }(),
              ],
            );
          }(),
          pw.SizedBox(height: 16),
        ],
      ],
    ));

    final bytes = await doc.save();
    final filename = 'lenden_groups_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
    final ok = await shareBytesFile(bytes: bytes, filename: filename, mimeType: 'application/pdf', subject: 'LenDen Group Transactions Report');
    if (!ok && mounted) {
      ElegantNotification.error(
        title: const Text('Export failed', style: TextStyle(fontWeight: FontWeight.bold)),
        description: const Text('Could not export the PDF'),
      ).show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentUserEmail = session.user?['email'];

    return Scaffold(
      appBar: AppBar(
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
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: AppThemeColors.primaryText(context)),
              onSelected: (value) {
                if (value == 'export_csv') _exportCsv();
                if (value == 'export_pdf') _exportPdf();
                if (value == 'share_as_note') _shareGroupSummaryAsNote();
                if (value == 'currency_mode') _showCurrencyPicker(context);
                if (value == 'join_by_code') _showJoinByCodeDialog();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'join_by_code',
                  child: Row(children: [
                    const Icon(Icons.group_add_rounded, size: 18, color: AppColors.cyan),
                    const SizedBox(width: 12),
                    Text(AppLocalizations.of(context).t('join_by_code_menu_label')),
                  ]),
                ),
                PopupMenuItem(
                  value: 'currency_mode',
                  child: Row(children: [
                    const Icon(Icons.currency_exchange_rounded, size: 18, color: AppColors.cyan),
                    const SizedBox(width: 12),
                    Text('Currency: $selectedCurrency'),
                  ]),
                ),
                if (userGroups.isNotEmpty) ...[
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
                  const PopupMenuItem(
                    value: 'share_as_note',
                    child: Row(children: [
                      Icon(Icons.note_add_rounded, size: 18, color: AppColors.tricolorGreen),
                      SizedBox(width: 12),
                      Text('Share as Note'),
                    ]),
                  ),
                ],
              ],
            ),
          ],
        ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? errorStateWidget(context, error!, _fetchUserGroups)
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
                                          gradient: AppColors.tricolorGradient,
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
                                        color: AppColors.tricolorOrange,
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
                                          color: AppColors.tricolorOrange,
                                          icon: Icons.groups_rounded),
                                      _summaryStatChip(
                                          t('created_label'), '$createdGroupsCount',
                                          color: AppColors.tricolorOrange,
                                          icon: Icons.add_circle_rounded),
                                      _summaryStatChip(t('expenses_label'),
                                          '${_calculateTotalExpenses()}',
                                          color: AppColors.tricolorOrange,
                                          icon: Icons.receipt_long_rounded),
                                      _summaryStatChip(
                                          t('pending_label'),
                                          _formatDisplayAmountFromInr(
                                              _calculateTotalPendingBalance()),
                                          color: AppColors.tricolorOrange,
                                          icon: Icons.hourglass_bottom_rounded),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const FreeAttemptsBanner(featureKey: 'group_creation'),
                          // Sort chips
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
                                Text('Sort:', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                                const SizedBox(width: 8),
                                for (final opt in [
                                  ('default', 'Default'),
                                  ('name_asc', 'A–Z'),
                                  ('expenses_desc', 'Most Expenses'),
                                  ('pending_desc', 'Pending'),
                                ])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: ChoiceChip(
                                      label: Text(opt.$2, style: const TextStyle(fontSize: 12)),
                                      selected: _groupSort == opt.$1,
                                      selectedColor: AppColors.cyan.withValues(alpha: 0.2),
                                      onSelected: (_) => setState(() => _groupSort = opt.$1),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                FilterChip(
                                  label: const Text('Has Pending', style: TextStyle(fontSize: 12)),
                                  selected: _showPendingOnly,
                                  selectedColor: Colors.orange.withValues(alpha: 0.2),
                                  checkmarkColor: Colors.orange,
                                  onSelected: (v) => setState(() => _showPendingOnly = v),
                                ),
                              ]),
                            ),
                          ),
                          // Member filter strip
                          if (userGroups.isNotEmpty) Builder(builder: (ctx) {
                            final members = _memberOptions();
                            if (members.length <= 1) return const SizedBox.shrink();
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                                child: Row(children: [
                                  Container(width: 22, height: 22, decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                    child: const Icon(Icons.people_alt_outlined, size: 13, color: AppColors.cyan)),
                                  const SizedBox(width: 6),
                                  Text('Filter by Member', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppThemeColors.secondaryText(context))),
                                ]),
                              ),
                              SizedBox(
                                height: 64,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: members.length,
                                  itemBuilder: (ctx2, mi) {
                                    final m = members[mi];
                                    final email = m['email'] as String;
                                    final name = m['name'] as String;
                                    final pic = (m['profileImage'] ?? '').toString();
                                    final isAll = email == 'all';
                                    final isSelected = _selectedMemberFilter == email;
                                    return GestureDetector(
                                      onTap: () => setState(() => _selectedMemberFilter = isSelected && !isAll ? 'all' : email),
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                          Container(
                                            width: 38, height: 38,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(color: isSelected ? AppColors.cyan : AppThemeColors.border(ctx2), width: isSelected ? 2 : 1),
                                            ),
                                            child: ClipOval(
                                              child: (!isAll && pic.isNotEmpty)
                                                ? Image.network(pic, width: 38, height: 38, fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(
                                                      color: isSelected ? AppColors.cyan.withValues(alpha: 0.14) : AppThemeColors.surfaceBg(ctx2),
                                                      child: Icon(Icons.person_rounded, size: 18, color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                                    ))
                                                : Container(
                                                    color: isSelected ? AppColors.cyan.withValues(alpha: 0.14) : AppThemeColors.surfaceBg(ctx2),
                                                    child: Icon(isAll ? Icons.groups_rounded : Icons.person_rounded, size: 18,
                                                      color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          SizedBox(
                                            width: 48,
                                            child: Text(
                                              isAll ? 'All' : name.isEmpty ? email.split('@').first : name.split(' ').first,
                                              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                              style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                                color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(ctx2)),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ]);
                          }),

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
                                  itemCount: _sortedGroups.length,
                                  itemBuilder: (context, index) {
                                          final group = _sortedGroups[index];
                                          final expenses =
                                              group['expenses'] ?? [];
                                          final members =
                                              group['members'] ?? [];
                                          final isFavourite =
                                              (group['favourite'] as List? ??
                                                      [])
                                                  .contains(currentUserEmail);

                                          // Use server-computed pending balance
                                          final userPendingBalance =
                                              (group['userPendingBalance'] as num? ?? 0).toDouble();

                                          // Photo-card variables
                                          final groupColor = group['color'] != null && group['color'].toString().isNotEmpty
                                              ? Color(int.parse(group['color'].toString().replaceFirst('#', '0xff')))
                                              : AppColors.cyan;
                                          final imgUrl = (group['groupImageUrl']?.toString() ?? '').isNotEmpty
                                              ? group['groupImageUrl'].toString()
                                              : defaultGroupImageUrl(group['title']?.toString() ?? '');
                                          final mList = members is List ? members : [];
                                          final eList = expenses is List ? expenses : [];

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 18),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                // ── PHOTO CARD ──
                                                GestureDetector(
                                                  onTap: () => Navigator.push(context, MaterialPageRoute(
                                                    builder: (_) => GroupOverviewPage(
                                                      group: group,
                                                      userPendingBalance: userPendingBalance,
                                                      formatAmount: _formatDisplayAmountFromInr,
                                                      expenseAmountInInr: _expenseAmountInInr,
                                                      splitAmountInInr: _splitAmountInInr,
                                                      currentUserEmail: currentUserEmail?.toString() ?? '',
                                                      unreadMessageCount: (group['unreadMessageCount'] as num? ?? 0).toInt(),
                                                      onGenerateReceipt: () => _showGroupReceiptOptionsDialog(group),
                                                      onAddExpense: () => _showAddExpenseDialog(group),
                                                      onShareInvite: () => _shareGroupInvite(group),
                                                      onShareAsNote: () => _shareGroupAsNote(group),
                                                      onShareAsPdf: () => _shareGroupPdf(group),
                                                    ),
                                                  )),
                                                  child: Container(
                                                    height: 185,
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(20),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: groupColor.withValues(alpha: 0.25),
                                                          blurRadius: 16,
                                                          offset: const Offset(0, 6),
                                                        ),
                                                      ],
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.circular(20),
                                                      child: Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          if (imgUrl.isNotEmpty)
                                                            Image.network(
                                                              imgUrl,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_, __, ___) => _groupImgPlaceholder(
                                                                groupColor,
                                                                group['title']?.toString() ?? '',
                                                              ),
                                                            )
                                                          else
                                                            _groupImgPlaceholder(
                                                              groupColor,
                                                              group['title']?.toString() ?? '',
                                                            ),
                                                          Container(
                                                            decoration: const BoxDecoration(
                                                              gradient: LinearGradient(
                                                                colors: [Color(0x33000000), Color(0xDD000000)],
                                                                begin: Alignment.topCenter,
                                                                end: Alignment.bottomCenter,
                                                              ),
                                                            ),
                                                          ),
                                                          Padding(
                                                            padding: const EdgeInsets.all(14),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                // Top row: color dot + balance chip + fav + chat
                                                                Row(
                                                                  children: [
                                                                    Container(
                                                                      width: 11, height: 11,
                                                                      decoration: BoxDecoration(
                                                                        color: groupColor,
                                                                        shape: BoxShape.circle,
                                                                        border: Border.all(color: Colors.white, width: 1.5),
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 8),
                                                                    if (userPendingBalance != 0.0)
                                                                      Container(
                                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                                        decoration: BoxDecoration(
                                                                          color: (userPendingBalance > 0 ? Colors.red.shade700 : Colors.green.shade700).withValues(alpha: 0.88),
                                                                          borderRadius: BorderRadius.circular(20),
                                                                        ),
                                                                        child: Text(
                                                                          _formatDisplayAmountFromInr(userPendingBalance),
                                                                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                                                                        ),
                                                                      ),
                                                                    const Spacer(),
                                                                    GestureDetector(
                                                                      onTap: () => _toggleFavourite(group['_id']),
                                                                      child: Icon(
                                                                        isFavourite ? Icons.star_rounded : Icons.star_border_rounded,
                                                                        color: isFavourite ? Colors.amber : Colors.white,
                                                                        size: 22,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 12),
                                                                    Stack(
                                                                      clipBehavior: Clip.none,
                                                                      children: [
                                                                        GestureDetector(
                                                                          onTap: () => Navigator.push(context, MaterialPageRoute(
                                                                            builder: (context) => GroupChatPage(
                                                                              groupTransactionId: group['_id'],
                                                                              groupTitle: group['title'] ?? t('group_chat_label'),
                                                                              members: group['members'] ?? [],
                                                                              groupImageUrl: group['groupImageUrl']?.toString(),
                                                                            ),
                                                                          )),
                                                                          child: const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
                                                                        ),
                                                                        if ((group['unreadMessageCount'] as num? ?? 0) > 0)
                                                                          Positioned(
                                                                            right: -2, top: -2,
                                                                            child: Container(
                                                                              width: 9, height: 9,
                                                                              decoration: BoxDecoration(
                                                                                color: Colors.green.shade500,
                                                                                shape: BoxShape.circle,
                                                                                border: Border.all(color: Colors.white, width: 1.5),
                                                                              ),
                                                                            ),
                                                                          ),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                ),
                                                                const Spacer(),
                                                                // Bottom row: title + members | View Details + expand pill
                                                                Row(
                                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                                  children: [
                                                                    Expanded(
                                                                      child: Column(
                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text(
                                                                            group['title']?.toString() ?? t('untitled_group_label'),
                                                                            style: const TextStyle(
                                                                              color: Colors.white,
                                                                              fontSize: 18,
                                                                              fontWeight: FontWeight.bold,
                                                                              shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                                                                            ),
                                                                            overflow: TextOverflow.ellipsis,
                                                                          ),
                                                                          const SizedBox(height: 4),
                                                                          Builder(builder: (_) {
                                                                            final catKey = (group['category'] ?? 'other').toString();
                                                                            return Row(mainAxisSize: MainAxisSize.min, children: [
                                                                              Icon(txCatIcon(catKey), size: 11, color: Colors.white70),
                                                                              const SizedBox(width: 3),
                                                                              Text(txCatLabel(catKey), style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w500)),
                                                                            ]);
                                                                          }),
                                                                          const SizedBox(height: 3),
                                                                          Row(
                                                                            children: [
                                                                              // Show unique member avatars (no creator duplication)
                                                                              ...mList.take(4).toList().asMap().entries.map((e) {
                                                                                final mu = e.value is Map ? (e.value['user'] ?? e.value) : e.value;
                                                                                final mp = (mu is Map ? (mu['profileImage'] ?? mu['profilePicture'] ?? '') : '').toString();
                                                                                final mi = (mu is Map ? (mu['name'] ?? mu['email'] ?? '?') : '?').toString();
                                                                                return Transform.translate(
                                                                                  offset: Offset(e.key * -5.0, 0),
                                                                                  child: CircleAvatar(
                                                                                    radius: 10,
                                                                                    backgroundColor: AppColors.cyan,
                                                                                    child: ClipOval(
                                                                                      child: mp.isNotEmpty
                                                                                          ? Image.network(
                                                                                              mp,
                                                                                              width: 20, height: 20,
                                                                                              fit: BoxFit.cover,
                                                                                              errorBuilder: (_, __, ___) => Center(
                                                                                                child: Text(mi.isNotEmpty ? mi[0].toUpperCase() : '?',
                                                                                                    style: const TextStyle(fontSize: 8, color: Colors.white)),
                                                                                              ),
                                                                                            )
                                                                                          : Center(child: Text(mi.isNotEmpty ? mi[0].toUpperCase() : '?',
                                                                                              style: const TextStyle(fontSize: 8, color: Colors.white))),
                                                                                    ),
                                                                                  ),
                                                                                );
                                                                              }),
                                                                              const SizedBox(width: 4),
                                                                              Text('${mList.length} member${mList.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                                                              const SizedBox(width: 8),
                                                                              const Icon(Icons.receipt_outlined, color: Colors.white70, size: 12),
                                                                              const SizedBox(width: 3),
                                                                              Text('${eList.length} expense${eList.length == 1 ? '' : 's'}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                                                            ],
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 8),
                                                                    Column(
                                                                      mainAxisSize: MainAxisSize.min,
                                                                      crossAxisAlignment: CrossAxisAlignment.end,
                                                                      children: [
                                                                        OutlinedButton(
                                                                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                                                                            builder: (_) => GroupDetailPage(
                                                                              groupId: group['_id']?.toString() ?? '',
                                                                              initialGroup: group,
                                                                            ),
                                                                          )),
                                                                          style: OutlinedButton.styleFrom(
                                                                            foregroundColor: Colors.white,
                                                                            side: const BorderSide(color: Colors.white, width: 1.5),
                                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                                                            minimumSize: Size.zero,
                                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                          ),
                                                                          child: const Text('View Details →', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                                                                        ),
                                                                        const SizedBox(height: 6),
                                                                        Container(
                                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                                                                          child: Row(
                                                                            mainAxisSize: MainAxisSize.min,
                                                                            children: [
                                                                              const Text('Overview', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                                                              const SizedBox(width: 2),
                                                                              const Icon(Icons.keyboard_arrow_right_rounded, color: Colors.white, size: 16),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                        ],
                      ),
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
              heroTag: 'add_group',
              onPressed: _openCreateGroup,
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
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
