import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

const _tricolorGradient = LinearGradient(
  colors: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Widget _tricolorBorderBox({
  required Widget child,
  double radius = 18,
  double borderWidth = 2,
  EdgeInsetsGeometry? margin,
  List<BoxShadow>? shadow,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      gradient: _tricolorGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
    ),
    padding: EdgeInsets.all(borderWidth),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - borderWidth),
      child: child,
    ),
  );
}

// All supported currencies
const _kCurrencies = [
  {'code': 'INR', 'symbol': '₹', 'label': 'Indian Rupee'},
  {'code': 'USD', 'symbol': '\$', 'label': 'US Dollar'},
  {'code': 'EUR', 'symbol': '€', 'label': 'Euro'},
  {'code': 'GBP', 'symbol': '£', 'label': 'British Pound'},
  {'code': 'JPY', 'symbol': '¥', 'label': 'Japanese Yen'},
  {'code': 'CNY', 'symbol': '¥', 'label': 'Chinese Yuan'},
  {'code': 'CAD', 'symbol': '\$', 'label': 'Canadian Dollar'},
  {'code': 'AUD', 'symbol': '\$', 'label': 'Australian Dollar'},
  {'code': 'CHF', 'symbol': 'Fr', 'label': 'Swiss Franc'},
  {'code': 'RUB', 'symbol': '₽', 'label': 'Russian Ruble'},
];

class GroupExpensesPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final bool isCreator;
  final String userEmail;
  final List<dynamic> initialExpenses;
  final List<dynamic> initialMembers;
  final bool openAddExpense;

  const GroupExpensesPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.isCreator,
    required this.userEmail,
    required this.initialExpenses,
    required this.initialMembers,
    this.openAddExpense = false,
  });

  @override
  State<GroupExpensesPage> createState() => _GroupExpensesPageState();
}

class _GroupExpensesPageState extends State<GroupExpensesPage> {
  late List<dynamic> _expenses;
  late List<dynamic> _members;
  bool _loading = false;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _expenses = List<dynamic>.from(widget.initialExpenses);
    _members = List<dynamic>.from(widget.initialMembers);
    if (widget.openAddExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAddEditSheet());
    }
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
    if (_filter == 'mine') {
      return _expenses.where((e) {
        final addedBy = _emailOf(e['addedBy']).toLowerCase();
        return addedBy == widget.userEmail.toLowerCase();
      }).toList();
    }
    if (_filter == 'unsettled') {
      return _expenses.where((e) {
        final split = List<dynamic>.from(e['split'] ?? []);
        return split.any((s) {
          final email = _emailOf(s['user']).toLowerCase();
          return email == widget.userEmail.toLowerCase() &&
              s['settled'] != true;
        });
      }).toList();
    }
    return _expenses;
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
            _expenses =
                List<dynamic>.from(group['expenses'] ?? []);
            _members =
                List<dynamic>.from(group['members'] ?? []);
          });
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteExpense(String expenseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _tricolorBorderBox(
          radius: 20,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.delete_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text('Delete Expense',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                ]),
                const SizedBox(height: 12),
                const Text('Are you sure you want to delete this expense?',
                    style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Text('This action cannot be undone.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete',
                          style: TextStyle(color: Colors.white)),
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
      _showSnack('Expense deleted', success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      _showError(jsonDecode(res.body)['error'] ?? 'Failed to delete');
    }
  }

  Future<void> _settleExpense(String expenseId) async {
    setState(() => _loading = true);
    final res = await ApiClient.post(
        '/api/group-transactions/${widget.groupId}/expenses/$expenseId/settle');
    if (!mounted) return;
    if (res.statusCode == 200) {
      _showSnack('Your share settled!', success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      _showError(jsonDecode(res.body)['error'] ?? 'Failed to settle');
    }
  }

  String _currencySymbol(String? c) {
    final code = (c ?? 'INR').toUpperCase();
    for (final cur in _kCurrencies) {
      if (cur['code'] == code) return cur['symbol']!;
    }
    return code;
  }

  void _showError(String raw) {
    String msg = raw;
    if (raw.contains('Cannot include members who have left')) {
      msg = 'Some selected members have left this group and cannot be included. Deselect them before saving.';
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

  void _showAddEditSheet({Map<String, dynamic>? expense}) {
    final descCtrl =
        TextEditingController(text: expense?['description'] ?? '');
    final amtCtrl = TextEditingController(
        text: expense != null
            ? (expense['amount'] ?? '').toString()
            : '');

    // Currency: locked after first expense, or from existing expense
    final lockedCurrency = _groupCurrency;
    String currency = expense?['currency']?.toString() ??
        lockedCurrency ??
        'INR';
    String splitType = 'equal';

    final activeMembers = _activeMembers;
    final allEmails = activeMembers
        .map((m) => m['email'] != null
            ? m['email'].toString()
            : _emailOf(m['user']))
        .where((e) => e.isNotEmpty && e != '-')
        .toList();

    // When editing: only pre-select members who are still active
    final Set<String> selectedEmails;
    int skippedLeftCount = 0;
    if (expense != null && expense['split'] != null) {
      final splitEmails = {
        for (final s in (expense['split'] as List))
          _emailOf(s['user'])
      }.where((e) => e != '-').toSet();
      final leftEmails =
          splitEmails.where((e) => !allEmails.contains(e)).toSet();
      skippedLeftCount = leftEmails.length;
      selectedEmails =
          splitEmails.where((e) => allEmails.contains(e)).toSet();
    } else {
      selectedEmails = Set<String>.from(allEmails);
    }

    final splitCtrls = {
      for (final e in allEmails) e: TextEditingController()
    };

    if (expense != null && expense['split'] != null) {
      for (final s in (expense['split'] as List)) {
        final email = _emailOf(s['user']);
        if (splitCtrls.containsKey(email)) {
          splitCtrls[email]!.text = (s['amount'] ?? '').toString();
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 0,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tricolor stripe at top
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: const BoxDecoration(
                    gradient: _tricolorGradient,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: _tricolorGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            expense == null
                                ? Icons.add_rounded
                                : Icons.edit_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          expense == null ? 'Add Expense' : 'Edit Expense',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Left member info banner (when editing)
                    if (skippedLeftCount > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_rounded,
                                color: Colors.orange[700], size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$skippedLeftCount member(s) from this expense have left the group. Their balances are auto-settled and cannot be re-included here.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange[800]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Description
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(
                        hintText: 'Description (e.g. Dinner, Hotel)',
                        prefixIcon:
                            const Icon(Icons.description_outlined),
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Amount + Currency
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: amtCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            decoration: InputDecoration(
                              hintText: 'Amount',
                              prefixIcon: const Icon(
                                  Icons.currency_rupee_rounded),
                              filled: true,
                              fillColor: Colors.grey[100],
                              border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: lockedCurrency != null && expense == null
                              // Locked currency pill (not the first expense)
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2E7D32)
                                        .withValues(alpha: 0.08),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                        color: const Color(0xFF2E7D32)
                                            .withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.lock_rounded,
                                          size: 14,
                                          color: Color(0xFF2E7D32)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${_currencySymbol(lockedCurrency)} $lockedCurrency',
                                        style: const TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              // Free currency selector (first expense or editing)
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: currency,
                                      isExpanded: true,
                                      items: _kCurrencies
                                          .map((cur) =>
                                              DropdownMenuItem(
                                                value: cur['code'],
                                                child: Text(
                                                    '${cur['symbol']} ${cur['code']}'),
                                              ))
                                          .toList(),
                                      onChanged: (v) => setModal(
                                          () => currency = v ?? 'INR'),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),

                    // Lock notice
                    if (lockedCurrency != null && expense == null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            'Currency is fixed for this group ($lockedCurrency)',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── Member selection ───────────────────────────
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Split between',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setModal(() {
                            if (selectedEmails.length ==
                                allEmails.length) {
                              selectedEmails.clear();
                            } else {
                              selectedEmails
                                ..clear()
                                ..addAll(allEmails);
                            }
                          }),
                          child: Text(
                            selectedEmails.length == allEmails.length
                                ? 'Deselect all'
                                : 'Select all',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF2E7D32),
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...allEmails.map((email) {
                      final isSelected = selectedEmails.contains(email);
                      return GestureDetector(
                        onTap: () => setModal(() {
                          if (isSelected) {
                            selectedEmails.remove(email);
                          } else {
                            selectedEmails.add(email);
                          }
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF2E7D32)
                                    .withValues(alpha: 0.08)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF2E7D32)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey[400],
                                child: Text(
                                  email.isNotEmpty
                                      ? email[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(email,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: isSelected
                                            ? Colors.black87
                                            : Colors.grey[600]),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : Colors.grey[400],
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),

                    // ── Split type ──────────────────────────────────
                    const SizedBox(height: 12),
                    const Text('Split type',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _splitTypeChip('Equal split', 'equal',
                              splitType,
                              (v) => setModal(() => splitType = v)),
                          const SizedBox(width: 8),
                          _splitTypeChip('Custom split', 'custom',
                              splitType,
                              (v) => setModal(() => splitType = v)),
                        ],
                      ),
                    ),

                    if (splitType == 'custom') ...[
                      const SizedBox(height: 12),
                      Text(
                        'Amount for each selected member:',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      ...allEmails
                          .where((e) => selectedEmails.contains(e))
                          .map((email) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          const Color(0xFF2E7D32),
                                      child: Text(email[0].toUpperCase(),
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(email,
                                          style: const TextStyle(
                                              fontSize: 13),
                                          overflow:
                                              TextOverflow.ellipsis),
                                    ),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 80,
                                      child: TextField(
                                        controller: splitCtrls[email],
                                        keyboardType:
                                            const TextInputType
                                                .numberWithOptions(
                                                decimal: true),
                                        decoration: InputDecoration(
                                          hintText: '0.00',
                                          filled: true,
                                          fillColor: Colors.grey[100],
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8),
                                          border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: BorderSide.none),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ],
                    const SizedBox(height: 16),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: _tricolorGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          icon: Icon(
                              expense == null
                                  ? Icons.add_rounded
                                  : Icons.save_rounded,
                              color: Colors.white),
                          label: Text(
                            expense == null
                                ? 'Add Expense'
                                : 'Save Changes',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16),
                          ),
                          onPressed: () async {
                            final desc = descCtrl.text.trim();
                            final amount =
                                double.tryParse(amtCtrl.text.trim());
                            if (desc.isEmpty) {
                              _showError('Enter a description');
                              return;
                            }
                            if (amount == null || amount <= 0) {
                              _showError('Enter a valid amount');
                              return;
                            }
                            if (selectedEmails.isEmpty) {
                              _showError('Select at least one member');
                              return;
                            }

                            final effectiveCurrency =
                                (lockedCurrency != null && expense == null)
                                    ? lockedCurrency
                                    : currency;

                            final chosenEmails = selectedEmails.toList();

                            List<Map<String, dynamic>> split;
                            if (splitType == 'equal') {
                              split = chosenEmails
                                  .map((e) => <String, dynamic>{
                                        'user': e,
                                        'amount': null,
                                      })
                                  .toList();
                            } else {
                              split = [];
                              for (final email in chosenEmails) {
                                final amt = double.tryParse(
                                        splitCtrls[email]
                                                ?.text
                                                .trim() ??
                                            '') ??
                                    0;
                                split.add(
                                    {'user': email, 'amount': amt});
                              }
                              final total = split.fold(
                                  0.0,
                                  (s, m) =>
                                      s +
                                      ((m['amount'] ?? 0) as num)
                                          .toDouble());
                              if ((total - amount).abs() > 0.01) {
                                _showError(
                                    'Split total (${total.toStringAsFixed(2)}) must equal amount (${amount.toStringAsFixed(2)})');
                                return;
                              }
                            }

                            Navigator.pop(ctx);
                            setState(() => _loading = true);

                            if (expense == null) {
                              final res = await ApiClient.post(
                                '/api/group-transactions/${widget.groupId}/add-expense',
                                body: {
                                  'description': desc,
                                  'amount': amount,
                                  'currency': effectiveCurrency,
                                  'splitType': splitType,
                                  'split': split,
                                  'selectedMembers': chosenEmails,
                                },
                              );
                              if (!mounted) return;
                              if (res.statusCode == 200 ||
                                  res.statusCode == 201) {
                                _showSnack('Expense added!', success: true);
                                _refresh();
                              } else {
                                setState(() => _loading = false);
                                _showError(jsonDecode(res.body)['error'] ??
                                    'Failed to add expense');
                              }
                            } else {
                              final res = await ApiClient.put(
                                '/api/group-transactions/${widget.groupId}/expenses/${expense['_id']}',
                                body: {
                                  'description': desc,
                                  'amount': amount,
                                  'currency': effectiveCurrency,
                                  'splitType': splitType,
                                  'split': split,
                                  'selectedMembers': chosenEmails,
                                },
                              );
                              if (!mounted) return;
                              if (res.statusCode == 200) {
                                _showSnack('Expense updated!',
                                    success: true);
                                _refresh();
                              } else {
                                setState(() => _loading = false);
                                _showError(jsonDecode(res.body)['error'] ??
                                    'Failed to update expense');
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    ).whenComplete(() {
      descCtrl.dispose();
      amtCtrl.dispose();
      for (final c in splitCtrls.values) c.dispose();
    });
  }

  void _showSplitsDialog(Map<String, dynamic> expense) {
    final split = List<dynamic>.from(expense['split'] ?? []);
    final sym = _currencySymbol(expense['currency']);
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _tricolorBorderBox(
          radius: 20,
          child: Container(
            color: Colors.white,
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
                          'Splits: ${expense['description']}',
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
                      final email = _emailOf(s['user']);
                      final amt = (s['amount'] ?? 0).toString();
                      final settled = s['settled'] == true;
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
                                  '$sym$amt',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: settled
                                        ? Colors.green[700]
                                        : Colors.orange[800],
                                  ),
                                ),
                                Text(
                                  settled ? 'Settled' : 'Pending',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: settled
                                        ? Colors.green[600]
                                        : Colors.orange[700],
                                  ),
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
                      child: const Text('Close'),
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

  Widget _splitTypeChip(String label, String value, String selected,
      ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: isSelected
          ? Container(
              decoration: BoxDecoration(
                gradient: _tricolorGradient,
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    double myPending = 0;
    for (final e in _expenses) {
      for (final s in (e['split'] ?? [])) {
        final email = _emailOf(s['user']).toLowerCase();
        if (email == widget.userEmail.toLowerCase() &&
            s['settled'] != true) {
          myPending += ((s['amount'] ?? 0) as num).toDouble();
        }
      }
    }

    final groupCur = _groupCurrency;
    final pendingSym = _currencySymbol(groupCur);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Expenses',
                style: TextStyle(
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
                    gradient: _tricolorGradient,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statPill(
                          '${_expenses.length} Expenses', Colors.white),
                      const SizedBox(width: 8),
                      _statPill(
                          '$pendingSym${myPending.toStringAsFixed(0)} Pending',
                          Colors.orange[200]!),
                      if (groupCur != null) ...[
                        const SizedBox(width: 8),
                        _statPill('Currency: $groupCur', Colors.white70),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All', 'all'),
                  const SizedBox(width: 8),
                  _filterChip('Added by me', 'mine'),
                  const SizedBox(width: 8),
                  _filterChip('My Pending', 'unsettled'),
                ],
              ),
            ),
          ),

          // Expense list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            color: Colors.grey[300], size: 64),
                        const SizedBox(height: 8),
                        Text('No expenses found',
                            style:
                                TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF2E7D32)),
                          onPressed: () => _showAddEditSheet(),
                          icon: const Icon(Icons.add,
                              color: Colors.white),
                          label: const Text('Add First Expense',
                              style:
                                  TextStyle(color: Colors.white)),
                        ),
                      ],
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
                      final amount =
                          (e['amount'] ?? 0).toString();
                      final currency = e['currency'] ?? 'INR';
                      final sym = _currencySymbol(currency);
                      final addedByEmail =
                          _emailOf(e['addedBy']);
                      final isMine =
                          addedByEmail.toLowerCase() ==
                              widget.userEmail.toLowerCase();
                      final canEdit = isMine || widget.isCreator;
                      final canDelete = widget.isCreator;

                      final split = List<dynamic>.from(
                          e['split'] ?? []);
                      Map<String, dynamic>? mySplit;
                      for (final s in split) {
                        final sEmail =
                            _emailOf(s['user']).toLowerCase();
                        if (sEmail ==
                            widget.userEmail.toLowerCase()) {
                          mySplit = s as Map<String, dynamic>;
                          break;
                        }
                      }
                      final myAmt = mySplit != null
                          ? (mySplit['amount'] ?? 0).toString()
                          : null;
                      final mySettled =
                          mySplit?['settled'] == true;

                      return _tricolorBorderBox(
                        margin:
                            const EdgeInsets.only(bottom: 14),
                        radius: 18,
                        child: Container(
                          color: Colors.white,
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
                                            'by $addedByEmail',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors
                                                    .grey[600]),
                                            overflow: TextOverflow
                                                .ellipsis,
                                          ),
                                          if (mySplit !=
                                              null) ...[
                                            const SizedBox(
                                                height: 4),
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    'Your share: $sym$myAmt',
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
                                                        ? '✓ Settled'
                                                        : 'Pending',
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
                                    Text(
                                      '$sym$amount',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2E7D32),
                                      ),
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
                                    if (mySplit != null &&
                                        !mySettled) ...[
                                      _actionBtn(
                                        'Settle my share',
                                        Icons
                                            .check_circle_rounded,
                                        Colors.green,
                                        () => _settleExpense(
                                            expenseId),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (canEdit) ...[
                                      _actionBtn(
                                        'Edit',
                                        Icons.edit_rounded,
                                        const Color(0xFF1565C0),
                                        () => _showAddEditSheet(
                                            expense: e),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    if (canDelete) ...[
                                      _actionBtn(
                                        'Delete',
                                        Icons.delete_rounded,
                                        Colors.red,
                                        () => _deleteExpense(
                                            expenseId),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    _actionBtn(
                                      'Splits (${split.length})',
                                      Icons
                                          .people_outline_rounded,
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
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: _tricolorGradient,
          borderRadius: BorderRadius.circular(32),
        ),
        padding: const EdgeInsets.all(2),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddEditSheet(),
          backgroundColor: const Color(0xFF2E7D32),
          elevation: 0,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text('Add Expense',
              style: TextStyle(color: Colors.white)),
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
                gradient: _tricolorGradient,
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
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
    );
  }
}
