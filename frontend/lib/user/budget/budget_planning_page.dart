import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/responsive.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../widgets/currency_display.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'tabs/personal_budget_tab.dart';
import 'tabs/monthly_budget_tab.dart';
import 'tabs/category_budgets_tab.dart';
import 'tabs/group_budgets_tab.dart';
import 'tabs/goals_tab.dart';
import 'tabs/alerts_tab.dart';
import 'tabs/history_tab.dart';
import 'tabs/recurring_tab.dart';

class BudgetPlanningPage extends StatefulWidget {
  final int initialTabIndex;
  const BudgetPlanningPage({super.key, this.initialTabIndex = 0});

  @override
  State<BudgetPlanningPage> createState() => _BudgetPlanningPageState();
}

class _BudgetPlanningPageState extends State<BudgetPlanningPage>
    with SingleTickerProviderStateMixin, CurrencyDisplayMixin<BudgetPlanningPage> {
  bool _isLoading = true;
  bool _hasError = false;
  Map<String, dynamic>? _budget;
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _goals = [];
  Map<String, dynamic>? _recommendations;
  Map<String, dynamic>? _budgetInsights;
  Map<String, dynamic>? _rolloverPreview;
  Map<String, dynamic>? _streak;

  late final TabController _tabController;
  final _now = DateTime.now();
  final _fmt = NumberFormat('#,##0', 'en_IN');
  String? _displayCurrencyError;

  static const _presets = [
    ('Starter', 5000.0, 10000.0, 3000.0, 15000.0),
    ('Regular', 12000.0, 25000.0, 8000.0, 40000.0),
    ('Power',   30000.0, 60000.0, 20000.0, 100000.0),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this,
        initialIndex: widget.initialTabIndex.clamp(0, 7));
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.hasFeature('budget_planning')) {
      _fetchData();
    } else {
      // Not subscribed — don't burn 8 API calls. Each tab gates itself.
      // Personal Budget tab uses its own access check (supports 30-day trial).
      _isLoading = false;
    }
    loadCurrencies(onError: (_) {
      if (mounted) setState(() => _displayCurrencyError = 'Currency conversion unavailable');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _ca(num? v) {
    final amount = (v ?? 0).toDouble();
    if (selectedCurrency == 'INR' || currencyData == null ||
        !currencyData!.canConvert('INR', selectedCurrency)) {
      return '₹${_fmt.format(amount)}';
    }
    final converted = currencyData!.convert(amount, 'INR', selectedCurrency);
    final sym = currencyData!.symbolFor(selectedCurrency);
    return '$sym${_fmt.format(converted)}';
  }

  Future<void> _fetchData() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final results = await Future.wait([
        ApiClient.get('/api/budget/${_now.year}/${_now.month}'),
        ApiClient.get('/api/budget/status'),
        ApiClient.get('/api/budget/history'),
        ApiClient.get('/api/savings-goals'),
        ApiClient.get('/api/budget/recommendations'),
        ApiClient.get('/api/budget/insights'),
        ApiClient.get('/api/budget/rollover-preview'),
        ApiClient.get('/api/budget/streak'),
      ]);
      if (!mounted) return;
      if (results[0].statusCode == 200) _budget          = json.decode(results[0].body);
      if (results[1].statusCode == 200) _status          = json.decode(results[1].body);
      if (results[2].statusCode == 200) _history         = (json.decode(results[2].body) as List).cast<Map<String, dynamic>>();
      if (results[3].statusCode == 200) _goals           = (json.decode(results[3].body) as List).cast<Map<String, dynamic>>();
      if (results[4].statusCode == 200) _recommendations = json.decode(results[4].body);
      if (results[5].statusCode == 200) _budgetInsights  = json.decode(results[5].body);
      if (results[6].statusCode == 200) _rolloverPreview = json.decode(results[6].body);
      if (results[7].statusCode == 200) _streak          = json.decode(results[7].body);
      setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Future<void> _applyRollover() async {
    try {
      final resp = await ApiClient.post('/api/budget/rollover', body: {
        'year': _now.year, 'month': _now.month,
      });
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Surplus rolled over to this month\'s budget!'),
          backgroundColor: Colors.teal, behavior: SnackBarBehavior.floating,
        ));
        await _fetchData();
      } else {
        final body = json.decode(resp.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(body['message'] ?? 'Could not apply rollover'),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (_) {}
  }

  Future<void> _saveGroupLimit(String groupId, double? limit) async {
    final resp = await ApiClient.patch('/api/budget/group-limit', body: {
      'year': _now.year,
      'month': _now.month,
      'groupId': groupId,
      if (limit != null) 'limit': limit,
    });
    if (!mounted) return;
    if (resp.statusCode == 200) {
      await _fetchData();
    } else {
      final body = json.decode(resp.body);
      throw Exception(body['message'] ?? 'Could not save group limit');
    }
  }

  Future<void> _saveBudget(String type, String value) async {
    final parsed = double.tryParse(value);
    if (value.isNotEmpty && parsed == null) return;
    try {
      final limits = Map<String, dynamic>.from(_budget?['limits'] ?? {});
      limits[type] = value.isEmpty ? null : parsed;
      final resp = await ApiClient.post('/api/budget', body: {
        'year': _now.year,
        'month': _now.month,
        'limits': limits,
      });
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _budget = json.decode(resp.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context).t('budget_save_success')),
            backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
          ));
        }
        await _fetchData();
      }
    } catch (_) {}
  }

  Future<void> _saveCategoryBudget(String key, String value) async {
    final parsed = double.tryParse(value);
    if (value.isNotEmpty && parsed == null) return;
    try {
      final catLimits = Map<String, dynamic>.from(_budget?['categoryLimits'] as Map? ?? {});
      catLimits[key] = value.isEmpty ? null : parsed;
      final resp = await ApiClient.put('/api/budget/categories', body: {
        'year': _now.year, 'month': _now.month, 'categoryLimits': catLimits,
      });
      if (!mounted) return;
      if (resp.statusCode == 200) {
        _budget = json.decode(resp.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Category budget saved'), backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ));
        }
        await _fetchData();
      }
    } catch (_) {}
  }

  Future<void> _createGoal(Map<String, dynamic> body) async {
    try {
      final resp = await ApiClient.post('/api/savings-goals', body: body);
      if (!mounted) return;
      if (resp.statusCode == 201) await _fetchData();
    } catch (_) {}
  }

  Future<void> _addToGoal(String id, double amount) async {
    final resp = await ApiClient.post('/api/savings-goals/$id/add', body: { 'amount': amount });
    if (resp.statusCode == 200 && mounted) await _fetchData();
  }

  Future<void> _deleteGoal(String id) async {
    final resp = await ApiClient.delete('/api/savings-goals/$id');
    if (resp.statusCode == 200 && mounted) await _fetchData();
  }

  Future<void> _saveRecurring(Map<String, dynamic> body) async {
    try {
      final resp = await ApiClient.post('/api/budget/recurring', body: body);
      if (!mounted) return;
      if (resp.statusCode == 201) await _fetchData();
    } catch (_) {}
  }

  Future<void> _deleteRecurring(String id) async {
    final resp = await ApiClient.delete('/api/budget/recurring/$id');
    if (resp.statusCode == 200 && mounted) await _fetchData();
  }

  Future<void> _saveAlertThresholds(List<int> thresholds) async {
    try {
      final resp = await ApiClient.put('/api/budget/alerts', body: {
        'year': _now.year,
        'month': _now.month,
        'alertThresholds': thresholds,
      });
      if (!mounted) return;
      if (resp.statusCode == 200) {
        await _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Alert thresholds saved'),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    } catch (_) {}
  }

  void _showPresetDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.auto_fix_high_rounded, color: AppColors.cyan, size: 20),
          const SizedBox(width: 8),
          Text('Quick Presets', style: TextStyle(fontSize: context.sp(16), fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Apply a budget template for this month',
              style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
          const SizedBox(height: 16),
          for (final p in _presets) _presetTile(p),
        ]),
      ),
    );
  }

  Widget _presetTile((String, double, double, double, double) p) {
    const colors = [Colors.teal, AppColors.cyan, Colors.deepPurple];
    const icons  = [Icons.spa_outlined, Icons.bolt_outlined, Icons.rocket_outlined];
    final idx    = _presets.indexOf(p);
    final color  = colors[idx];
    return GestureDetector(
      onTap: () => _applyPreset(p.$2, p.$3, p.$4, p.$5),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icons[idx], color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.$1, style: TextStyle(fontSize: context.sp(13), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            Text('Overall: ${_ca(p.$5)}', style: TextStyle(fontSize: context.sp(11), color: color)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppThemeColors.secondaryText(context)),
        ]),
      ),
    );
  }

  Future<void> _applyPreset(double quick, double secure, double group, double overall) async {
    Navigator.pop(context);
    final resp = await ApiClient.post('/api/budget', body: {
      'year': _now.year,
      'month': _now.month,
      'limits': { 'quick': quick, 'secure': secure, 'group': group, 'overall': overall },
    });
    if (!mounted) return;
    if (resp.statusCode == 200) _budget = json.decode(resp.body);
    await _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(height: context.sh(85), color: AppThemeColors.waveSolid(context)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 16, 0),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(child: Column(children: [
                      Text(t('budget_planning_page_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: context.sp(20), fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                      Text(DateFormat('MMMM yyyy').format(_now),
                          style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
                    ])),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: AppThemeColors.primaryText(context)),
                      onPressed: _fetchData,
                    ),
                  ]),
                ),
                // Currency selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Row(children: [
                    if (_displayCurrencyError != null)
                      Expanded(child: Text(_displayCurrencyError!,
                          style: TextStyle(fontSize: context.sp(11), color: Colors.orange))),
                    const Spacer(),
                    Text('Currency:', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
                    const SizedBox(width: 8),
                    buildCurrencySelector(),
                  ]),
                ),
                const SizedBox(height: 4),
                // TabBar
                Container(
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                    labelColor: AppColors.cyan,
                    unselectedLabelColor: AppThemeColors.secondaryText(context),
                    indicator: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelStyle: TextStyle(fontSize: context.sp(12), fontWeight: FontWeight.bold),
                    unselectedLabelStyle: TextStyle(fontSize: context.sp(12)),
                    tabs: [
                      Tab(text: t('tab_personal')),
                      Tab(text: t('monthly')),
                      Tab(text: t('tab_categories')),
                      Tab(text: t('groups_label')),
                      Tab(text: t('tab_goals')),
                      Tab(text: t('alerts_label')),
                      Tab(text: t('history_label')),
                      Tab(text: t('tab_recurring')),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                      : _hasError
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.error_outline, color: Colors.red.shade300, size: 48),
                              const SizedBox(height: 12),
                              Text(t('fetch_error_message'),
                                  style: TextStyle(color: AppThemeColors.secondaryText(context))),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetchData,
                                icon: const Icon(Icons.refresh),
                                label: Text(t('retry')),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.cyan, foregroundColor: Colors.white),
                              ),
                            ]))
                          : TabBarView(
                                  controller: _tabController,
                                  children: [
                                    const PersonalBudgetTab(),
                                    MonthlyBudgetTab(
                                      budget: _budget,
                                      status: _status,
                                      recommendations: _recommendations,
                                      rolloverPreview: _rolloverPreview,
                                      streak: _streak,
                                      now: _now,
                                      ca: _ca,
                                      onSaveBudget: _saveBudget,
                                      onShowPresets: _showPresetDialog,
                                      onApplyRollover: _applyRollover,
                                    ),
                                    CategoryBudgetsTab(
                                      budget: _budget,
                                      status: _status,
                                      recommendations: _recommendations,
                                      ca: _ca,
                                      onSaveCategoryBudget: _saveCategoryBudget,
                                    ),
                                    GroupBudgetsTab(status: _status, budget: _budget, ca: _ca, onSaveGroupLimit: _saveGroupLimit),
                                    GoalsTab(
                                      goals: _goals,
                                      ca: _ca,
                                      onCreateGoal: _createGoal,
                                      onAddToGoal: _addToGoal,
                                      onDeleteGoal: _deleteGoal,
                                    ),
                                    AlertsTab(
                                      status: _status,
                                      budget: _budget,
                                      ca: _ca,
                                      onSaveThresholds: _saveAlertThresholds,
                                    ),
                                    HistoryTab(
                                      budget: {'history': _history, 'insights': _budgetInsights},
                                      ca: _ca,
                                    ),
                                    RecurringTab(
                                      budget: _budget,
                                      status: _status,
                                      ca: _ca,
                                      onSaveRecurring: _saveRecurring,
                                      onDeleteRecurring: _deleteRecurring,
                                    ),
                                  ],
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
