import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../utils/pickers.dart';
import 'package:intl/intl.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../widgets/premium_gate.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../utils/currency_helpers.dart';
import '../../../l10n/app_localizations.dart';
import '../personal_budget_history_page.dart';
import '../personal_budget_expenses_page.dart';
import '../../digitise/subscriptions_page.dart';

class PersonalBudgetTab extends StatefulWidget {
  const PersonalBudgetTab({super.key});

  @override
  State<PersonalBudgetTab> createState() => _PersonalBudgetTabState();
}

class _PersonalBudgetTabState extends State<PersonalBudgetTab> {
  bool _loading = true;
  bool _hasAccess = false;
  bool _isTrial = false;
  int _trialDaysLeft = 0;
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _predictions = [];
  String? _error;
  String _viewCurrency = 'INR';
  final Set<String> _expandedIds = {};

  final _fmt = NumberFormat('#,##0.##', 'en_IN');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final accessResp = await ApiClient.get('/api/personal-budget/access');
      if (!mounted) return;
      if (accessResp.statusCode == 200) {
        final data = json.decode(accessResp.body);
        _hasAccess     = data['hasAccess'] == true;
        _isTrial       = data['isTrial'] == true;
        _trialDaysLeft = (data['trialDaysLeft'] as num?)?.toInt() ?? 0;
      } else {
        _error = 'Could not verify subscription status. Please retry.';
      }
      if (_hasAccess) {
        final results = await Future.wait([
          ApiClient.get('/api/personal-budget/active'),
          ApiClient.get('/api/personal-budget/predictions'),
        ]);
        if (!mounted) return;
        if (results[0].statusCode == 200) {
          _active = (json.decode(results[0].body) as List).cast<Map<String, dynamic>>();
        }
        if (results[1].statusCode == 200) {
          _predictions = (json.decode(results[1].body) as List).cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtC(num? v, String currency) =>
      '${currencySymbol(currency)}${_fmt.format(v ?? 0)}';

  // Convert from a budget's native currency to the user's selected view currency.
  String _fmtV(num? v, String fromCurrency) {
    final converted = convertCurrency((v ?? 0).toDouble(), fromCurrency, _viewCurrency);
    return '${currencySymbol(_viewCurrency)}${_fmt.format(converted)}';
  }

  Color _progressColor(double pct) {
    if (pct >= 100) return Colors.red.shade600;
    if (pct >= 80)  return Colors.orange.shade600;
    return AppColors.cyan;
  }

  String _healthLabel(double pct) {
    final l = AppLocalizations.of(context);
    if (pct < 60)  return l.t('pb_healthy');
    if (pct < 80)  return l.t('pb_moderate');
    if (pct < 100) return l.t('pb_warning');
    return l.t('pb_over_limit');
  }

  Color _healthColor(double pct) {
    if (pct < 60)  return Colors.green.shade600;
    if (pct < 80)  return AppColors.cyan;
    if (pct < 100) return Colors.orange.shade600;
    return Colors.red.shade600;
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

  Widget _buildTrialBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.card_giftcard_rounded, color: Colors.amber, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${AppLocalizations.of(context).t('free_trial')} — $_trialDaysLeft ${_trialDaysLeft == 1 ? 'day' : AppLocalizations.of(context).t('days_left')}. ${AppLocalizations.of(context).t('subscribe_to_keep_access')}',
            style: TextStyle(
              fontSize: context.sp(12),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.amber.shade300
                  : Colors.amber.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
          child: Text(AppLocalizations.of(context).t('subscribe'), style: TextStyle(fontSize: context.sp(12),
              color: AppColors.cyan, fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.cyan));
    }
    if (_error != null) return errorStateWidget(context, _error!, _init);
    if (!_hasAccess) return const BudgetPremiumGate();

    return RefreshIndicator(
      color: AppColors.cyan,
      onRefresh: _init,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          if (_isTrial) _buildTrialBanner(),
          _buildHeader(),
          const SizedBox(height: 12),
          if (_active.isNotEmpty) _buildOverviewCard(),
          if (_active.isEmpty) _buildEmpty() else ..._active.map(_buildBudgetCard),
          const SizedBox(height: 20),
          _buildHistoryButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
      Expanded(
        child: Text(AppLocalizations.of(context).t('my_budgets'),
            style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
      ),
      tricolorBorder(
        radius: 10,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<String>(
            value: _viewCurrency,
            underline: const SizedBox.shrink(),
            icon: const Icon(Icons.currency_exchange_rounded,
                size: 16, color: AppColors.cyan),
            dropdownColor: AppThemeColors.cardBg(context),
            style: TextStyle(fontSize: context.sp(12),
                color: AppThemeColors.primaryText(context)),
            items: kSupportedCurrencies
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) { if (v != null) setState(() => _viewCurrency = v); },
          ),
        ),
      ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add, size: 18),
        label: Text(AppLocalizations.of(context).t('new_budget')),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.cyan,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold),
        ),
      ),
    ]);
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.account_balance_wallet_outlined, size: context.sp(56),
            color: AppThemeColors.secondaryText(context)),
        const SizedBox(height: 14),
        Text(AppLocalizations.of(context).t('no_active_budgets'), style: TextStyle(fontSize: context.sp(15),
            fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 6),
        Text(AppLocalizations.of(context).t('start_new_budget_hint'),
            style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _buildOverviewCard() {
    // Compute aggregate in INR (convert each budget's amounts)
    double totalLimit = 0;
    double totalSpent = 0;
    int atRisk = 0;
    int healthy = 0;
    for (final b in _active) {
      final currency = (b['currency'] as String?) ?? 'INR';
      final limit    = (b['limit']       as num?)?.toDouble() ?? 0;
      final spent    = (b['spentAmount'] as num?)?.toDouble() ?? 0;
      final pct      = (b['percentSpent'] as num?)?.toDouble() ?? 0;
      totalLimit += convertCurrency(limit, currency, _viewCurrency);
      totalSpent += convertCurrency(spent, currency, _viewCurrency);
      if (pct >= 80) atRisk++; else healthy++;
    }
    final overallPct    = totalLimit > 0 ? (totalSpent / totalLimit) * 100 : 0.0;
    final overallPctStr = overallPct > 9999 ? '>9999' : overallPct.toStringAsFixed(1);
    final healthC       = _healthColor(overallPct);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.07),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.dashboard_rounded, color: AppColors.cyan, size: 16),
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).t('budget_overview'),
              style: TextStyle(fontSize: context.sp(13),
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const Spacer(),
          _chip('${_active.length} ${AppLocalizations.of(context).t('active_label')}',
              AppColors.cyan.withValues(alpha: 0.12), AppColors.cyan),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, cons) {
          final statW = ((cons.maxWidth - 27) / 4).clamp(90.0, double.infinity);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SizedBox(width: statW, child: _overviewStat(AppLocalizations.of(context).t('total_limit'),
                  _fmtC(totalLimit, _viewCurrency), AppThemeColors.primaryText(context))),
              _overviewDivider(),
              SizedBox(width: statW, child: _overviewStat(AppLocalizations.of(context).t('total_spent'),
                  _fmtC(totalSpent, _viewCurrency), healthC)),
              _overviewDivider(),
              SizedBox(width: statW, child: _overviewStat(AppLocalizations.of(context).t('pb_healthy'),
                  '$healthy', Colors.green.shade600, icon: Icons.check_circle_rounded)),
              _overviewDivider(),
              SizedBox(width: statW, child: _overviewStat(AppLocalizations.of(context).t('at_risk_label'),
                  '$atRisk', atRisk > 0 ? Colors.orange.shade700 : AppThemeColors.secondaryText(context),
                  icon: atRisk > 0 ? Icons.warning_rounded : null)),
            ]),
          );
        }),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (overallPct / 100).clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppThemeColors.scaffoldBg(context),
            valueColor: AlwaysStoppedAnimation(healthC),
          ),
        ),
        const SizedBox(height: 4),
        Text('$overallPctStr% of combined budget used  •  amounts in $_viewCurrency',
            style: TextStyle(fontSize: context.sp(10),
                color: AppThemeColors.secondaryText(context))),
      ]),
    );
  }

  Widget _overviewStat(String label, String value, Color valueColor,
      {IconData? icon}) {
    return Column(children: [
      if (icon != null) ...[
        Icon(icon, color: valueColor, size: 14),
        const SizedBox(height: 2),
      ],
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: context.sp(13),
              fontWeight: FontWeight.bold, color: valueColor)),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: context.sp(10),
              color: AppThemeColors.secondaryText(context))),
    ]);
  }

  Widget _overviewDivider() => Container(
        width: 1, height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: AppThemeColors.secondaryText(context).withValues(alpha: 0.15),
      );

  Widget _buildBudgetCard(Map<String, dynamic> b) {
    final pct      = (b['percentSpent'] as num?)?.toDouble() ?? 0;
    final timePct  = (b['progress']     as num?)?.toDouble() ?? 0;
    final spent    = (b['spentAmount']  as num?)?.toDouble() ?? 0;
    final limit    = (b['limit']        as num?)?.toDouble() ?? 0;
    final color    = _progressColor(pct);
    final days     = (b['daysLeft'] as num?)?.toInt() ?? 0;
    final period   = (b['period']   as String?) ?? '';
    final currency = (b['currency'] as String?) ?? 'INR';
    final id       = b['_id'] as String;
    final endDate  = b['endDate'] != null ? DateTime.parse(b['endDate']).toLocal() : null;
    final canEdit  = b['status'] == 'active' && (endDate?.isAfter(DateTime.now()) ?? false);
    final expanded    = _expandedIds.contains(id);
    final pred        = _predictions.where((p) => p['_id'] == id).firstOrNull;
    final budgetColor = _colorFromBudget(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: budgetColor.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: budgetColor.withValues(alpha: 0.45), width: 2),
        boxShadow: [BoxShadow(color: budgetColor.withValues(alpha: 0.12),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Always visible: header ─────────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(b['name'] ?? '', style: TextStyle(fontSize: context.sp(15),
                        fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _healthColor(pct).withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(pct < 60 ? Icons.check_circle_rounded
                          : pct < 80 ? Icons.info_rounded
                          : pct < 100 ? Icons.warning_rounded : Icons.error_rounded,
                          color: _healthColor(pct), size: 11),
                      const SizedBox(width: 4),
                      Text(_healthLabel(pct), style: TextStyle(fontSize: context.sp(10),
                          color: _healthColor(pct), fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip(_periodLabel(period), AppColors.cyan.withValues(alpha: 0.15), AppColors.cyan),
                  _chip(currency, Colors.amber.withValues(alpha: 0.15), Colors.amber.shade700),
                  _chip('$days day${days == 1 ? '' : 's'} left',
                      days <= 2 ? Colors.red.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
                      days <= 2 ? Colors.red : AppThemeColors.secondaryText(context)),
                ]),
              ]),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: AppThemeColors.secondaryText(context), size: 20),
              onSelected: (v) {
                if (v == 'edit')     _showEditDialog(b);
                if (v == 'delete')   _confirmDelete(id);
                if (v == 'complete') _markComplete(id);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit',     child: Text(AppLocalizations.of(context).t('edit'))),
                PopupMenuItem(value: 'complete', child: Text(AppLocalizations.of(context).t('mark_complete'))),
                PopupMenuItem(value: 'delete',   child: Text(AppLocalizations.of(context).t('delete'),
                    style: const TextStyle(color: Colors.red))),
              ],
            ),
          ]),

          // ── Always visible: amounts + progress ─────────────────────────
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, cons) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: cons.maxWidth),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_fmtV(spent, currency), style: TextStyle(fontSize: context.sp(20),
                      fontWeight: FontWeight.bold, color: color)),
                  Text(AppLocalizations.of(context).t('spent_label'), style: TextStyle(fontSize: context.sp(10),
                      color: AppThemeColors.secondaryText(context))),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtV(limit, currency), style: TextStyle(fontSize: context.sp(20),
                      fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                  Text(AppLocalizations.of(context).t('limit_label'), style: TextStyle(fontSize: context.sp(10),
                      color: AppThemeColors.secondaryText(context))),
                ]),
              ]),
            ),
          )),
          const SizedBox(height: 10),
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
              value: (timePct / 100).clamp(0.0, 1.0), minHeight: 12,
              backgroundColor: AppThemeColors.scaffoldBg(context),
              valueColor: AlwaysStoppedAnimation(
                  AppThemeColors.secondaryText(context).withValues(alpha: 0.25)),
            )),
            ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0), minHeight: 12,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.85)),
            )),
          ]),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              Container(width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${pct > 9999 ? ">9999" : pct.toStringAsFixed(1)}% ${AppLocalizations.of(context).t('spent_label')}',
                  style: TextStyle(fontSize: context.sp(10), color: color, fontWeight: FontWeight.w600)),
            ]),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: AppThemeColors.secondaryText(context).withValues(alpha: 0.4),
                  shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text('${timePct.toStringAsFixed(0)}% time elapsed',
                  style: TextStyle(fontSize: context.sp(10),
                      color: AppThemeColors.secondaryText(context))),
            ]),
          ]),
          const SizedBox(height: 6),
          LayoutBuilder(builder: (context, cons) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: cons.maxWidth),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(spent <= limit
                    ? '${_fmtV(limit - spent, currency)} ${AppLocalizations.of(context).t('remaining_label').toLowerCase()}'
                    : '${AppLocalizations.of(context).t('over_by_label')} ${_fmtV(spent - limit, currency)}',
                    style: TextStyle(fontSize: context.sp(11),
                        color: spent <= limit ? Colors.green.shade600 : Colors.red.shade600,
                        fontWeight: FontWeight.w600)),
                if (timePct > 0 && pct > 0)
                  Text(pct > timePct
                      ? AppLocalizations.of(context).t('pb_spending_fast')
                      : AppLocalizations.of(context).t('pb_under_pace'),
                      style: TextStyle(fontSize: context.sp(11),
                          color: pct > timePct ? Colors.orange.shade700 : Colors.green.shade600,
                          fontWeight: FontWeight.w600)),
              ]),
            ),
          )),

          // ── Expanded section ───────────────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 220),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((b['notes'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(b['notes'] as String, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: context.sp(12),
                        color: AppThemeColors.secondaryText(context),
                        fontStyle: FontStyle.italic)),
              ],
              if ((b['allocations'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.pie_chart_outline_rounded,
                      size: 13, color: AppColors.cyan),
                  const SizedBox(width: 5),
                  Text('Planned Allocations',
                      style: TextStyle(fontSize: context.sp(11),
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.secondaryText(context))),
                ]),
                const SizedBox(height: 6),
                ...(b['allocations'] as List).map((a) {
                  final aMap    = a as Map<String, dynamic>;
                  final aLimit  = (aMap['limit'] as num?)?.toDouble() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      const Icon(Icons.chevron_right_rounded,
                          size: 14, color: AppColors.cyan),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(aMap['name'] as String? ?? '',
                            style: TextStyle(fontSize: context.sp(12),
                                color: AppThemeColors.primaryText(context))),
                      ),
                      Text(_fmtC(aLimit, currency),
                          style: TextStyle(fontSize: context.sp(12),
                              fontWeight: FontWeight.w600,
                              color: AppThemeColors.secondaryText(context))),
                    ]),
                  );
                }),
              ],
              const SizedBox(height: 10),
              _dateRange(b),
              if (pred != null) ...[
                const SizedBox(height: 12),
                _buildInlinePrediction(pred, currency),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: tricolorBorder(radius: 10, child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => PersonalBudgetExpensesPage(
                        budgetId: id, budgetName: b['name'] as String? ?? '',
                        budgetCurrency: currency, readOnly: !canEdit),
                    )).then((_) => _init()),
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
                ),
                if (canEdit) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: tricolorBorder(radius: 10, glow: true, child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => PersonalBudgetExpensesPage(
                          budgetId: id, budgetName: b['name'] as String? ?? '',
                          budgetCurrency: currency),
                      )).then((_) => _init()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(color: AppColors.cyan,
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(AppLocalizations.of(context).t('add_expense'),
                              style: TextStyle(fontSize: context.sp(12), color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    )),
                  ),
                ],
              ]),
            ]),
            secondChild: const SizedBox.shrink(),
          ),

          // ── View More / View Less toggle ───────────────────────────────
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() {
              if (expanded) _expandedIds.remove(id); else _expandedIds.add(id);
            }),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(expanded ? AppLocalizations.of(context).t('view_less') : AppLocalizations.of(context).t('view_more'),
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

  Widget _buildInlinePrediction(Map<String, dynamic> p, String currency) {
    final onTrack   = p['onTrack'] as bool?;
    final rec       = p['recommendation'] as String?;
    final projected = (p['projectedSpend'] as num?)?.toDouble();
    final limit     = (p['limit'] as num?)?.toDouble() ?? 0;
    final pct       = (p['progress'] as num?)?.toInt() ?? 0;
    final dataPoints = (p['historicalDataPoints'] as num?)?.toInt() ?? 0;
    final color = onTrack == true ? Colors.green.shade600 : Colors.orange.shade700;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(onTrack == true
              ? Icons.trending_down_rounded
              : Icons.trending_up_rounded,
              color: color, size: 16),
          const SizedBox(width: 6),
          Text(AppLocalizations.of(context).t('budget_prediction'), style: TextStyle(fontSize: context.sp(12),
              fontWeight: FontWeight.bold, color: color)),
          const Spacer(),
          _chip(onTrack == true ? AppLocalizations.of(context).t('on_track_label') : AppLocalizations.of(context).t('at_risk_label'),
              color.withValues(alpha: 0.12), color),
        ]),
        if (projected != null) ...[
          const SizedBox(height: 4),
          Text('Projected: ${_fmtV(projected, currency)} / ${_fmtV(limit, currency)} limit  •  $pct% elapsed',
              style: TextStyle(fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context))),
        ],
        if (dataPoints > 0)
          Text('Based on $dataPoints past budget${dataPoints == 1 ? '' : 's'}',
              style: TextStyle(fontSize: context.sp(11),
                  color: AppThemeColors.secondaryText(context))),
        if (rec != null) ...[
          const SizedBox(height: 6),
          Text(rec, style: TextStyle(fontSize: context.sp(12),
              color: color, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _dateRange(Map<String, dynamic> b) {
    final df = DateFormat('dd MMM yyyy');
    final s  = b['startDate'] != null ? df.format(DateTime.parse(b['startDate']).toLocal()) : '';
    final e  = b['endDate']   != null ? df.format(DateTime.parse(b['endDate']).toLocal()) : '';
    return Row(children: [
      Icon(Icons.calendar_month_rounded, size: 14, color: AppThemeColors.secondaryText(context)),
      const SizedBox(width: 4),
      Text('$s → $e', style: TextStyle(fontSize: context.sp(11),
          color: AppThemeColors.secondaryText(context))),
    ]);
  }

  Widget _buildHistoryButton() {
    return tricolorBorder(
      radius: 14,
      child: GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PersonalBudgetHistoryPage())),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppThemeColors.scaffoldBg(context),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.history_rounded, color: AppColors.cyan, size: 20),
            const SizedBox(width: 8),
            Text(AppLocalizations.of(context).t('view_budget_history'),
                style: TextStyle(color: AppColors.cyan, fontSize: context.sp(14),
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: context.sp(11), color: fg, fontWeight: FontWeight.w600)),
    );
  }

  String _periodLabel(String p) {
    final t = AppLocalizations.of(context).t;
    switch (p) {
      case 'daily':   return t('daily');
      case 'weekly':  return t('weekly');
      case 'monthly': return t('monthly');
      case 'yearly':  return t('yearly');
      case 'custom':  return t('custom_label');
      default:        return p;
    }
  }

  // ─── Create/Edit dialog ────────────────────────────────────────────────────

  void _showCreateDialog() => _showBudgetDialog(null);
  void _showEditDialog(Map<String, dynamic> b) => _showBudgetDialog(b);

  void _showBudgetDialog(Map<String, dynamic>? existing) {
    final nameCtrl  = TextEditingController(text: existing?['name'] as String? ?? '');
    final limitCtrl = TextEditingController(
        text: existing != null ? (existing['limit'] as num).toString() : '');
    final notesCtrl = TextEditingController(text: existing?['notes'] as String? ?? '');
    String period   = existing?['period'] as String? ?? 'monthly';
    String currency = existing?['currency'] as String? ?? 'INR';
    DateTime startDate = existing != null
        ? DateTime.parse(existing['startDate']).toLocal()
        : DateTime.now();
    DateTime endDate   = existing != null
        ? DateTime.parse(existing['endDate']).toLocal()
        : DateTime.now().add(const Duration(days: 30));

    // Allocation items: parallel lists of name/limit controllers
    final allocNameCtrls  = <TextEditingController>[];
    final allocLimitCtrls = <TextEditingController>[];
    final existingAllocs  = (existing?['allocations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    for (final a in existingAllocs) {
      allocNameCtrls.add(TextEditingController(text: a['name'] as String? ?? ''));
      allocLimitCtrls.add(TextEditingController(
          text: (a['limit'] as num?)?.toString() ?? ''));
    }

    void applyPeriodDefaults(String p, StateSetter setState) {
      final now = DateTime.now();
      switch (p) {
        case 'daily':
          startDate = DateTime(now.year, now.month, now.day);
          endDate   = startDate.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
          break;
        case 'weekly':
          final dow  = now.weekday;
          startDate = DateTime(now.year, now.month, now.day - (dow - 1));
          endDate   = startDate.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
          break;
        case 'monthly':
          startDate = DateTime(now.year, now.month);
          endDate   = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'yearly':
          startDate = DateTime(now.year);
          endDate   = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
        default: break;
      }
      setState(() {});
    }

    final df = DateFormat('dd MMM yyyy');
    bool saving = false;

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
              Text(existing == null ? 'New Personal Budget' : 'Edit Budget',
                  style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 16),

              _field(nameCtrl,  'Budget Name', Icons.label_rounded),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _field(limitCtrl,
                      'Limit (${currencySymbol(currency)})',
                      currencyIcon(currency),
                      type: TextInputType.number),
                ),
                const SizedBox(width: 10),
                tricolorBorder(
                  radius: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButton<String>(
                      value: currency,
                      underline: const SizedBox.shrink(),
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.cyan, size: 18),
                      dropdownColor: AppThemeColors.cardBg(context),
                      style: TextStyle(fontSize: context.sp(13),
                          color: AppThemeColors.primaryText(context)),
                      items: kSupportedCurrencies
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: existing == null
                          ? (v) { if (v != null) setS(() => currency = v); }
                          : null,
                    ),
                  ),
                ),
              ]),
              if (existing != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(AppLocalizations.of(context).t('currency_locked_note'),
                      style: TextStyle(fontSize: context.sp(11),
                          color: AppThemeColors.secondaryText(context),
                          fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 12),

              Text('Period', style: TextStyle(fontSize: context.sp(13),
                  color: AppThemeColors.secondaryText(context))),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: ['daily', 'weekly', 'monthly', 'yearly', 'custom']
                  .map((p) => ChoiceChip(
                        label: Text(_periodLabel(p)),
                        selected: period == p,
                        selectedColor: AppColors.cyan,
                        labelStyle: TextStyle(
                            color: period == p ? Colors.white : AppThemeColors.primaryText(context),
                            fontSize: context.sp(12)),
                        onSelected: (_) {
                          setS(() => period = p);
                          if (p != 'custom') applyPeriodDefaults(p, setS);
                        },
                      ))
                  .toList()),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(child: _datePicker(ctx, 'Start', df.format(startDate), () async {
                  final d = await showAppDatePicker(context: ctx,
                      initialDate: startDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
                  if (d != null) setS(() => startDate = DateTime(d.year, d.month, d.day, startDate.hour, startDate.minute));
                })),
                const SizedBox(width: 12),
                Expanded(child: _datePicker(ctx, 'End', df.format(endDate), () async {
                  final d = await showAppDatePicker(context: ctx,
                      initialDate: endDate, firstDate: DateTime(2020), lastDate: DateTime(2035));
                  if (d != null) setS(() => endDate = DateTime(d.year, d.month, d.day, endDate.hour, endDate.minute));
                })),
              ]),
              const SizedBox(height: 12),

              _field(notesCtrl, 'Notes (optional)', Icons.notes_rounded, maxLines: 3),
              const SizedBox(height: 20),

              // ── Allocation items ──────────────────────────────────────────
              Row(children: [
                const Icon(Icons.pie_chart_outline_rounded,
                    size: 16, color: AppColors.cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Planned Allocations (optional)',
                      style: TextStyle(fontSize: context.sp(13),
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context))),
                ),
                GestureDetector(
                  onTap: () {
                    setS(() {
                      allocNameCtrls.add(TextEditingController());
                      allocLimitCtrls.add(TextEditingController());
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_rounded, size: 14, color: AppColors.cyan),
                      const SizedBox(width: 4),
                      Text('Add', style: TextStyle(fontSize: context.sp(12),
                          color: AppColors.cyan, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
              if (allocNameCtrls.isEmpty) ...[
                const SizedBox(height: 6),
                Text('Optionally break down where you plan to spend this budget.',
                    style: TextStyle(fontSize: context.sp(11),
                        color: AppThemeColors.secondaryText(context),
                        fontStyle: FontStyle.italic)),
              ],
              ...List.generate(allocNameCtrls.length, (i) => Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: allocNameCtrls[i],
                      onChanged: (_) => setS(() {}),
                      style: TextStyle(fontSize: context.sp(13),
                          color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        hintText: 'e.g. Food, Transport',
                        filled: true,
                        fillColor: AppThemeColors.cardBg(context),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: allocLimitCtrls[i],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setS(() {}),
                      style: TextStyle(fontSize: context.sp(13),
                          color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        hintText: 'Limit',
                        prefixText: currencySymbol(currency),
                        filled: true,
                        fillColor: AppThemeColors.cardBg(context),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => setS(() {
                      allocNameCtrls.removeAt(i);
                      allocLimitCtrls.removeAt(i);
                    }),
                    child: const Icon(Icons.remove_circle_outline_rounded,
                        color: Colors.red, size: 22),
                  ),
                ]),
              )),
              if (allocNameCtrls.isNotEmpty) Builder(builder: (_) {
                final mainLimit = double.tryParse(limitCtrl.text.trim()) ?? 0;
                final allocTotal = List.generate(allocLimitCtrls.length,
                    (i) => double.tryParse(allocLimitCtrls[i].text.trim()) ?? 0.0)
                    .fold(0.0, (a, b) => a + b);
                final over = allocTotal > mainLimit && mainLimit > 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${currencySymbol(currency)}${_fmt.format(allocTotal)} of ${currencySymbol(currency)}${_fmt.format(mainLimit)} allocated'
                    '${over ? ' — exceeds limit!' : ''}',
                    style: TextStyle(
                      fontSize: context.sp(11),
                      color: over ? Colors.red : AppThemeColors.secondaryText(context),
                      fontWeight: over ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              }),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : () async {
                    final name  = nameCtrl.text.trim();
                    final limit = double.tryParse(limitCtrl.text.trim());
                    if (name.isEmpty || limit == null || limit <= 0) {
                      showSnack(context, 'Please enter a valid name and limit.', isError: true);
                      return;
                    }
                    if (!endDate.isAfter(startDate)) {
                      showSnack(context, 'End date must be after start date.', isError: true);
                      return;
                    }
                    final allocations = List.generate(allocNameCtrls.length, (i) {
                      final aName  = allocNameCtrls[i].text.trim();
                      final aLimit = double.tryParse(allocLimitCtrls[i].text.trim());
                      return aName.isNotEmpty && aLimit != null
                          ? {'name': aName, 'limit': aLimit}
                          : null;
                    }).whereType<Map<String, dynamic>>().toList();
                    final allocTotal = allocations.fold(0.0, (s, a) => s + (a['limit'] as double));
                    if (allocTotal > limit) {
                      showSnack(context, 'Allocation totals exceed the budget limit.', isError: true);
                      return;
                    }
                    setS(() => saving = true);
                    try {
                      final body = {
                        'name': name, 'period': period, 'limit': limit,
                        'startDate': startDate.toIso8601String(),
                        'endDate': endDate.toIso8601String(),
                        'notes': notesCtrl.text.trim(),
                        'allocations': allocations,
                        if (existing == null) 'currency': currency,
                      };
                      final resp = existing == null
                          ? await ApiClient.post('/api/personal-budget', body: body)
                          : await ApiClient.put('/api/personal-budget/${existing['_id']}', body: body);
                      if (!mounted) return;
                      if (resp.statusCode == 200 || resp.statusCode == 201) {
                        Navigator.pop(ctx);
                        showSnack(context, AppLocalizations.of(context).t(existing == null ? 'budget_created' : 'budget_updated'));
                        _init();
                      } else {
                        final err = json.decode(resp.body);
                        showSnack(context, err['error'] ?? 'Could not save budget.', isError: true);
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: saving
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(existing == null ? 'Create Budget' : 'Save Changes',
                          style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {TextInputType type = TextInputType.text, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      maxLines: maxLines,
      style: TextStyle(fontSize: context.sp(14), color: AppThemeColors.primaryText(context)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.cyan, size: 20),
        filled: true,
        fillColor: AppThemeColors.cardBg(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  Widget _datePicker(BuildContext ctx, String label, String value, VoidCallback onTap) {
    return tricolorBorder(
      radius: 12,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: context.sp(11),
                color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.cyan),
              const SizedBox(width: 6),
              Text(value, style: TextStyle(fontSize: context.sp(13),
                  color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppLocalizations.of(context).t('delete_budget')),
        content: Text(AppLocalizations.of(context).t('delete_budget_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context).t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).t('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await ApiClient.delete('/api/personal-budget/$id');
      if (mounted) { showSnack(context, AppLocalizations.of(context).t('budget_deleted')); _init(); }
    }
  }

  Future<void> _markComplete(String id) async {
    final resp = await ApiClient.put('/api/personal-budget/$id', body: {'status': 'completed'});
    if (!mounted) return;
    if (resp.statusCode == 200) { showSnack(context, AppLocalizations.of(context).t('budget_complete')); _init(); }
  }
}
