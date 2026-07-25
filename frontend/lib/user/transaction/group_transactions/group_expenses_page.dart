import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/app_colors.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/budget_exceeded_sheet.dart';
import '../../../utils/display_currency_helper.dart';
import '../../../session.dart';
import '../../../widgets/stylish_dialog.dart';
import '../../../utils/share_utils.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

String _fmtDateTime(dynamic dt) {
  if (dt == null) return '';
  try {
    final d = dt is String ? DateTime.parse(dt).toLocal() : dt as DateTime;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year}  $h:$m $period';
  } catch (_) {
    return '';
  }
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

const _kCardColors = [
  Color(0xFFFFF4E6), Color(0xFFE8F5E9), Color(0xFFFCE4EC),
  Color(0xFFE3F2FD), Color(0xFFFFF9C4), Color(0xFFF3E5F5),
];

const _kCategories = [
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

IconData _categoryIcon(String? key) {
  final cat = _kCategories.firstWhere(
    (c) => c['key'] == key,
    orElse: () => _kCategories.last,
  );
  return cat['icon'] as IconData;
}

String _categoryLabel(String? key, String Function(String) t) {
  switch (key) {
    case 'food':
      return t('category_food_label');
    case 'transport':
      return t('category_transport_label');
    case 'accommodation':
      return t('category_stay_label');
    case 'entertainment':
      return t('category_fun_label');
    case 'shopping':
      return t('category_shopping_label');
    case 'utilities':
      return t('category_utilities_label');
    case 'medical':
      return t('category_medical_label');
    case 'education':
      return t('category_education_label');
    default:
      return t('other');
  }
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

// ── Add/Edit Expense Sheet ────────────────────────────────────────────────────
// Using a proper StatefulWidget (not StatefulBuilder) so the State lifecycle
// correctly unregisters InheritedWidget (MediaQuery, etc.) dependents on
// deactivate(), preventing the _dependents.isEmpty assertion crash on scroll.

class _AddExpenseSheet extends StatefulWidget {
  final List<String> allEmails;
  final String? lockedCurrency;
  final Map<String, dynamic>? expense;
  final int skippedLeftCount;
  final Set<String> initialSelectedEmails;
  final Map<String, String> initialSplitAmounts;
  final String currentUserEmail;
  final void Function(
    String desc,
    double amount,
    String currency,
    String splitType,
    List<String> selectedEmails,
    List<Map<String, dynamic>> split,
    String category,
    String addedBy,
  ) onSubmit;

  const _AddExpenseSheet({
    required this.allEmails,
    required this.lockedCurrency,
    required this.expense,
    required this.skippedLeftCount,
    required this.initialSelectedEmails,
    required this.initialSplitAmounts,
    required this.currentUserEmail,
    required this.onSubmit,
  });

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  late final TextEditingController descCtrl;
  late final TextEditingController amtCtrl;
  late final Map<String, TextEditingController> splitCtrls;
  late String currency;
  late String splitType;
  late Set<String> selectedEmails;
  late String category;
  late String addedBy;

  @override
  void initState() {
    super.initState();
    descCtrl =
        TextEditingController(text: widget.expense?['description'] ?? '');
    amtCtrl = TextEditingController(
        text: widget.expense != null
            ? (widget.expense!['amount'] ?? '').toString()
            : '');
    currency = widget.expense?['currency']?.toString() ??
        widget.lockedCurrency ??
        'INR';
    splitType = 'equal';
    category = widget.expense?['category']?.toString() ?? 'other';
    addedBy = widget.expense?['addedBy']?.toString().isNotEmpty == true
        ? widget.expense!['addedBy'].toString()
        : widget.currentUserEmail;
    selectedEmails = Set<String>.from(widget.initialSelectedEmails);
    splitCtrls = {
      for (final e in widget.allEmails)
        e: TextEditingController(text: widget.initialSplitAmounts[e] ?? '')
    };
    // Rebuild on every keystroke so the live remaining counter updates.
    amtCtrl.addListener(_rebuild);
    for (final c in splitCtrls.values) c.addListener(_rebuild);
  }

  void _rebuild() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    amtCtrl.removeListener(_rebuild);
    for (final c in splitCtrls.values) c.removeListener(_rebuild);
    descCtrl.dispose();
    amtCtrl.dispose();
    for (final c in splitCtrls.values) c.dispose();
    super.dispose();
  }

  String _sym(String? c) {
    final code = (c ?? 'INR').toUpperCase();
    for (final cur in _kCurrencies) {
      if (cur['code'] == code) return cur['symbol']!;
    }
    return code;
  }

  Widget _chip(String label, String value, String selected,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

  void _validationError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_rounded, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(msg,
                style: const TextStyle(fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: const Color(0xFFD32F2F),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(14),
      elevation: 6,
      duration: const Duration(seconds: 4),
    ));
  }

  void _handleSubmit() {
    final t = AppLocalizations.of(context).t;
    final desc = descCtrl.text.trim();
    final amount = double.tryParse(amtCtrl.text.trim());
    if (desc.isEmpty) {
      _validationError(t('enter_a_description_message'));
      return;
    }
    if (amount == null || amount <= 0) {
      _validationError(t('enter_a_valid_amount'));
      return;
    }
    if (selectedEmails.isEmpty) {
      _validationError(t('select_at_least_one_member_message'));
      return;
    }

    final lockedCurrency = widget.lockedCurrency;
    final expense = widget.expense;
    // Currency is always locked when editing; locked to group currency for new non-first.
    final effectiveCurrency = expense != null
        ? (expense['currency']?.toString() ?? currency)
        : (lockedCurrency ?? currency);
    final chosenEmails = selectedEmails.toList();

    List<Map<String, dynamic>> split;
    if (splitType == 'equal') {
      split = chosenEmails
          .map((e) => <String, dynamic>{'user': e, 'amount': null})
          .toList();
    } else {
      split = [];
      for (final email in chosenEmails) {
        final amt =
            double.tryParse(splitCtrls[email]?.text.trim() ?? '') ?? 0;
        split.add({'user': email, 'amount': amt});
      }
      final total = split.fold(
          0.0, (s, m) => s + ((m['amount'] ?? 0) as num).toDouble());
      if ((total - amount).abs() > 0.01) {
        _validationError(
            t('split_total_must_equal_amount_message').replaceFirst('{total}', total.toStringAsFixed(2)).replaceFirst('{amount}', amount.toStringAsFixed(2)));
        return;
      }
    }

    Navigator.pop(context);
    widget.onSubmit(
        desc, amount, effectiveCurrency, splitType, chosenEmails, split, category, addedBy);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final lockedCurrency = widget.lockedCurrency;
    final expense = widget.expense;
    final allEmails = widget.allEmails;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: const BoxDecoration(
                gradient: _tricolorGradient,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
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
                Expanded(
                  child: Text(
                    expense == null ? t('add_expense_label') : t('edit_expense_label'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 20, color: Colors.black54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (widget.skippedLeftCount > 0) ...[
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
                        t('members_left_group_balances_auto_settled_message').replaceFirst('{count}', '${widget.skippedLeftCount}'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                hintText: t('description_hint_dinner_hotel_message'),
                prefixIcon: const Icon(Icons.description_outlined),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),

            // Category picker
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final cat = _kCategories[i];
                  final selected = category == cat['key'];
                  return GestureDetector(
                    onTap: () => setState(() => category = cat['key'] as String),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2E7D32)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2E7D32)
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            cat['icon'] as IconData,
                            size: 14,
                            color: selected ? Colors.white : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _categoryLabel(cat['key'] as String, t),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: amtCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      hintText: t('amount_hint'),
                      prefixIcon:
                          const Icon(Icons.currency_rupee_rounded),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  // Locked when editing OR when group already has a currency.
                // Free dropdown only on the very first new expense.
                child: (expense != null || lockedCurrency != null)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32)
                                .withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFF2E7D32)
                                    .withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.lock_rounded,
                                  size: 14, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  () {
                                    final c = expense != null
                                        ? (expense['currency']?.toString() ?? currency)
                                        : lockedCurrency!;
                                    return '${_sym(c)} $c';
                                  }(),
                                  style: const TextStyle(
                                    color: Color(0xFF2E7D32),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currency,
                              isExpanded: true,
                              items: _kCurrencies
                                  .map((cur) => DropdownMenuItem(
                                        value: cur['code'],
                                        child: Text(
                                            '${cur['symbol']} ${cur['code']}'),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => currency = v ?? 'INR'),
                            ),
                          ),
                        ),
                ),
              ],
            ),

            if (expense != null || lockedCurrency != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      expense != null
                          ? t('currency_cannot_be_changed_editing_message')
                          : t('currency_fixed_for_group_message').replaceFirst('{currency}', '$lockedCurrency'),
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            // ── Added by picker ───────────────────────────────────
            Text(t('added_by_who_paid_label'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allEmails.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final email = allEmails[i];
                  final sel = addedBy == email;
                  return GestureDetector(
                    onTap: () => setState(() => addedBy = email),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.cyan : Colors.grey[100],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: sel ? AppColors.cyan : Colors.grey[300]!,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (sel)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                            ),
                          Text(
                            email == widget.currentUserEmail ? t('you_label') : email.split('@').first,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : Colors.grey[700],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Text(t('split_between_label'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    if (selectedEmails.length == allEmails.length) {
                      selectedEmails.clear();
                    } else {
                      selectedEmails
                        ..clear()
                        ..addAll(allEmails);
                    }
                  }),
                  child: Text(
                    selectedEmails.length == allEmails.length
                        ? t('deselect_all_label')
                        : t('select_all_label'),
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
                onTap: () => setState(() {
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
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
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
                          email.isNotEmpty ? email[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
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

            const SizedBox(height: 12),
            Text(t('split_type_label'),
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(t('equal_split_label'), 'equal', splitType,
                      (v) => setState(() => splitType = v)),
                  const SizedBox(width: 8),
                  _chip(t('custom_split_label'), 'custom', splitType,
                      (v) => setState(() => splitType = v)),
                ],
              ),
            ),

            if (splitType == 'custom') ...[
              const SizedBox(height: 12),
              // ── Live remaining bar ──────────────────────────────────
              Builder(builder: (_) {
                final total = double.tryParse(amtCtrl.text.trim()) ?? 0;
                final assigned = selectedEmails.fold(0.0, (sum, email) =>
                    sum + (double.tryParse(splitCtrls[email]?.text.trim() ?? '') ?? 0));
                final remaining = total - assigned;
                final exact = remaining.abs() < 0.01;
                final over = remaining < -0.01;
                final symStr = _sym(
                  (widget.lockedCurrency != null && widget.expense == null)
                      ? widget.lockedCurrency
                      : currency,
                );
                final barColor = exact
                    ? Colors.green[50]!
                    : over
                        ? Colors.red[50]!
                        : Colors.orange[50]!;
                final borderColor = exact
                    ? Colors.green[300]!
                    : over
                        ? Colors.red[300]!
                        : Colors.orange[300]!;
                final textColor = exact
                    ? Colors.green[700]!
                    : over
                        ? Colors.red[700]!
                        : Colors.orange[800]!;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${t('assigned_label')}: $symStr${assigned.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: FontWeight.w600),
                      ),
                      Text(
                        exact
                            ? '✓ ${t('balanced_label')}'
                            : over
                                ? '${t('over_by_label')} $symStr${(-remaining).toStringAsFixed(2)}'
                                : '${t('left_colon_label')} $symStr${remaining.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontSize: 12,
                            color: textColor,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Text(
                t('amount_for_each_selected_member_label'),
                style:
                    TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              ...allEmails
                  .where((e) => selectedEmails.contains(e))
                  .map((email) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFF2E7D32),
                              child: Text(email[0].toUpperCase(),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(email,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: splitCtrls[email],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                    expense == null ? t('add_expense_label') : t('save_changes_label'),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16),
                  ),
                  onPressed: _handleSubmit,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _GroupExpensesPageState extends State<GroupExpensesPage> {
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

  DisplayCurrencyData? _displayCurrencyData;
  String _selectedDisplayCurrency = 'INR';
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
    _loadDisplayCurrencies();
    _fetchDailyExpenseLimit();
    if (widget.openAddExpense) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAddExpense());
    }
  }

  Future<void> _fetchDailyExpenseLimit() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
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
    if (!session.isSubscribed) {
      await Future.wait([
        session.loadFreebieCounts(),
        _fetchDailyExpenseLimit(),
      ]);
    }
    if (!session.isSubscribed && _dailyExpenseUsed >= _dailyExpenseLimit) {
      final coins = session.lenDenCoins ?? 0;
      final useCoins = await showFreeAttemptsExhaustedDialog(
        context,
        featureName: t('group_expense_feature_label'),
        coinCost: 5,
        currentCoins: coins,
      );
      if (useCoins != true) return;
      _showAddEditSheet(useCoins: true);
      return;
    }
    _showAddEditSheet();
  }

  Future<void> _loadDisplayCurrencies() async {
    try {
      final data = await DisplayCurrencyHelper.load();
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = data;
        if (!data.currencies.any((c) => c['code'] == _selectedDisplayCurrency)) {
          _selectedDisplayCurrency = 'INR';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _displayCurrencyData = null;
        _selectedDisplayCurrency = 'INR';
      });
    }
  }

  // Convert an amountInr value into the selected display currency.
  String _fmtInr(num amountInr) {
    final target = _selectedDisplayCurrency.toUpperCase();
    if (target != 'INR' &&
        !(_displayCurrencyData?.canConvert('INR', target) ?? false)) {
      return '₹${amountInr.toStringAsFixed(2)}';
    }
    final converted =
        _displayCurrencyData?.convert(amountInr, 'INR', target) ??
            amountInr.toDouble();
    final sym = _displayCurrencyData?.symbolFor(target) ?? '₹';
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
        child: _tricolorBorderBox(
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
        child: _tricolorBorderBox(
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
    final direct = _emailOf(userField);
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
        final email = (m['email'] ?? _emailOf(mUser)).toString();
        if (email.contains('@')) return email;
      }
    }
    return direct;
  }

  String _currencySymbol(String? c) {
    final code = (c ?? 'INR').toUpperCase();
    for (final cur in _kCurrencies) {
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
            m['email'] != null ? m['email'].toString() : _emailOf(m['user']))
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
      builder: (_) => _AddExpenseSheet(
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
          child: _tricolorBorderBox(
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
        child: _tricolorBorderBox(
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
                          ? _fmtDateTime(s['settledAt'])
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
                                    _selectedDisplayCurrency.toUpperCase())
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
                value: _selectedDisplayCurrency,
                dropdownColor: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                style: TextStyle(
                    color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w600),
                iconEnabledColor: Colors.white,
                selectedItemBuilder: (_) =>
                    (_displayCurrencyData?.currencies ?? _kFallbackCurrencies)
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
                items: (_displayCurrencyData?.currencies ?? _kFallbackCurrencies)
                    .map((c) => DropdownMenuItem(
                          value: c['code'],
                          child: Text('${c['symbol']} ${c['code']}'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedDisplayCurrency = v);
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
                    gradient: _tricolorGradient,
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
                TextField(
                  decoration: InputDecoration(
                    hintText: t('search_description_member_hint'),
                    hintStyle:
                        TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () =>
                                setState(() => _searchQuery = ''),
                          )
                        : null,
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(context),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
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

                      return _tricolorBorderBox(
                        margin:
                            const EdgeInsets.only(bottom: 14),
                        radius: 18,
                        child: Container(
                          color: _kCardColors[i % _kCardColors.length],
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
                                          if (_fmtDateTime(e['createdAt'] ?? e['date']).isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Icon(Icons.access_time_rounded,
                                                    size: 11,
                                                    color: Colors.grey[400]),
                                                const SizedBox(width: 3),
                                                Flexible(
                                                  child: Text(
                                                    _fmtDateTime(e['createdAt'] ?? e['date']),
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
                                                _categoryIcon(expCategory),
                                                size: 11,
                                                color: const Color(0xFF2E7D32),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                _categoryLabel(expCategory, t),
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
                                            _selectedDisplayCurrency
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
          gradient: _tricolorGradient,
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
