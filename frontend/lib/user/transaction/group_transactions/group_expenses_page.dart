import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/budget_exceeded_sheet.dart';
import '../../../widgets/currency_display.dart';
import '../../../session.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../utils/share_utils.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/search_tab_bar.dart';
import './widgets/group_expense_helpers.dart';
import './widgets/add_expense_sheet.dart';

class GroupExpensesPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final bool isCreator;
  final String userEmail;
  final List<dynamic> initialExpenses;
  final List<dynamic> initialMembers;
  final List<dynamic> initialMemberPayments;
  final bool openAddExpense;

  const GroupExpensesPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.isCreator,
    required this.userEmail,
    required this.initialExpenses,
    required this.initialMembers,
    this.initialMemberPayments = const [],
    this.openAddExpense = false,
  });

  @override
  State<GroupExpensesPage> createState() => _GroupExpensesPageState();
}

class _GroupExpensesPageState extends State<GroupExpensesPage>
    with CurrencyDisplayMixin<GroupExpensesPage> {
  late List<dynamic> _expenses;
  late List<dynamic> _members;
  late List<dynamic> _memberPayments;
  bool _loading = false;
  String _filter = 'all';
  String _searchQuery = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  int _dailyExpenseLimit = 3;
  int _dailyExpenseUsed = 0;

  final _searchCtrl = TextEditingController();

  static const _kFallbackCurrencies = [
    {'code': 'INR', 'symbol': '₹'},
    {'code': 'USD', 'symbol': '\$'},
    {'code': 'EUR', 'symbol': '€'},
    {'code': 'GBP', 'symbol': '£'},
    {'code': 'JPY', 'symbol': '¥'},
    {'code': 'CAD', 'symbol': '\$'},
    {'code': 'AUD', 'symbol': '\$'},
    {'code': 'CHF', 'symbol': 'Fr'},
  ];

  @override
  void initState() {
    super.initState();
    _expenses = List<dynamic>.from(widget.initialExpenses);
    _members = List<dynamic>.from(widget.initialMembers);
    _memberPayments = List<dynamic>.from(widget.initialMemberPayments);
    loadCurrencies();
    _fetchDailyExpenseLimit();
    if (widget.openAddExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAddExpense());
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDailyExpenseLimit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.hasFeature('group_expenses')) return;
    try {
      final res = await ApiClient.get(
          '/api/limits/group/${widget.groupId}/expenses');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _dailyExpenseLimit = data['limit'] ?? 3;
            _dailyExpenseUsed = data['used'] ?? 0;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _openAddExpense() async {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('group_expenses')) {
      await Future.wait([
        session.loadFreebieCounts(),
        _fetchDailyExpenseLimit(),
      ]);
    }
    if (!session.hasFeature('group_expenses') && _dailyExpenseUsed >= _dailyExpenseLimit) {
      final coins = session.lenDenCoins ?? 0;
      final useCoins = await showFreeAttemptsExhaustedDialog(
        context,
        featureName: t('group_expense_feature_label'),
        coinCost: session.groupExpenseCoinCost,
        currentCoins: coins,
      );
      if (useCoins != true) return;
      _showAddEditSheet(useCoins: true);
      return;
    }
    _showAddEditSheet();
  }

  // Convert an amountInr value into the selected display currency.
  String _fmtInr(num amountInr) {
    final target = selectedCurrency.toUpperCase();
    if (target != 'INR' &&
        !(currencyData?.canConvert('INR', target) ?? false)) {
      return '₹${amountInr.toStringAsFixed(2)}';
    }
    final converted =
        currencyData?.convert(amountInr, 'INR', target) ??
            amountInr.toDouble();
    final sym = currencyData?.symbolFor(target) ?? '₹';
    return '$sym${converted.toStringAsFixed(2)}';
  }

  List<dynamic> get _activeMembers =>
      _members.where((m) => m['leftAt'] == null).toList();

  // Currency locked to first expense's currency (null = no expenses yet → free to choose)
  String? get _groupCurrency {
    for (final e in _expenses) {
      final c = e['currency']?.toString();
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  List<dynamic> get _filtered {
    var list = _expenses.where((e) {
      // tab filter
      if (_filter == 'mine') {
        final addedBy = _resolveEmail(e['addedBy']).toLowerCase();
        if (addedBy != widget.userEmail.toLowerCase()) return false;
      } else if (_filter == 'unsettled') {
        final split = List<dynamic>.from(e['split'] ?? []);
        final hasPending = split.any((s) {
          final email = _resolveEmail(s['user']).toLowerCase();
          return email == widget.userEmail.toLowerCase() && s['settled'] != true;
        });
        if (!hasPending) return false;
      }
      // search
      if (_searchQuery.isNotEmpty) {
        final desc = (e['description'] ?? '').toString().toLowerCase();
        final by = _resolveEmail(e['addedBy']).toLowerCase();
        if (!desc.contains(_searchQuery.toLowerCase()) &&
            !by.contains(_searchQuery.toLowerCase())) return false;
      }
      // date range
      if (_dateFrom != null || _dateTo != null) {
        final raw = e['createdAt'] ?? e['date'];
        if (raw == null) return false;
        try {
          final d = DateTime.parse(raw.toString()).toLocal();
          if (_dateFrom != null && d.isBefore(_dateFrom!)) return false;
          if (_dateTo != null && d.isAfter(_dateTo!.add(const Duration(days: 1)))) return false;
        } catch (_) {
          return false;
        }
      }
      return true;
    }).toList();
    return list;
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res =
          await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final groups =
            List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final group = groups.firstWhere(
          (g) => g['_id'].toString() == widget.groupId,
          orElse: () => <String, dynamic>{},
        );
        if (group.isNotEmpty && mounted) {
          setState(() {
            _expenses = List<dynamic>.from(group['expenses'] ?? []);
            _members = List<dynamic>.from(group['members'] ?? []);
            _memberPayments = List<dynamic>.from(group['memberPayments'] ?? []);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showReceiptDialog() {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: tricolorBorderBox(
          radius: 20,
          child: Container(
            color: AppThemeColors.cardBg(context),
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxWidth: 320),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.picture_as_pdf_rounded,
                      color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Text(t('group_report_label'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.email_outlined),
                    label: Text(t('send_to_my_email_label')),
                    onPressed: () {
                      Navigator.pop(context);
                      _requestReceipt('email');
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeColors.cardBg(context),
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(t('download_pdf_label')),
                    onPressed: () {
                      Navigator.pop(context);
                      _requestReceipt('download');
                    },
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppThemeColors.cardBg(context),
                      foregroundColor: const Color(0xFF2E7D32),
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.share_rounded),
                    label: Text(t('share_pdf_label')),
                    onPressed: () {
                      Navigator.pop(context);
                      _requestReceipt('share');
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestReceipt(String action) async {
    final t = AppLocalizations.of(context).t;
    setState(() => _loading = true);
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/receipt',
      body: {'action': action, 'email': widget.userEmail},
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      if (action == 'download') {
        try {
          final tempDir = await getTemporaryDirectory();
          final file = File('${tempDir.path}/group-receipt-${widget.groupId}.pdf');
          await file.writeAsBytes(res.bodyBytes);
          await OpenFile.open(file.path);
        } catch (e) {
          _showError('${t('could_not_open_pdf_message')}: $e');
        }
      } else if (action == 'share') {
        final ok = await shareBytesFile(
          bytes: res.bodyBytes,
          filename: 'group-receipt-${widget.groupId}.pdf',
          subject: '${widget.groupTitle} - Group Summary',
          mimeType: 'application/pdf',
        );
        if (!ok) _showError(t('could_not_share_pdf_message'));
      } else {
        _showSnack(t('report_sent_to_email_message'), success: true);
      }
    } else {
      _showError(jsonDecode(res.body)['error'] ?? t('failed_to_generate_report_message'));
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: const Color(0xFF2E7D32),
                onPrimary: Colors.white,
              ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
    }
  }

  Future<void> _deleteExpense(String expenseId) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: tricolorBorderBox(
          radius: 20,
          child: Container(
            color: AppThemeColors.cardBg(context),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.delete_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(t('delete_expense_title'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                ]),
                const SizedBox(height: 12),
                Text(t('confirm_delete_expense_message'),
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Text(t('action_cannot_be_undone_message'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(t('cancel'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('delete'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    final res = await ApiClient.delete(
        '/api/group-transactions/${widget.groupId}/expenses/$expenseId');
    if (!mounted) return;
    if (res.statusCode == 200) {
      _showSnack(t('expense_deleted_message'), success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      _showError(jsonDecode(res.body)['error'] ?? t('failed_to_delete_expense_message'));
    }
  }

  Future<void> _settleExpense(String expenseId) async {
    final t = AppLocalizations.of(context).t;
    setState(() => _loading = true);
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/expenses/$expenseId/settle',
      body: {'memberEmails': [widget.userEmail]},
    );
    if (!mounted) return;
    if (res.statusCode == 200) {
      _showSnack(t('your_share_settled_message'), success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      _showError(jsonDecode(res.body)['error'] ?? t('failed_to_settle_message'));
    }
  }

  // Resolves a split's user field to an email.
  // The server returns split.user as a raw ObjectId string.
  // The members list stores each member with _id == user's ObjectId (see view_group_transactions_page pattern).
  String _resolveEmail(dynamic userField) {
    final direct = emailOf(userField);
    if (direct.contains('@')) return direct;

    for (final m in _members) {
      // Primary: member sub-doc _id IS the user ObjectId
      final memberId = (m['_id'] ?? '').toString();
      if (memberId.isNotEmpty && memberId == direct) {
        final email = (m['email'] ?? '').toString();
        if (email.contains('@')) return email;
      }
      // Fallback: member has a separate user field
      final mUser = m['user'];
      final mId = mUser is Map
          ? (mUser['_id'] ?? mUser['id'] ?? '').toString()
          : (mUser ?? '').toString();
      if (mId.isNotEmpty && mId == direct) {
        final email = (m['email'] ?? emailOf(mUser)).toString();
        if (email.contains('@')) return email;
      }
    }
    return direct;
  }

  String _currencySymbol(String? c) {
    final code = (c ?? 'INR').toUpperCase();
    for (final cur in kGroupExpenseCurrencies) {
      if (cur['code'] == code) return cur['symbol']!;
    }
    return code;
  }

  void _showError(String raw) {
    final t = AppLocalizations.of(context).t;
    String msg = raw;
    if (raw.contains('Cannot include members who have left')) {
      msg = t('members_left_cannot_include_message');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: success ? const Color(0xFF2E7D32) : Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
      ),
    );
  }

  void _showAddEditSheet({Map<String, dynamic>? expense, bool useCoins = false}) {
    final lockedCurrency = _groupCurrency;
    final activeMembers = _activeMembers;
    final allEmails = activeMembers
        .map((m) =>
            m['email'] != null ? m['email'].toString() : emailOf(m['user']))
        .where((e) => e.isNotEmpty && e != '-')
        .toList();

    final Set<String> selectedEmails;
    int skippedLeftCount = 0;
    if (expense != null && expense['split'] != null) {
      final splitEmails = {
        for (final s in (expense['split'] as List)) _resolveEmail(s['user'])
      }.where((e) => e != '-').toSet();
      final leftEmails =
          splitEmails.where((e) => !allEmails.contains(e)).toSet();
      skippedLeftCount = leftEmails.length;
      selectedEmails =
          splitEmails.where((e) => allEmails.contains(e)).toSet();
    } else {
      selectedEmails = Set<String>.from(allEmails);
    }

    final Map<String, String> initialSplitAmounts = {};
    if (expense != null && expense['split'] != null) {
      for (final s in (expense['split'] as List)) {
        final email = _resolveEmail(s['user']);
        if (allEmails.contains(email)) {
          initialSplitAmounts[email] = (s['amount'] ?? '').toString();
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddExpenseSheet(
        allEmails: allEmails,
        lockedCurrency: lockedCurrency,
        expense: expense,
        skippedLeftCount: skippedLeftCount,
        initialSelectedEmails: selectedEmails,
        initialSplitAmounts: initialSplitAmounts,
        currentUserEmail: widget.userEmail,
        onSubmit: (desc, amount, currency, splitType, selectedEmails, split, category, addedBy) {
          _doExpenseSubmit(
            expense: expense,
            desc: desc,
            amount: amount,
            currency: currency,
            splitType: splitType,
            selectedEmails: selectedEmails,
            split: split,
            category: category,
            addedBy: addedBy,
            useCoins: useCoins,
          );
        },
      ),
    );
  }

  Future<void> _doExpenseSubmit({
    required Map<String, dynamic>? expense,
    required String desc,
    required double amount,
    required String currency,
    required String splitType,
    required List<String> selectedEmails,
    required List<Map<String, dynamic>> split,
    required String category,
    required String addedBy,
    bool useCoins = false,
  }) async {
    setState(() => _loading = true);
    if (expense == null) {
      final expenseBody = <String, dynamic>{
        'description': desc,
        'amount': amount,
        'currency': currency,
        'splitType': splitType,
        'split': split,
        'selectedMembers': selectedEmails,
        'category': category,
        'addedBy': addedBy,
        if (useCoins) 'useCoins': true,
      };
      final res = await ApiClient.post(
        '/api/group-transactions/${widget.groupId}/add-expense',
        body: expenseBody,
      );
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      if (res.statusCode == 200 || res.statusCode == 201) {
        _showSnack(t('expense_added_message'), success: true);
        _refresh();
      } else {
        setState(() => _loading = false);
        final exceeded = parseBudgetExceeded(res.body);
        if (exceeded != null) {
          final proceed = await showBudgetExceededSheet(context, exceeded);
          if (!mounted) return;
          if (proceed) {
            expenseBody['force'] = true;
            setState(() => _loading = true);
            final res2 = await ApiClient.post(
              '/api/group-transactions/${widget.groupId}/add-expense',
              body: expenseBody,
            );
            if (!mounted) return;
            if (res2.statusCode == 200 || res2.statusCode == 201) {
              _showSnack(t('expense_added_message'), success: true);
              _refresh();
            } else {
              setState(() => _loading = false);
              _showError(jsonDecode(res2.body)['error'] ?? t('failed_to_add_expense_message'));
            }
          }
          return;
        }
        _showError(jsonDecode(res.body)['error'] ?? jsonDecode(res.body)['message'] ?? t('failed_to_add_expense_message'));
      }
    } else {
      final res = await ApiClient.put(
        '/api/group-transactions/${widget.groupId}/expenses/${expense['_id']}',
        body: {
          'description': desc,
          'amount': amount,
          'currency': currency,
          'splitType': splitType,
          'split': split,
          'selectedMembers': selectedEmails,
          'category': category,
        },
      );
      if (!mounted) return;
      final t = AppLocalizations.of(context).t;
      if (res.statusCode == 200) {
        _showSnack(t('expense_updated_message'), success: true);
        _refresh();
      } else {
        setState(() => _loading = false);
        _showError(jsonDecode(res.body)['error'] ?? t('failed_to_update_expense_message'));
      }
    }
  }

  Future<void> _settleMembers(String expenseId, List<String> emails) async {
    setState(() => _loading = true);
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/expenses/$expenseId/settle',
      body: {'memberEmails': emails},
    );
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    if (res.statusCode == 200) {
      _showSnack(t('settled_successfully_message'), success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      _showError(jsonDecode(res.body)['error'] ?? t('failed_to_settle_message'));
    }
  }

  void _showSettleMembersDialog(Map<String, dynamic> expense) {
    final t = AppLocalizations.of(context).t;
    final expenseId = expense['_id']?.toString() ?? '';
    final split = List<dynamic>.from(expense['split'] ?? []);
    final unsettled = split
        .where((s) => s['settled'] != true)
        .map((s) => _resolveEmail(s['user']))
        .where((e) => e.contains('@'))
        .toList();

    if (unsettled.isEmpty) {
      _showSnack(t('all_splits_already_settled_message'), success: true);
      return;
    }

    final selected = <String>{};

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: Colors.transparent,
          child: tricolorBorderBox(
            radius: 20,
            child: Container(
              color: AppThemeColors.cardBg(context),
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2E7D32),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t('settle_members_title_message')
                                .replaceFirst('{description}', expense['description']?.toString() ?? ''),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () =>
                              setDlg(() => selected.addAll(unsettled)),
                          child: Text(t('select_all_label')),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          onPressed: () =>
                              setDlg(() => selected.clear()),
                          child: Text(t('clear')),
                        ),
                        const Spacer(),
                        // Settle All for this expense — one tap
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _settleMembers(expenseId, unsettled);
                          },
                          icon: const Icon(Icons.done_all_rounded,
                              size: 15),
                          label: Text(t('settle_all_label')),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: unsettled.length,
                      itemBuilder: (_, i) {
                        final email = unsettled[i];
                        final isSelected = selected.contains(email);
                        return InkWell(
                          onTap: () => setDlg(() {
                            if (isSelected) {
                              selected.remove(email);
                            } else {
                              selected.add(email);
                            }
                          }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.green[50]
                                  : Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.green[400]!
                                    : Colors.orange[200]!,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  color: isSelected
                                      ? Colors.green[700]
                                      : Colors.orange[400],
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(email,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(t('cancel')),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                            ),
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _settleMembers(
                                        expenseId, selected.toList());
                                  },
                            child: Text(t('settle_label')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSplitsDialog(Map<String, dynamic> expense) {
    final t = AppLocalizations.of(context).t;
    final split = List<dynamic>.from(expense['split'] ?? []);
    final sym = _currencySymbol(expense['currency']);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: tricolorBorderBox(
          radius: 20,
          child: Container(
            color: AppThemeColors.cardBg(context),
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E7D32),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          color: Colors.white),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('splits_title_message')
                              .replaceFirst('{description}', expense['description']?.toString() ?? ''),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                // Splits list
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: split.length,
                    itemBuilder: (_, i) {
                      final s = split[i] as Map<String, dynamic>;
                      final email = _resolveEmail(s['user']);
                      final splitAmtInr =
                          (s['amountInr'] ?? s['amount'] ?? 0) as num;
                      final amt = (s['amount'] ?? 0).toString();
                      final settled = s['settled'] == true;
                      final settledBy =
                          s['settledBy']?.toString();
                      final settledAt = s['settledAt'] != null
                          ? fmtDateTime(s['settledAt'])
                          : null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: settled
                              ? Colors.green[50]
                              : Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: settled
                                ? Colors.green[200]!
                                : Colors.orange[200]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  settled ? Colors.green : Colors.orange,
                              child: Icon(
                                  settled
                                      ? Icons.check
                                      : Icons.schedule,
                                  color: Colors.white,
                                  size: 14),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(email,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _fmtInr(splitAmtInr),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: settled
                                        ? Colors.green[700]
                                        : Colors.orange[800],
                                  ),
                                ),
                                if ((expense['currency']?.toString().toUpperCase() ?? 'INR') !=
                                    selectedCurrency.toUpperCase())
                                  Text(
                                    '$sym$amt',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey[500]),
                                  ),
                                Text(
                                  settled ? t('settled_label') : t('pending_label'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: settled
                                        ? Colors.green[600]
                                        : Colors.orange[700],
                                  ),
                                ),
                                if (settled && settledBy != null)
                                  Text(
                                    t('settled_by_label')
                                        .replaceFirst('{name}', settledBy.split('@').first),
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.green[400]),
                                  ),
                                if (settled && settledAt != null)
                                  Text(
                                    settledAt,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey[400]),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('close')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final filtered = _filtered;
    double myPendingInr = 0;
    for (final e in _expenses) {
      for (final s in (e['split'] ?? [])) {
        final email = _resolveEmail(s['user']).toLowerCase();
        if (email == widget.userEmail.toLowerCase() && s['settled'] != true) {
          myPendingInr += ((s['amountInr'] ?? s['amount'] ?? 0) as num).toDouble();
        }
      }
    }
    // Subtract payments the current user has already made
    for (final p in _memberPayments) {
      if ((p['from'] as String? ?? '').toLowerCase() == widget.userEmail.toLowerCase()) {
        myPendingInr = (myPendingInr - ((p['amount'] ?? 0) as num).toDouble())
            .clamp(0.0, double.infinity);
      }
    }

    final groupCur = _groupCurrency;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('expenses_title_label'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.groupTitle,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedCurrency,
                dropdownColor: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                style: TextStyle(
                    color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w600),
                iconEnabledColor: Colors.white,
                selectedItemBuilder: (_) =>
                    (currencyData?.currencies ?? _kFallbackCurrencies)
                        .map((c) => Center(
                              child: Text(
                                '${c['symbol']} ${c['code']}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                            ))
                        .toList(),
                items: (currencyData?.currencies ?? _kFallbackCurrencies)
                    .map((c) => DropdownMenuItem(
                          value: c['code'],
                          child: Text('${c['symbol']} ${c['code']}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setCurrency(v);
                },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: t('group_report_label'),
            onPressed: _showReceiptDialog,
          ),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: const Color(0xFF2E7D32),
            padding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(
                    gradient: AppColors.tricolorGradient,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statPill(
                          t('expenses_count_label').replaceFirst('{count}', '${_expenses.length}'),
                          Colors.white),
                      const SizedBox(width: 8),
                      _statPill(
                          t('amount_pending_label').replaceFirst('{amount}', _fmtInr(myPendingInr)),
                          Colors.orange[200]!),
                      if (groupCur != null) ...[
                        const SizedBox(width: 8),
                        _statPill(t('native_currency_label').replaceFirst('{currency}', groupCur), Colors.white70),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Balance summary
          _buildBalanceSummary(),

          // Filter chips + search + date
          Container(
            color: AppThemeColors.cardBg(context),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                // Filters row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(t('filter_all_label'), 'all'),
                      const SizedBox(width: 8),
                      _filterChip(t('filter_added_by_me_label'), 'mine'),
                      const SizedBox(width: 8),
                      _filterChip(t('filter_my_pending_label'), 'unsettled'),
                      const SizedBox(width: 8),
                      // Date range button
                      GestureDetector(
                        onTap: _pickDateRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_dateFrom != null || _dateTo != null)
                                ? const Color(0xFF2E7D32)
                                : AppThemeColors.surfaceBg(context),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: (_dateFrom != null || _dateTo != null)
                                  ? const Color(0xFF2E7D32)
                                  : AppThemeColors.border(context),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.date_range_rounded,
                                  size: 14,
                                  color: (_dateFrom != null || _dateTo != null)
                                      ? Colors.white
                                      : AppThemeColors.secondaryText(context)),
                              const SizedBox(width: 4),
                              Text(
                                (_dateFrom != null || _dateTo != null)
                                    ? '${_dateFrom != null ? "${_dateFrom!.day}/${_dateFrom!.month}" : "…"} – ${_dateTo != null ? "${_dateTo!.day}/${_dateTo!.month}" : "…"}'
                                    : t('date_label'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (_dateFrom != null || _dateTo != null)
                                      ? Colors.white
                                      : AppThemeColors.secondaryText(context),
                                ),
                              ),
                              if (_dateFrom != null || _dateTo != null) ...[
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => setState(
                                      () { _dateFrom = null; _dateTo = null; }),
                                  child: const Icon(Icons.close_rounded,
                                      size: 12, color: Colors.white),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Search bar
                AppSearchBar(
                  controller: _searchCtrl,
                  hintText: t('search_description_member_hint'),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  margin: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // Expense list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.cyan,
              child: filtered.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Center(
                        child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            color: AppThemeColors.mutedText(context), size: 64),
                        const SizedBox(height: 8),
                        Text(t('no_expenses_found_message'),
                            style:
                                TextStyle(color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF2E7D32)),
                          onPressed: _openAddExpense,
                          icon: const Icon(Icons.add,
                              color: Colors.white),
                          label: Text(t('add_first_expense_label'),
                              style:
                                  const TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e =
                          filtered[i] as Map<String, dynamic>;
                      final expenseId =
                          e['_id']?.toString() ?? '';
                      final desc = e['description'] ?? '-';
                      final amountInr =
                          (e['amountInr'] ?? e['amount'] ?? 0) as num;
                      final nativeAmt = (e['amount'] ?? 0).toString();
                      final nativeCur = (e['currency'] ?? 'INR').toString();
                      final nativeSym = _currencySymbol(nativeCur);
                      final expCategory = (e['category'] ?? 'other').toString();
                      final addedByEmail =
                          _resolveEmail(e['addedBy']);
                      final isMine =
                          addedByEmail.toLowerCase() ==
                              widget.userEmail.toLowerCase();
                      final canEdit = isMine || widget.isCreator;
                      final canDelete = isMine || widget.isCreator;

                      final split = List<dynamic>.from(
                          e['split'] ?? []);
                      Map<String, dynamic>? mySplit;
                      for (final s in split) {
                        final sEmail =
                            _resolveEmail(s['user']).toLowerCase();
                        if (sEmail ==
                            widget.userEmail.toLowerCase()) {
                          mySplit = s as Map<String, dynamic>;
                          break;
                        }
                      }
                      final myAmtInr = mySplit != null
                          ? (mySplit['amountInr'] ?? mySplit['amount'] ?? 0) as num
                          : null;
                      final mySettled =
                          mySplit?['settled'] == true;

                      return tricolorBorderBox(
                        margin:
                            const EdgeInsets.only(bottom: 14),
                        radius: 18,
                        child: Container(
                          color: kGroupExpenseCardColors[i % kGroupExpenseCardColors.length],
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                                0xFF2E7D32)
                                            .withValues(
                                                alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                          Icons.receipt_outlined,
                                          color:
                                              Color(0xFF2E7D32)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment
                                                .start,
                                        children: [
                                          Text(
                                            desc,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 15),
                                            overflow: TextOverflow
                                                .ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            t('by_email_label').replaceFirst('{email}', addedByEmail),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors
                                                    .grey[600]),
                                            overflow: TextOverflow
                                                .ellipsis,
                                          ),
                                          if (fmtDateTime(e['createdAt'] ?? e['date']).isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(Icons.access_time_rounded,
                                                    size: 11,
                                                    color: Colors.grey[400]),
                                                const SizedBox(width: 3),
                                                Flexible(
                                                  child: Text(
                                                    fmtDateTime(e['createdAt'] ?? e['date']),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors.grey[400]),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          if (mySplit !=
                                              null) ...[
                                            const SizedBox(
                                                height: 4),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    t('your_share_label').replaceFirst('{amount}', myAmtInr != null ? _fmtInr(myAmtInr) : ''),
                                                    overflow:
                                                        TextOverflow
                                                            .ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: mySettled
                                                          ? Colors.green[
                                                              700]
                                                          : Colors.orange[
                                                              800],
                                                      fontWeight:
                                                          FontWeight
                                                              .w600,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 6),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 6,
                                                      vertical: 1),
                                                  decoration:
                                                      BoxDecoration(
                                                    color: mySettled
                                                        ? Colors
                                                            .green[50]
                                                        : Colors
                                                            .orange[50],
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(
                                                                8),
                                                  ),
                                                  child: Text(
                                                    mySettled
                                                        ? t('settled_check_label')
                                                        : t('pending_label'),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: mySettled
                                                          ? Colors.green[
                                                              700]
                                                          : Colors.orange[
                                                              800],
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        // category badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          margin: const EdgeInsets.only(
                                              bottom: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32)
                                                .withValues(alpha: 0.08),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                categoryIcon(expCategory),
                                                size: 11,
                                                color: const Color(0xFF2E7D32),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                categoryLabel(expCategory, t),
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF2E7D32),
                                                    fontWeight:
                                                        FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // converted amount
                                        Text(
                                          _fmtInr(amountInr),
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF2E7D32),
                                          ),
                                        ),
                                        // native amount (only when different)
                                        if (nativeCur.toUpperCase() !=
                                            selectedCurrency
                                                .toUpperCase())
                                          Text(
                                            '$nativeSym$nativeAmt',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[500]),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              // Action row
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(
                                    left: 14,
                                    right: 14,
                                    bottom: 12),
                                child: Row(
                                  children: [
                                    if (mySplit != null && !mySettled) ...[
                                      if (widget.isCreator) ...[
                                        _actionBtn(
                                          t('settle_my_share_label'),
                                          Icons.check_circle_rounded,
                                          Colors.green,
                                          () => _settleExpense(expenseId),
                                        ),
                                        const SizedBox(width: 8),
                                      ] else ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: Colors.orange[50],
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: Colors.orange[200]!),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.info_outline_rounded,
                                                  size: 13,
                                                  color: Colors.orange[700]),
                                              const SizedBox(width: 4),
                                              Text(
                                                t('ask_creator_to_settle_message'),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.orange[700]),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                    ],
                                    if (canEdit) ...[
                                      _actionBtn(
                                        t('edit'),
                                        Icons.edit_rounded,
                                        const Color(0xFF1565C0),
                                        () => _showAddEditSheet(
                                            expense: e),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (canDelete) ...[
                                      _actionBtn(
                                        t('delete'),
                                        Icons.delete_rounded,
                                        Colors.red,
                                        () => _deleteExpense(
                                            expenseId),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (widget.isCreator) ...[
                                      _actionBtn(
                                        t('settle_members_label'),
                                        Icons.how_to_reg_rounded,
                                        const Color(0xFF00695C),
                                        () => _showSettleMembersDialog(e),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    _actionBtn(
                                      t('splits_count_label').replaceFirst('{count}', '${split.length}'),
                                      Icons.people_outline_rounded,
                                      Colors.grey,
                                      () => _showSplitsDialog(e),
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
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: AppColors.tricolorGradient,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(2),
        child: FloatingActionButton.extended(
          onPressed: _openAddExpense,
          backgroundColor: const Color(0xFF2E7D32),
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: Text(t('add_expense_label'),
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceSummary() {
    final t = AppLocalizations.of(context).t;
    // Compute per-member unsettled totals from expense splits
    final Map<String, double> pending = {};
    for (final e in _expenses) {
      for (final s in List<dynamic>.from(e['split'] ?? [])) {
        if (s['settled'] == true) continue;
        final email = _resolveEmail(s['user']);
        if (!email.contains('@')) continue;
        final amt =
            ((s['amountInr'] ?? s['amount'] ?? 0) as num).toDouble();
        pending[email] = (pending[email] ?? 0) + amt;
      }
    }
    // Subtract recorded peer-to-peer payments so settled debts disappear
    for (final p in _memberPayments) {
      final from = (p['from'] as String? ?? '').toLowerCase();
      final amt = ((p['amount'] ?? 0) as num).toDouble();
      if (pending.containsKey(from)) {
        pending[from] = (pending[from]! - amt).clamp(0.0, double.infinity);
      }
    }
    pending.removeWhere((_, v) => v < 0.01);
    if (pending.isEmpty) return const SizedBox.shrink();

    final sorted = pending.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      color: AppThemeColors.cardBg(context),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet_outlined,
                    size: 14, color: Color(0xFF2E7D32)),
                const SizedBox(width: 5),
                Text(t('pending_balances_label'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32))),
              ],
            ),
          ),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final email = sorted[i].key;
                final amt = sorted[i].value;
                final isMe =
                    email.toLowerCase() == widget.userEmail.toLowerCase();
                return Container(
                  width: 150,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.orange[50]
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isMe
                          ? Colors.orange[300]!
                          : Colors.grey[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        email.split('@').first,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700]),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _fmtInr(amt),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isMe
                                ? Colors.orange[800]
                                : Colors.red[700]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _statPill(String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: selected
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.tricolorGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            )
          : Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
    );
  }
}
