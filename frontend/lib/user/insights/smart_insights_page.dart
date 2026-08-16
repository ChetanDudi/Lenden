import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/theme_helper.dart';
import '../../widgets/search_tab_bar.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/responsive.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../widgets/currency_display.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../widgets/premium_gate.dart';
import 'tabs/spending_analysis_tab.dart';
import 'tabs/predictions_tab.dart';
import 'tabs/saving_tips_tab.dart';
import 'tabs/financial_health_tab.dart';
import 'tabs/goal_forecast_tab.dart';
import 'tabs/weekly_summary_tab.dart';
import 'tabs/smart_alerts_tab.dart';
import 'tabs/subscriptions_tab.dart';
import 'tabs/profile_tab.dart';

class SmartInsightsPage extends StatefulWidget {
  const SmartInsightsPage({super.key});

  @override
  State<SmartInsightsPage> createState() => _SmartInsightsPageState();
}

class _SmartInsightsPageState extends State<SmartInsightsPage>
    with SingleTickerProviderStateMixin, CurrencyDisplayMixin<SmartInsightsPage> {
  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _insights = [];
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _prediction;
  List<Map<String, dynamic>> _unusualExpenses = [];
  Map<String, dynamic>? _spendingHabits;
  Map<String, dynamic>? _weeklyAISummary;
  List<Map<String, dynamic>> _savingSuggestions = [];
  List<Map<String, dynamic>> _goalForecast = [];
  Map<String, dynamic>? _healthScoreData;
  List<Map<String, dynamic>> _subscriptions = [];
  Map<String, dynamic>? _financialPersonality;
  List<Map<String, dynamic>> _personalTimeline = [];
  Map<String, dynamic> _dailySpending = {};

  late final TabController _tabController;
  final _fmt = NumberFormat('#,##0', 'en_IN');
  String? _displayCurrencyError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 9, vsync: this);
    _fetchInsights();
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
    final amount = (v ?? 0).abs().toDouble();
    if (selectedCurrency == 'INR' || currencyData == null ||
        !currencyData!.canConvert('INR', selectedCurrency)) {
      return '₹${_fmt.format(amount)}';
    }
    final converted = currencyData!.convert(amount, 'INR', selectedCurrency);
    final sym = currencyData!.symbolFor(selectedCurrency);
    return '$sym${_fmt.format(converted)}';
  }

  Future<void> _fetchInsights() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final resp = await ApiClient.get('/api/insights');
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        setState(() {
          _insights          = (data['insights']          as List? ?? []).cast<Map<String, dynamic>>();
          _summary           = data['summary']            as Map<String, dynamic>?;
          _prediction        = data['prediction']         as Map<String, dynamic>?;
          _unusualExpenses   = (data['unusualExpenses']   as List? ?? []).cast<Map<String, dynamic>>();
          _spendingHabits    = data['spendingHabits']     as Map<String, dynamic>?;
          _weeklyAISummary   = data['weeklyAISummary']    as Map<String, dynamic>?;
          _savingSuggestions = (data['savingSuggestions'] as List? ?? []).cast<Map<String, dynamic>>();
          _goalForecast      = (data['goalForecast']      as List? ?? []).cast<Map<String, dynamic>>();
          _healthScoreData        = data['healthScore']           as Map<String, dynamic>?;
          _subscriptions          = (data['subscriptions']        as List? ?? []).cast<Map<String, dynamic>>();
          _financialPersonality   = data['financialPersonality']  as Map<String, dynamic>?;
          _personalTimeline       = (data['personalTimeline']     as List? ?? []).cast<Map<String, dynamic>>();
          _dailySpending          = (data['dailySpending']        as Map<String, dynamic>?) ?? {};
          _isLoading = false;
        });
      } else {
        setState(() { _hasError = true; _isLoading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _hasError = true; _isLoading = false; });
    }
  }

  Map<String, dynamic> get _unifiedInsights => {
    'spendingAnalysis':    _flatSpending,
    'predictions':         _flatPrediction,
    'savingTips':          _savingSuggestions,
    'financialHealth':     _healthScoreData,
    'goalForecasts':       _goalForecast,
    'weeklySummary':       _flatWeekly,
    'smartAlerts':         _insights,
    'unusualExpenses':     _unusualExpenses,
    'spendingHabits':      _habitItems,
    'spendingHabitsSummary': _spendingHabits,
    'subscriptions':         _subscriptions,
    'detectedRecurring':     <dynamic>[],
  };

  Map<String, dynamic> get _flatWeekly {
    final w = _weeklyAISummary;
    if (w == null) return {};
    final thisWeek = w['thisWeek'] as Map<String, dynamic>? ?? {};
    final lastWeek = w['lastWeek'] as Map<String, dynamic>? ?? {};
    return {
      'thisWeekTotal':    (thisWeek['spent']    as num?)?.toDouble() ?? 0,
      'lastWeekTotal':    (lastWeek['spent']    as num?)?.toDouble() ?? 0,
      'transactionCount': (thisWeek['txnCount'] as num?)?.toInt()   ?? 0,
      'weekChange':       w['weekChange'],
      'categoryBreakdown': w['categoryBreakdown'] as List? ?? [],
      'dailyBreakdown':    <dynamic>[],
      'topTransactions':   <dynamic>[],
      'last4Weeks':        <dynamic>[],
      'peakSpendDay':      '',
    };
  }

  Map<String, dynamic> get _flatSpending {
    final thisMonth  = (_summary?['thisMonth']  as Map<String, dynamic>?) ?? {};
    final lastMonth  = (_summary?['lastMonth']  as Map<String, dynamic>?) ?? {};
    final largestMap = _summary?['largestExpense'] as Map<String, dynamic>?;

    Map<String, double> _toDoubleMap(dynamic raw) =>
        (raw as Map?)?.map((k, v) => MapEntry(k as String, (v as num? ?? 0).toDouble()))
        ?? <String, double>{};

    final catBreak       = _toDoubleMap(_summary?['categoryBreakdown']);
    final lastCatBrk     = _toDoubleMap(_summary?['lastMonthBreakdown']);
    final quickCatBreak  = _toDoubleMap(_summary?['categoryBreakdownQuick']);
    final groupBreakdown = _toDoubleMap(_summary?['groupBreakdown']);

    final thisSpent    = (thisMonth['spent']   as num?)?.toDouble() ?? 0;
    final lastSpent    = (lastMonth['spent']   as num?)?.toDouble() ?? 0;
    final thisQuick    = (thisMonth['quick']   as num?)?.toDouble() ?? 0;
    final lastQuick    = (lastMonth['quick']   as num?)?.toDouble() ?? 0;
    final thisGroup    = (thisMonth['group']   as num?)?.toDouble() ?? 0;
    final lastGroup    = (lastMonth['group']   as num?)?.toDouble() ?? 0;

    final highlights = <String>[];
    if (lastSpent > 0 && thisSpent > 0) {
      final diff = thisSpent - lastSpent;
      if (diff >  500) highlights.add('Spending ${_ca(diff.abs())} more than last month so far.');
      if (diff < -500) highlights.add('Spending ${_ca(diff.abs())} less than last month — great discipline!');
    }
    return {
      'total':              thisSpent,
      'totalQuick':         thisQuick,
      'totalGroup':         thisGroup,
      'lastMonthTotal':     lastSpent,
      'lastMonthQuick':     lastQuick,
      'lastMonthGroup':     lastGroup,
      'avgDailySpend':      (_prediction?['dailyRate']   as num?)?.toDouble() ?? 0,
      'largestExpense':     (largestMap?['amount']       as num?)?.toDouble() ?? 0,
      'largestCategory':    largestMap?['category']      as String? ?? '',
      'transactionCount':   (thisMonth['txnCount']       as num?)?.toInt() ?? 0,
      'categoryBreakdown':  catBreak,
      'lastMonthBreakdown': lastCatBrk,
      'categoryBreakdownQuick': quickCatBreak,
      'groupBreakdown':     groupBreakdown,
      'highlights':         highlights,
    };
  }

  Map<String, dynamic> get _flatPrediction {
    final p = _prediction;
    if (p == null) return {};
    final daysElapsed = (p['daysElapsed'] as num?)?.toInt() ?? 0;
    final daysTotal   = (p['daysTotal']   as num?)?.toInt() ?? 30;
    return {
      'projectedTotal':       (p['predictedMonthEnd'] as num?)?.toDouble() ?? 0,
      'currentSpend':         (p['currentSpend']      as num?)?.toDouble() ?? 0,
      'daysRemainingInMonth': daysTotal - daysElapsed,
      'daysElapsed':          daysElapsed,
      'daysTotal':            daysTotal,
      'dailyRate':            (p['dailyRate']          as num?)?.toDouble() ?? 0,
      'willExceedBudget':     p['willExceedBudget']   as bool?,
      'dailyProjection':      <dynamic>[],
      'categoryForecasts':    <String, dynamic>{},
      'confidence':           75,
    };
  }

  List<Map<String, dynamic>> get _habitItems {
    final h = _spendingHabits;
    if (h == null) return [];
    final items = <Map<String, dynamic>>[];
    final highestDay = h['highestDayOfWeek'] as String?;
    final highestAvg = (h['highestDayAvg'] as num?)?.toDouble() ?? 0;
    if (highestDay != null && highestAvg > 50) {
      items.add({'title': '$highestDay is your biggest spending day',
        'detail': 'You average ${_ca(highestAvg)} per transaction on $highestDay.', 'kind': 'warning'});
    }
    final weekendTotal = (h['weekendTotal'] as num?)?.toDouble() ?? 0;
    final weekdayTotal = (h['weekdayTotal'] as num?)?.toDouble() ?? 0;
    if (weekendTotal > 0 || weekdayTotal > 0) {
      final heavier = weekendTotal > weekdayTotal;
      items.add({'title': heavier ? 'Weekend spending is higher' : 'Weekday spending dominates',
        'detail': 'Weekend: ${_ca(weekendTotal)} · Weekdays: ${_ca(weekdayTotal)} this month.',
        'kind': heavier && weekendTotal > weekdayTotal * 0.6 ? 'warning' : 'neutral'});
    }
    final topCat = h['mostExpensiveCategory'] as String?;
    if (topCat != null) {
      final catStr = '${topCat[0].toUpperCase()}${topCat.substring(1)}';
      items.add({'title': '$catStr is your top expense category',
        'detail': 'Most of your spending flows to $catStr.', 'kind': 'neutral'});
    }
    final highestMonth = h['highestMonth'] as String?;
    final highestMonthAvg = (h['highestMonthAvg'] as num?)?.toDouble() ?? 0;
    if (highestMonth != null && highestMonthAvg > 0) {
      items.add({'title': '$highestMonth is your most expensive month historically',
        'detail': 'Average spend in $highestMonth: ${_ca(highestMonthAvg)}.', 'kind': 'neutral'});
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context);

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
                      tooltip: t('back'),
                    ),
                    Expanded(
                      child: Text('Money Insights',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: context.sp(22), fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: AppThemeColors.primaryText(context)),
                      onPressed: _fetchInsights,
                      tooltip: t('refresh'),
                    ),
                  ]),
                ),
                // Currency selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Row(children: [
                    if (_displayCurrencyError != null)
                      Flexible(child: Text(_displayCurrencyError!,
                          style: TextStyle(fontSize: context.sp(11), color: Colors.orange))),
                    const Spacer(),
                    Text('Currency:', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
                    const SizedBox(width: 8),
                    buildCurrencySelector(),
                  ]),
                ),
                const SizedBox(height: 4),
                // TabBar
                AppTabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabs: const [
                    AppTabItem(label: 'Spending'),
                    AppTabItem(label: 'Predictions'),
                    AppTabItem(label: 'Tips'),
                    AppTabItem(label: 'Health Score'),
                    AppTabItem(label: 'Goal Forecast'),
                    AppTabItem(label: 'Weekly'),
                    AppTabItem(label: 'Alerts'),
                    AppTabItem(label: 'Subscriptions'),
                    AppTabItem(label: 'My Profile'),
                  ],
                ),
                // Body
                Expanded(
                  child: !session.hasFeature('smart_insights')
                      ? const InsightsPremiumGate()
                      : _isLoading
                          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                          : _hasError
                              ? errorStateWidget(context, t('fetch_error_message'), _fetchInsights)
                              : TabBarView(
                                  controller: _tabController,
                                  children: [
                                    SpendingAnalysisTab(insights: _unifiedInsights, ca: _ca, dailySpending: _dailySpending),
                                    PredictionsTab(insights: _unifiedInsights, ca: _ca),
                                    SavingTipsTab(insights: _unifiedInsights, ca: _ca),
                                    FinancialHealthTab(insights: _unifiedInsights, ca: _ca),
                                    GoalForecastTab(insights: _unifiedInsights, ca: _ca),
                                    WeeklySummaryTab(insights: _unifiedInsights, ca: _ca),
                                    SmartAlertsTab(insights: _unifiedInsights, ca: _ca),
                                    SubscriptionsTab(insights: _unifiedInsights, ca: _ca),
                                    ProfileTab(
                                      financialPersonality: _financialPersonality,
                                      personalTimeline: _personalTimeline,
                                      ca: _ca,
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
