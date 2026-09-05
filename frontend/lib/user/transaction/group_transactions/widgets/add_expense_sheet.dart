import 'package:flutter/material.dart';
import '../../../../widgets/app_colors.dart';
import '../../../../utils/theme_helper.dart';
import '../../../../l10n/app_localizations.dart';
import './group_expense_helpers.dart';
import '../../../../utils/transaction_constants.dart';

class AddExpenseSheet extends StatefulWidget {
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

  const AddExpenseSheet({
    super.key,
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
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
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

  String _sym(String? c) => txCurrencySymbol(c);

  Widget _chip(String label, String value, String selected,
      ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: isSelected
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.tricolorGradient,
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
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: AppThemeColors.primaryText(context),
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
                gradient: AppColors.tricolorGradient,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppColors.tricolorGradient,
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
                      color: AppThemeColors.surfaceBg(context),
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
                fillColor: AppThemeColors.surfaceBg(context),
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
                itemCount: kGroupExpenseCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final cat = kGroupExpenseCategories[i];
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
                            : AppThemeColors.surfaceBg(context),
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
                            categoryLabel(cat['key'] as String, t),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : AppThemeColors.primaryText(context),
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
                      fillColor: AppThemeColors.surfaceBg(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
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
                            color: AppThemeColors.surfaceBg(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: currency,
                              isExpanded: true,
                              items: kGroupExpenseCurrencies
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
                        color: sel ? AppColors.cyan : AppThemeColors.surfaceBg(context),
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
                              color: sel ? Colors.white : AppThemeColors.primaryText(context),
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
                        : AppThemeColors.surfaceBg(context),
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
                                  fillColor: AppThemeColors.surfaceBg(context),
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
                  gradient: AppColors.tricolorGradient,
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
