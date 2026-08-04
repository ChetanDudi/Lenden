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
import 'personal_budget_expenses_page.dart';

class PersonalBudgetHistoryPage extends StatefulWidget {
  const PersonalBudgetHistoryPage({super.key});

  @override
  State<PersonalBudgetHistoryPage> createState() => _PersonalBudgetHistoryPageState();
}

class _PersonalBudgetHistoryPageState extends State<PersonalBudgetHistoryPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _budgets = [];
  int _total = 0;
  bool _hasMore = false;
  int _skip = 3;

  // Search filters
  final _nameCtrl     = TextEditingController();
  String? _filterPeriod;
  String? _filterStatus;
  DateTime? _startFrom;
  DateTime? _startTo;
  bool _showFilters = false;
  // Quick result filter (client-side on loaded items)
  bool? _quickOverBudget; // null=all, true=over, false=under
  final Set<String> _expandedHistoryIds = {};

  final _fmt = NumberFormat('#,##0.##', 'en_IN');
  final _df  = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _fetch(reset: true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool reset = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = <String, String>{
        'limit': '3',
        'skip':  reset ? '0' : '$_skip',
        if (_nameCtrl.text.trim().isNotEmpty) 'name': _nameCtrl.text.trim(),
        if (_filterPeriod != null) 'period': _filterPeriod!,
        if (_filterStatus != null) 'status': _filterStatus!,
        if (_startFrom != null) 'startFrom': _startFrom!.toIso8601String(),
        if (_startTo   != null) 'startTo':   _startTo!.toIso8601String(),
      };
      final query = params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
      final resp  = await ApiClient.get('/api/personal-budget/history?$query');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data   = json.decode(resp.body) as Map<String, dynamic>;
        final list   = (data['budgets'] as List).cast<Map<String, dynamic>>();
        _total   = (data['total'] as num?)?.toInt() ?? 0;
        _hasMore = data['hasMore'] == true;
        if (reset) {
          _budgets = list;
          _skip    = list.length;
        } else {
          _budgets.addAll(list);
          _skip   += list.length;
        }
      } else {
        final err = json.decode(resp.body);
        _error = err['error'] ?? 'Failed to load history.';
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySearch() {
    setState(() { _skip = 3; _budgets = []; });
    _fetch(reset: true);
  }

  void _clearFilters() {
    _nameCtrl.clear();
    setState(() {
      _filterPeriod = null;
      _filterStatus = null;
      _startFrom    = null;
      _startTo      = null;
    });
    _fetch(reset: true);
  }

  String _fmt2(num? v, [String currency = 'INR']) =>
      '${currencySymbol(currency)}${_fmt.format(v ?? 0)}';

  List<Map<String, dynamic>> get _displayed {
    if (_quickOverBudget == null) return _budgets;
    return _budgets.where((b) {
      final pct = (b['percentSpent'] as num?)?.toDouble() ?? 0;
      return _quickOverBudget! ? pct > 100 : pct <= 100;
    }).toList();
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'completed': return Colors.green.shade600;
      case 'expired':   return Colors.orange.shade700;
      default:          return AppColors.cyan;
    }
  }

  Color _pctColor(double pct) {
    if (pct >= 100) return Colors.red.shade600;
    if (pct >= 80)  return Colors.orange.shade600;
    return Colors.green.shade600;
  }

  Color _colorFromBudget(String id) {
    const palette = [
      Color(0xFF4CAF50), Color(0xFF2196F3), Color(0xFF9C27B0),
      Color(0xFFFF9800), Color(0xFFE91E63), Color(0xFF00BCD4),
      Color(0xFFFF5722), Color(0xFF607D8B), Color(0xFF795548), Color(0xFF3F51B5),
    ];
    final hash = id.codeUnits.fold(0, (prev, el) => prev + el);
    return palette[hash % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.waveSolid(context),
        foregroundColor: AppThemeColors.primaryText(context),
        title: Text(AppLocalizations.of(context).t('budget_history'),
            style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list_rounded),
            tooltip: 'Filters',
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(children: [
              Expanded(
                child: tricolorBorder(
                  radius: 14,
                  child: TextField(
                    controller: _nameCtrl,
                    style: TextStyle(fontSize: context.sp(14),
                        color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).t('search_budget_hint'),
                      hintStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.cyan),
                      filled: true,
                      fillColor: AppThemeColors.cardBg(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _applySearch(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _applySearch,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                child: const Icon(Icons.search, color: Colors.white),
              ),
            ]),
          ),

          // Expandable filters
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: _showFilters ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: _buildFilters(),
            secondChild: const SizedBox.shrink(),
          ),

          // Stats banner + quick filters
          if (_budgets.isNotEmpty) ...[
            _buildStatsBanner(),
            // Quick result filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                _qChip('All', _quickOverBudget == null,
                    () => setState(() => _quickOverBudget = null)),
                const SizedBox(width: 8),
                _qChip('Under Budget', _quickOverBudget == false,
                    () => setState(() => _quickOverBudget =
                        _quickOverBudget == false ? null : false)),
                const SizedBox(width: 8),
                _qChip('Over Budget', _quickOverBudget == true,
                    () => setState(() => _quickOverBudget =
                        _quickOverBudget == true ? null : true),
                    color: Colors.red.shade400),
              ]),
            ),
          ],

          // Summary row
          if (_budgets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _quickOverBudget != null
                        ? 'Showing ${_displayed.length} of ${_budgets.length} loaded'
                        : 'Showing ${_budgets.length} of $_total',
                    style: TextStyle(fontSize: context.sp(11),
                        color: AppThemeColors.secondaryText(context)),
                  ),
                  if (_filterPeriod != null || _filterStatus != null ||
                      _startFrom != null || _startTo != null ||
                      _nameCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: _clearFilters,
                      child: Text(AppLocalizations.of(context).t('clear_filters'), style: TextStyle(
                          fontSize: context.sp(11), color: AppColors.cyan,
                          fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),

          // List
          Expanded(
            child: _loading && _budgets.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                : _error != null
                    ? errorStateWidget(context, _error!, () => _fetch(reset: true))
                    : _displayed.isEmpty
                        ? _buildEmpty()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                            itemCount: _displayed.length + (_hasMore && _quickOverBudget == null ? 1 : 0),
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              if (i == _displayed.length) return _buildLoadMore();
                              return _buildHistoryCard(_displayed[i]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBanner() {
    final under = _budgets.where(
        (b) => ((b['percentSpent'] as num?)?.toDouble() ?? 0) <= 100).length;
    final over  = _budgets.length - under;
    final avgPct = _budgets.isEmpty ? 0.0
        : _budgets.fold<double>(
                0, (s, b) => s + ((b['percentSpent'] as num?)?.toDouble() ?? 0).clamp(0, 200)) /
            _budgets.length;
    final complianceRate = _budgets.isEmpty ? 0
        : (under / _budgets.length * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: tricolorBorder(
        radius: 14,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            _statCell(Icons.check_circle_rounded,
                '$under', 'Under Budget', Colors.green.shade600),
            _vDivider(),
            _statCell(Icons.warning_rounded,
                '$over', 'Over Budget', Colors.red.shade400),
            _vDivider(),
            _statCell(Icons.bar_chart_rounded,
                '${avgPct.toStringAsFixed(0)}%', 'Avg Used', AppColors.cyan),
            _vDivider(),
            _statCell(Icons.shield_rounded,
                '$complianceRate%', 'Compliance', Colors.green.shade600),
          ]),
        ),
      ),
    );
  }

  Widget _statCell(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: context.sp(13),
            fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: context.sp(9),
            color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _vDivider() => Container(
        width: 1, height: 36,
        color: AppThemeColors.secondaryText(context).withValues(alpha: 0.15),
      );

  Widget _qChip(String label, bool active, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? AppColors.cyan;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? c : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? c : c.withValues(alpha: 0.35)),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: context.sp(12),
              color: active ? Colors.white : AppThemeColors.primaryText(context),
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
      ),
    );
  }

  Widget _buildFilters() {
    return tricolorBorder(
      radius: 16,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Filter by Period',
            style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [null, 'daily', 'weekly', 'monthly', 'yearly', 'custom']
            .map((p) => ChoiceChip(
                  label: Text(p == null ? 'All' : _periodLabel(p)),
                  selected: _filterPeriod == p,
                  selectedColor: AppColors.cyan,
                  labelStyle: TextStyle(
                      color: _filterPeriod == p ? Colors.white : AppThemeColors.primaryText(context),
                      fontSize: context.sp(12)),
                  onSelected: (_) => setState(() => _filterPeriod = p),
                ))
            .toList()),
        const SizedBox(height: 10),
        Text('Filter by Status',
            style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [null, 'completed', 'expired']
            .map((s) => ChoiceChip(
                  label: Text(s == null ? 'All' : _capitalize(s)),
                  selected: _filterStatus == s,
                  selectedColor: AppColors.cyan,
                  labelStyle: TextStyle(
                      color: _filterStatus == s ? Colors.white : AppThemeColors.primaryText(context),
                      fontSize: context.sp(12)),
                  onSelected: (_) => setState(() => _filterStatus = s),
                ))
            .toList()),
        const SizedBox(height: 10),
        Text('Date Range (Start Date)',
            style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _dateFilterTile('From', _startFrom, () async {
            final d = await showDatePicker(context: context,
                initialDate: _startFrom ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (d != null) setState(() => _startFrom = d);
          })),
          const SizedBox(width: 8),
          Expanded(child: _dateFilterTile('To', _startTo, () async {
            final d = await showDatePicker(context: context,
                initialDate: _startTo ?? DateTime.now(),
                firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (d != null) setState(() => _startTo = d);
          })),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _applySearch,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(AppLocalizations.of(context).t('apply_filters'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
      ),
    );
  }

  Widget _dateFilterTile(String label, DateTime? val, VoidCallback onTap) {
    return tricolorBorder(
      radius: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: AppThemeColors.scaffoldBg(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.calendar_month_rounded, size: 16, color: AppColors.cyan),
            const SizedBox(width: 6),
            Text(val != null ? _df.format(val) : label,
                style: TextStyle(fontSize: context.sp(12),
                    color: val != null ? AppThemeColors.primaryText(context) : AppThemeColors.secondaryText(context))),
          ]),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> b) {
    final pct      = (b['percentSpent'] as num?)?.toDouble() ?? 0;
    final spent    = (b['spentAmount'] as num?)?.toDouble() ?? 0;
    final limit    = (b['limit'] as num?)?.toDouble() ?? 0;
    final status   = b['status'] as String? ?? '';
    final currency = (b['currency'] as String?) ?? 'INR';
    final stColor  = _statusColor(status);
    final pctColor = _pctColor(pct);
    final period   = b['period'] as String? ?? '';
    final id       = b['_id'] as String;
    final expanded    = _expandedHistoryIds.contains(id);
    final budgetColor = _colorFromBudget(id);
    final s = b['startDate'] != null ? _df.format(DateTime.parse(b['startDate']).toLocal()) : '';
    final e = b['endDate']   != null ? _df.format(DateTime.parse(b['endDate']).toLocal()) : '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: budgetColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: budgetColor.withValues(alpha: 0.45), width: 2),
        boxShadow: [BoxShadow(color: budgetColor.withValues(alpha: 0.12),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Always visible: header ─────────────────────────────────────
          Row(children: [
            Expanded(
              child: Text(b['name'] ?? '',
                  style: TextStyle(fontSize: context.sp(14), fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
            ),
            _badge(_periodLabel(period), AppColors.cyan.withValues(alpha: 0.13), AppColors.cyan),
            const SizedBox(width: 6),
            _badge(_capitalize(status), stColor.withValues(alpha: 0.13), stColor),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: AppThemeColors.secondaryText(context)),
              onSelected: (v) {
                if (v == 'expenses') {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => PersonalBudgetExpensesPage(
                      budgetId: id, budgetName: b['name'] as String? ?? '',
                      budgetCurrency: currency, readOnly: true),
                  ));
                }
                if (v == 'delete') _confirmDeleteHistory(id);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'expenses', child: Row(children: [
                  const Icon(Icons.receipt_long_rounded, size: 16), const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).t('view_expenses')),
                ])),
                PopupMenuItem(value: 'delete', child: Row(children: [
                  const Icon(Icons.delete_rounded, size: 16, color: Colors.red), const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).t('delete'), style: const TextStyle(color: Colors.red)),
                ])),
              ],
            ),
          ]),

          // ── Always visible: amounts + progress ─────────────────────────
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Spent', style: TextStyle(fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context))),
              Text(_fmt2(spent, currency), style: TextStyle(fontSize: context.sp(16),
                  fontWeight: FontWeight.bold, color: pctColor)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Budget Limit', style: TextStyle(fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context))),
              Text(_fmt2(limit, currency), style: TextStyle(fontSize: context.sp(16),
                  fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            ]),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0), minHeight: 8,
              backgroundColor: AppThemeColors.scaffoldBg(context),
              valueColor: AlwaysStoppedAnimation(pctColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${pct.toStringAsFixed(1)}% of budget used',
                style: TextStyle(fontSize: context.sp(11), color: pctColor,
                    fontWeight: FontWeight.w600)),
            Text(pct > 100
                ? 'Over by ${_fmt2(spent - limit, currency)}'
                : 'Saved ${_fmt2(limit - spent, currency)}',
                style: TextStyle(fontSize: context.sp(11),
                    color: pct > 100 ? Colors.red.shade600 : Colors.green.shade600,
                    fontWeight: FontWeight.w600)),
          ]),

          // ── Expanded section ───────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.calendar_today_rounded, size: 13,
                    color: AppThemeColors.secondaryText(context)),
                const SizedBox(width: 4),
                Text('$s → $e', style: TextStyle(fontSize: context.sp(11),
                    color: AppThemeColors.secondaryText(context))),
                const SizedBox(width: 8),
                _badge(currency, Colors.amber.withValues(alpha: 0.13), Colors.amber.shade700),
              ]),
              if ((b['notes'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(b['notes'] as String, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.sp(12), fontStyle: FontStyle.italic,
                        color: AppThemeColors.secondaryText(context))),
              ],
              const SizedBox(height: 10),
              tricolorBorder(radius: 10, child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PersonalBudgetExpensesPage(
                    budgetId: id, budgetName: b['name'] as String? ?? '',
                    budgetCurrency: currency, readOnly: true),
                )),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.cyan),
                    const SizedBox(width: 6),
                    Text(AppLocalizations.of(context).t('view_expenses'),
                        style: TextStyle(fontSize: context.sp(12), color: AppColors.cyan,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              )),
            ]),
            secondChild: const SizedBox.shrink(),
          ),

          // ── View More / View Less toggle ───────────────────────────────
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() {
              if (expanded) _expandedHistoryIds.remove(id);
              else _expandedHistoryIds.add(id);
            }),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(expanded ? 'View Less' : 'View More',
                  style: TextStyle(fontSize: context.sp(12), color: AppColors.cyan,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 16, color: AppColors.cyan),
            ]),
          ),
        ]),
    );
  }

  Future<void> _confirmDeleteHistory(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context).t('delete_history')),
        content: Text(AppLocalizations.of(context).t('delete_history_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).t('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      final resp = await ApiClient.delete('/api/personal-budget/history/$id');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        showSnack(context, AppLocalizations.of(context).t('budget_deleted'));
        _fetch(reset: true);
      } else {
        final err = json.decode(resp.body);
        showSnack(context, err['error'] ?? 'Could not delete.', isError: true);
      }
    }
  }

  Widget _buildLoadMore() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: _loading
            ? const CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2)
            : OutlinedButton.icon(
                icon: const Icon(Icons.expand_more_rounded, color: AppColors.cyan),
                label: Text('Load more ($_total total)',
                    style: TextStyle(color: AppColors.cyan, fontSize: context.sp(13))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.cyan),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _fetch,
              ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.history_rounded, size: context.sp(56),
            color: AppThemeColors.secondaryText(context)),
        const SizedBox(height: 12),
        Text(AppLocalizations.of(context).t('no_history_found'), style: TextStyle(fontSize: context.sp(15),
            fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 6),
        Text('Completed or expired budgets will appear here.',
            style: TextStyle(fontSize: context.sp(12),
                color: AppThemeColors.secondaryText(context))),
      ]),
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

  String _periodLabel(String p) {
    const map = {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly',
        'yearly': 'Yearly', 'custom': 'Custom'};
    return map[p] ?? p;
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
