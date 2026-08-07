import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../utils/currency_helpers.dart';
import '../../l10n/app_localizations.dart';

class PersonalBudgetExpensesPage extends StatefulWidget {
  final String budgetId;
  final String budgetName;
  final String budgetCurrency;
  final bool readOnly;

  const PersonalBudgetExpensesPage({
    super.key,
    required this.budgetId,
    required this.budgetName,
    required this.budgetCurrency,
    this.readOnly = false,
  });

  @override
  State<PersonalBudgetExpensesPage> createState() => _PersonalBudgetExpensesPageState();
}

class _ExpenseGroup {
  final String label;
  final List<Map<String, dynamic>> items;
  _ExpenseGroup(this.label, this.items);
}

class _PersonalBudgetExpensesPageState extends State<PersonalBudgetExpensesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _byCategory = [];
  double _total = 0;
  double _limit = 0;
  bool _isEditable = false;
  String _viewCurrency = 'INR';
  String _searchQuery = '';
  String? _filterCategory;

  final _numFmt  = NumberFormat('#,##0.##', 'en_IN');
  final _dtFmt   = DateFormat('dd MMM yyyy, hh:mm a');
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _viewCurrency = widget.budgetCurrency;
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiClient.get('/api/personal-budget/${widget.budgetId}/expenses');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _expenses   = (data['expenses'] as List).cast<Map<String, dynamic>>();
        _byCategory = (data['byCategory'] as List).cast<Map<String, dynamic>>();
        _total      = (data['total'] as num?)?.toDouble() ?? 0;
        final b     = data['budget'] as Map<String, dynamic>;
        _limit      = (b['limit'] as num?)?.toDouble() ?? 0;
        _isEditable = (b['isEditable'] as bool?) ?? false;
        if (widget.readOnly) _isEditable = false;
      } else {
        _error = json.decode(resp.body)['error'] ?? 'Failed to load expenses.';
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(double v) {
    final converted = convertCurrency(v, widget.budgetCurrency, _viewCurrency);
    return '${currencySymbol(_viewCurrency)}${_numFmt.format(converted)}';
  }

  Color _progressColor(double pct) {
    if (pct >= 100) return Colors.red.shade600;
    if (pct >= 80)  return Colors.orange.shade600;
    return AppColors.cyan;
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _expenses;
    if (_filterCategory != null) {
      list = list.where((e) =>
          (e['category'] as String? ?? '').toLowerCase() ==
          _filterCategory!.toLowerCase()).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) {
        final desc = (e['description'] as String? ?? '').toLowerCase();
        final cat  = (e['category']    as String? ?? '').toLowerCase();
        return desc.contains(q) || cat.contains(q);
      }).toList();
    }
    return list;
  }

  List<_ExpenseGroup> get _grouped {
    final expenses = _filtered;
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final buckets  = <String, List<Map<String, dynamic>>>{};
    final ordering = <String>[];

    for (final e in expenses) {
      final raw  = e['date'] as String?;
      final date = raw != null ? DateTime.parse(raw).toLocal() : now;
      final day  = DateTime(date.year, date.month, date.day);
      final diff = today.difference(day).inDays;

      final label = diff == 0 ? 'Today'
          : diff == 1       ? 'Yesterday'
          : diff < 7        ? 'This Week'
          : diff < 30       ? 'This Month'
          : 'Earlier';

      if (!buckets.containsKey(label)) {
        buckets[label] = [];
        ordering.add(label);
      }
      buckets[label]!.add(e);
    }

    return ordering.map((k) => _ExpenseGroup(k, buckets[k]!)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _isEditable;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.waveSolid(context),
        foregroundColor: AppThemeColors.primaryText(context),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.budgetName,
              style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold)),
          Text(widget.readOnly ? AppLocalizations.of(context).t('expenses_read_only') : AppLocalizations.of(context).t('expenses_label'),
              style: TextStyle(fontSize: context.sp(12),
                  color: AppThemeColors.secondaryText(context))),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: DropdownButton<String>(
              value: _viewCurrency,
              underline: const SizedBox.shrink(),
              icon: Icon(Icons.currency_exchange_rounded, size: 18,
                  color: AppThemeColors.primaryText(context)),
              dropdownColor: AppThemeColors.cardBg(context),
              style: TextStyle(fontSize: context.sp(12),
                  color: AppThemeColors.primaryText(context)),
              items: kSupportedCurrencies.map((c) => DropdownMenuItem(
                value: c, child: Text('$c ${currencySymbol(c)}'),
              )).toList(),
              onChanged: (v) { if (v != null) setState(() => _viewCurrency = v); },
            ),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.cyan,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(AppLocalizations.of(context).t('add_expense'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () => _showExpenseDialog(null),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _error != null
              ? errorStateWidget(context, _error!, _load)
              : _buildBody(canEdit),
    );
  }

  Widget _buildBody(bool canEdit) {
    final pct   = _limit > 0 ? (_total / _limit) * 100 : 0.0;
    final color = _progressColor(pct);
    final left  = _limit - _total;
    final groups = _grouped;

    // Quick stats
    final count    = _expenses.length;
    final largest  = _expenses.isNotEmpty
        ? _expenses.map((e) => (e['amount'] as num?)?.toDouble() ?? 0).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final topCat   = _byCategory.isNotEmpty ? (_byCategory.first['category'] as String? ?? '-') : '-';

    // Categories for filter chips
    final categories = _byCategory.map((c) => c['category'] as String? ?? '').toSet().toList();

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Summary card ──────────────────────────────────────────
                tricolorBorder(
                  radius: 18,
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Spent', style: TextStyle(fontSize: context.sp(11),
                              color: AppThemeColors.secondaryText(context))),
                          Text(_fmt(_total), style: TextStyle(fontSize: context.sp(22),
                              fontWeight: FontWeight.bold, color: color)),
                        ]),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('Budget', style: TextStyle(fontSize: context.sp(11),
                              color: AppThemeColors.secondaryText(context))),
                          Text(_fmt(_limit), style: TextStyle(fontSize: context.sp(22),
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                        ]),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0.0, 1.0),
                          minHeight: 12,
                          backgroundColor: AppThemeColors.scaffoldBg(context),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${pct.toStringAsFixed(1)}% used',
                            style: TextStyle(fontSize: context.sp(11), color: color,
                                fontWeight: FontWeight.w600)),
                        Text(left >= 0 ? '${_fmt(left)} remaining'
                            : 'Over by ${_fmt(-left)}',
                            style: TextStyle(fontSize: context.sp(11),
                                color: left >= 0
                                    ? Colors.green.shade600 : Colors.red.shade600,
                                fontWeight: FontWeight.w600)),
                      ]),
                      if (_viewCurrency != widget.budgetCurrency) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Shown in $_viewCurrency (converted from ${widget.budgetCurrency})',
                          style: TextStyle(fontSize: context.sp(10),
                              color: AppThemeColors.secondaryText(context),
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ]),
                  ),
                ),

                // ── Quick stats row ───────────────────────────────────────
                if (count > 0) ...[
                  Row(children: [
                    _statTile(Icons.receipt_rounded, '$count',
                        'entries', AppColors.cyan),
                    const SizedBox(width: 10),
                    _statTile(Icons.arrow_upward_rounded, _fmt(largest),
                        'largest', Colors.red.shade400),
                    const SizedBox(width: 10),
                    _statTile(Icons.star_rounded, topCat,
                        'top category', Colors.amber.shade700),
                  ]),
                  const SizedBox(height: 14),
                ],

                // ── Category breakdown ────────────────────────────────────
                if (_byCategory.isNotEmpty) ...[
                  Text('By Category',
                      style: TextStyle(fontSize: context.sp(13),
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 8),
                  tricolorBorder(
                    radius: 14,
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: _byCategory.map((c) {
                          final amt    = (c['amount'] as num?)?.toDouble() ?? 0;
                          final catPct = _total > 0 ? (amt / _total) * 100 : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Column(children: [
                              Row(children: [
                                _categoryIcon(c['category'] as String? ?? ''),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(c['category'] as String? ?? '',
                                      style: TextStyle(fontSize: context.sp(13),
                                          color: AppThemeColors.primaryText(context))),
                                ),
                                Text(_fmt(amt), style: TextStyle(
                                    fontSize: context.sp(13),
                                    fontWeight: FontWeight.bold,
                                    color: AppThemeColors.primaryText(context))),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 36,
                                  child: Text('${catPct.toStringAsFixed(0)}%',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: context.sp(11),
                                          color: AppThemeColors.secondaryText(context))),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (catPct / 100).clamp(0.0, 1.0),
                                  minHeight: 5,
                                  backgroundColor: AppThemeColors.scaffoldBg(context),
                                  valueColor: AlwaysStoppedAnimation(AppColors.cyan),
                                ),
                              ),
                            ]),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],

                // ── Search bar ────────────────────────────────────────────
                tricolorBorder(
                  radius: 14,
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(fontSize: context.sp(14),
                        color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).t('search_expenses_hint'),
                      hintStyle: TextStyle(
                          color: AppThemeColors.secondaryText(context)),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: AppColors.cyan),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: AppColors.cyan),
                              onPressed: () => setState(
                                  () { _searchCtrl.clear(); _searchQuery = ''; }),
                            )
                          : null,
                      filled: true,
                      fillColor: AppThemeColors.cardBg(context),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
                const SizedBox(height: 10),

                // ── Category filter chips ─────────────────────────────────
                if (categories.isNotEmpty)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _filterChip('All', _filterCategory == null,
                            () => setState(() => _filterCategory = null)),
                        ...categories.map((cat) => _filterChip(
                              cat, _filterCategory == cat,
                              () => setState(() => _filterCategory =
                                  _filterCategory == cat ? null : cat),
                            )),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),

                // ── List header ───────────────────────────────────────────
                Row(children: [
                  Expanded(
                    child: Text(
                      _filtered.isEmpty
                          ? 'No expenses'
                          : 'Expenses (${_filtered.length}${_filtered.length != count ? ' of $count' : ''})',
                      style: TextStyle(fontSize: context.sp(13),
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context)),
                    ),
                  ),
                  if (widget.readOnly)
                    _badge(AppLocalizations.of(context).t('read_only_label'),
                        Colors.grey.withValues(alpha: 0.15), Colors.grey.shade600),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          ),

          // ── Grouped expense list ──────────────────────────────────────────
          if (_filtered.isEmpty && !_loading)
            SliverToBoxAdapter(child: _buildEmpty(canEdit))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    int idx = 0;
                    for (final group in groups) {
                      if (i == idx) return _groupHeader(group.label, group.items);
                      idx++;
                      for (final e in group.items) {
                        if (i == idx) return _buildExpenseCard(e, canEdit);
                        idx++;
                      }
                    }
                    return null;
                  },
                  childCount: groups.fold<int>(
                      0, (s, g) => s + 1 + g.items.length),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: tricolorBorder(
        radius: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.sp(12),
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                Text(label, style: TextStyle(fontSize: context.sp(10),
                    color: AppThemeColors.secondaryText(context))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan
                : AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.cyan : AppColors.cyan.withValues(alpha: 0.3),
            ),
          ),
          child: Text(label,
              style: TextStyle(
                fontSize: context.sp(12),
                color: selected ? Colors.white : AppThemeColors.primaryText(context),
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              )),
        ),
      ),
    );
  }

  Widget _groupHeader(String label, List<Map<String, dynamic>> items) {
    final groupTotal = items.fold<double>(
        0, (s, e) => s + ((e['amount'] as num?)?.toDouble() ?? 0));
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Row(children: [
        Text(label,
            style: TextStyle(
              fontSize: context.sp(12),
              fontWeight: FontWeight.bold,
              color: AppThemeColors.secondaryText(context),
              letterSpacing: 0.5,
            )),
        const Spacer(),
        Text(_fmt(groupTotal),
            style: TextStyle(fontSize: context.sp(12),
                color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _buildExpenseCard(Map<String, dynamic> e, bool canEdit) {
    final amount = (e['amount'] as num?)?.toDouble() ?? 0;
    final cat    = e['category'] as String? ?? '';
    final desc   = e['description'] as String? ?? '';
    final raw    = e['date'] as String?;
    final date   = raw != null ? DateTime.parse(raw).toLocal() : null;

    return tricolorBorder(
      radius: 14,
      margin: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          _categoryIcon(cat),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _badge(cat, AppColors.cyan.withValues(alpha: 0.12), AppColors.cyan),
              ]),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.sp(12),
                        color: AppThemeColors.secondaryText(context))),
              ],
              if (date != null) ...[
                const SizedBox(height: 2),
                Text(_dtFmt.format(date),
                    style: TextStyle(fontSize: context.sp(10),
                        color: AppThemeColors.secondaryText(context))),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          Text(_fmt(amount),
              style: TextStyle(fontSize: context.sp(15),
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          if (canEdit)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18,
                  color: AppThemeColors.secondaryText(context)),
              onSelected: (v) {
                if (v == 'edit')      _showExpenseDialog(e);
                if (v == 'duplicate') _showExpenseDialog(_duplicated(e));
                if (v == 'delete')    _deleteExpense(e['_id'] as String);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit',
                    child: Row(children: [
                      const Icon(Icons.edit_rounded, size: 16),
                      const SizedBox(width: 8), Text(AppLocalizations.of(context).t('edit')),
                    ])),
                PopupMenuItem(value: 'duplicate',
                    child: Row(children: [
                      const Icon(Icons.copy_rounded, size: 16),
                      const SizedBox(width: 8), Text(AppLocalizations.of(context).t('duplicate')),
                    ])),
                PopupMenuItem(value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(AppLocalizations.of(context).t('delete'), style: const TextStyle(color: Colors.red)),
                    ])),
              ],
            ),
        ]),
      ),
    );
  }

  Map<String, dynamic> _duplicated(Map<String, dynamic> e) {
    // Same amount/category/description but today's date — no _id so dialog treats as new
    return {
      'amount':      e['amount'],
      'category':    e['category'],
      'description': e['description'],
      'date':        DateTime.now().toIso8601String(),
    };
  }

  Widget _buildEmpty(bool canEdit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_rounded, size: context.sp(52),
              color: AppThemeColors.secondaryText(context)),
          const SizedBox(height: 14),
          Text(
            _searchQuery.isNotEmpty || _filterCategory != null
                ? AppLocalizations.of(context).t('no_matching_expenses')
                : AppLocalizations.of(context).t('no_expenses_yet'),
            style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.w600,
                color: AppThemeColors.secondaryText(context)),
          ),
          if (_searchQuery.isEmpty && _filterCategory == null && canEdit) ...[
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).t('tap_add_expense_hint'),
                style: TextStyle(fontSize: context.sp(12),
                    color: AppThemeColors.secondaryText(context))),
          ],
          if (_searchQuery.isNotEmpty || _filterCategory != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => setState(() {
                _searchCtrl.clear();
                _searchQuery = '';
                _filterCategory = null;
              }),
              child: Text(AppLocalizations.of(context).t('clear_filters'), style: const TextStyle(color: AppColors.cyan)),
            ),
          ],
        ]),
      ),
    );
  }

  // ─── Expense dialog ───────────────────────────────────────────────────────

  void _showExpenseDialog(Map<String, dynamic>? existing) {
    final isNew    = existing == null || existing['_id'] == null;
    final amtCtrl  = TextEditingController(
        text: existing != null ? (existing['amount'] as num).toString() : '');
    final descCtrl = TextEditingController(
        text: existing?['description'] as String? ?? '');
    String category = existing?['category'] as String? ?? kBudgetCategories.first;
    bool customCat  = !kBudgetCategories.contains(category);
    final customCatCtrl = TextEditingController(text: customCat ? category : '');
    DateTime date = existing?['date'] != null
        ? DateTime.parse(existing!['date'] as String).toLocal()
        : DateTime.now();
    TimeOfDay time = TimeOfDay.fromDateTime(date);
    bool saving = false;
    final df = DateFormat('dd MMM yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, sc) => Container(
            decoration: BoxDecoration(
              color: AppThemeColors.scaffoldBg(context),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: ListView(controller: sc, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(isNew ? AppLocalizations.of(context).t('add_expense') : AppLocalizations.of(context).t('edit_expense'),
                  style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 16),

              // Amount
              TextField(
                controller: amtCtrl,
                autofocus: isNew,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(fontSize: context.sp(14),
                    color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: 'Amount (${widget.budgetCurrency})',
                  prefixIcon: Icon(currencyIcon(widget.budgetCurrency),
                      color: AppColors.cyan, size: 20),
                  filled: true,
                  fillColor: AppThemeColors.cardBg(context),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),

              // Category chips
              Text('Category', style: TextStyle(fontSize: context.sp(12),
                  color: AppThemeColors.secondaryText(context))),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                ...kBudgetCategories.map((c) => GestureDetector(
                      onTap: () => setS(() { category = c; customCat = false; }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: (!customCat && category == c)
                              ? AppColors.cyan
                              : AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (!customCat && category == c)
                                ? AppColors.cyan
                                : AppColors.cyan.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(c,
                              style: TextStyle(
                                fontSize: context.sp(12),
                                color: (!customCat && category == c)
                                    ? Colors.white
                                    : AppThemeColors.primaryText(context),
                                fontWeight: (!customCat && category == c)
                                    ? FontWeight.bold : FontWeight.normal,
                              )),
                        ]),
                      ),
                    )),
                GestureDetector(
                  onTap: () => setS(() => customCat = true),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: customCat ? Colors.amber : AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: customCat
                            ? Colors.amber
                            : Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text('Custom…',
                        style: TextStyle(
                          fontSize: context.sp(12),
                          color: customCat
                              ? Colors.white
                              : AppThemeColors.primaryText(context),
                        )),
                  ),
                ),
              ]),
              if (customCat) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: customCatCtrl,
                  style: TextStyle(fontSize: context.sp(14),
                      color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: 'Custom category name',
                    filled: true,
                    fillColor: AppThemeColors.cardBg(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Description
              TextField(
                controller: descCtrl,
                maxLines: 2,
                style: TextStyle(fontSize: context.sp(14),
                    color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  labelText: 'Description / note (optional)',
                  prefixIcon: const Icon(Icons.notes_rounded,
                      color: AppColors.cyan, size: 20),
                  filled: true,
                  fillColor: AppThemeColors.cardBg(context),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 14),

              // Date + Time
              Row(children: [
                Expanded(child: tricolorBorder(
                  radius: 12,
                  child: GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx, initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (d != null) setS(() => date = DateTime(
                          d.year, d.month, d.day, time.hour, time.minute));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Date', style: TextStyle(fontSize: context.sp(11),
                            color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 14, color: AppColors.cyan),
                          const SizedBox(width: 6),
                          Text(df.format(date),
                              style: TextStyle(fontSize: context.sp(13),
                                  color: AppThemeColors.primaryText(context),
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ]),
                    ),
                  ),
                )),
                const SizedBox(width: 12),
                Expanded(child: tricolorBorder(
                  radius: 12,
                  child: GestureDetector(
                    onTap: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (t != null) setS(() {
                        time = t;
                        date = DateTime(date.year, date.month, date.day,
                            t.hour, t.minute);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Time', style: TextStyle(fontSize: context.sp(11),
                            color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.access_time_rounded,
                              size: 14, color: AppColors.cyan),
                          const SizedBox(width: 6),
                          Text(time.format(context),
                              style: TextStyle(fontSize: context.sp(13),
                                  color: AppThemeColors.primaryText(context),
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ]),
                    ),
                  ),
                )),
              ]),
              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    final amt = double.tryParse(amtCtrl.text.trim());
                    if (amt == null || amt <= 0) {
                      showSnack(context, 'Enter a valid amount.', isError: true);
                      return;
                    }
                    final cat = customCat
                        ? customCatCtrl.text.trim() : category;
                    if (cat.isEmpty) {
                      showSnack(context, 'Enter a category.', isError: true);
                      return;
                    }
                    setS(() => saving = true);
                    try {
                      final body = {
                        'amount':      amt,
                        'category':    cat,
                        'description': descCtrl.text.trim(),
                        'date':        date.toIso8601String(),
                      };
                      final expId = existing?['_id'] as String?;
                      final resp  = (isNew)
                          ? await ApiClient.post(
                              '/api/personal-budget/${widget.budgetId}/expenses',
                              body: body)
                          : await ApiClient.put(
                              '/api/personal-budget/${widget.budgetId}/expenses/$expId',
                              body: body);
                      if (!mounted) return;
                      if (resp.statusCode == 200 || resp.statusCode == 201) {
                        Navigator.pop(ctx);
                        showSnack(context,
                            AppLocalizations.of(context).t(isNew ? 'expense_added' : 'expense_updated'));
                        _load();
                      } else {
                        final err = json.decode(resp.body);
                        showSnack(context, err['error'] ?? 'Could not save.',
                            isError: true);
                      }
                    } catch (e) {
                      showSnack(context, 'Error: $e', isError: true);
                    } finally {
                      if (mounted) setS(() => saving = false);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(isNew ? AppLocalizations.of(context).t('add_expense') : AppLocalizations.of(context).t('save_changes'),
                          style: TextStyle(fontSize: context.sp(15),
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Future<void> _deleteExpense(String expenseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context).t('delete_expense')),
        content: Text(AppLocalizations.of(context).t('delete_budget_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).t('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final resp = await ApiClient.delete(
          '/api/personal-budget/${widget.budgetId}/expenses/$expenseId');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        showSnack(context, AppLocalizations.of(context).t('expense_deleted'));
        _load();
      } else {
        final err = json.decode(resp.body);
        showSnack(context, err['error'] ?? 'Could not delete.', isError: true);
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  IconData _catIconData(String cat) {
    switch (cat.toLowerCase()) {
      case 'food':          return Icons.restaurant_rounded;
      case 'groceries':     return Icons.shopping_basket_rounded;
      case 'shopping':      return Icons.shopping_bag_rounded;
      case 'entertainment': return Icons.movie_rounded;
      case 'fuel':          return Icons.local_gas_station_rounded;
      case 'travel':        return Icons.flight_rounded;
      case 'medical':       return Icons.local_hospital_rounded;
      case 'education':     return Icons.school_rounded;
      case 'rent':          return Icons.home_rounded;
      case 'bills':         return Icons.receipt_rounded;
      default:              return Icons.label_rounded;
    }
  }

  Widget _categoryIcon(String cat) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.cyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_catIconData(cat), color: AppColors.cyan, size: 20),
    );
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: context.sp(11), color: fg,
          fontWeight: FontWeight.w600)),
    );
  }
}
