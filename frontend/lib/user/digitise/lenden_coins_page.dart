import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../widgets/currency_display.dart';
import '../../widgets/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';
import '../wallet/widgets/wallet_auth_step.dart';

class LenDenCoinsPage extends StatefulWidget {
  final int coins;

  const LenDenCoinsPage({super.key, required this.coins});

  @override
  State<LenDenCoinsPage> createState() => _LenDenCoinsPageState();
}

class _LenDenCoinsPageState extends State<LenDenCoinsPage>
    with CurrencyDisplayMixin<LenDenCoinsPage> {
  bool _isFetchingHistory = false;
  bool _hasFetchedHistory = false;
  bool _isLoadingMore = false;
  bool _allLoaded = false;
  bool _sourcesExpanded = false;
  String? _historyError;
  int? _fetchedBalance;
  bool _isLoadingBalance = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _fetchBalance();
    loadCurrencies();
  }

  String _formatCoinMoney(int coins) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final pricing = session.coinPricingConfig;
    final coinValue = (pricing['coinValue'] as num? ?? 0.10).toDouble();
    final baseCurrency =
        (pricing['coinValueCurrency'] as String? ?? 'INR').toUpperCase();
    final amount = coins * coinValue;
    return formatCurrencyAmount(
      amount,
      from: baseCurrency,
      to: selectedCurrency,
      data: currencyData,
    );
  }

  Future<void> _fetchBalance() async {
    setState(() => _isLoadingBalance = true);
    try {
      final res = await ApiClient.get('/api/coins/history?limit=0');
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && mounted) {
        setState(() => _fetchedBalance = data['balance'] as int?);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingBalance = false);
    }
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _isFetchingHistory = true;
      _historyError = null;
    });

    try {
      final res = await ApiClient.get('/api/coins/history?limit=5');
      final data = jsonDecode(res.body);
      if (res.statusCode != 200) {
        final t = AppLocalizations.of(context).t;
        throw Exception(
            (data['error'] ?? t('failed_to_fetch_history_message'))
                .toString());
      }

      setState(() {
        _hasFetchedHistory = true;
        _allLoaded = false;
        _fetchedBalance = data['balance'] as int?;
        _summary = Map<String, dynamic>.from(data['summary'] ?? {});
        _entries = List<Map<String, dynamic>>.from(
          (data['entries'] ?? [])
              .map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } catch (e) {
      setState(() {
        _hasFetchedHistory = true;
        _historyError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isFetchingHistory = false);
    }
  }

  Future<void> _fetchAllHistory() async {
    setState(() { _isLoadingMore = true; _historyError = null; });
    try {
      final res = await ApiClient.get('/api/coins/history?limit=200');
      final data = jsonDecode(res.body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _allLoaded = true;
          _fetchedBalance = data['balance'] as int?;
          _summary = Map<String, dynamic>.from(data['summary'] ?? {});
          _entries = List<Map<String, dynamic>>.from(
            (data['entries'] ?? []).map((e) => Map<String, dynamic>.from(e)),
          );
        });
      } else {
        final err = (jsonDecode(res.body)['error'] ?? 'Failed to load remaining history').toString();
        setState(() => _historyError = err);
      }
    } catch (_) {
      if (mounted) setState(() => _historyError = 'Connection error loading remaining history.');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  int get _displayBalance => _fetchedBalance ?? widget.coins;

  Future<void> _showBuyCoinsSheet() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final pricing = session.coinPricingConfig;
    final coinValue = (pricing['coinValue'] as num? ?? 0.10).toDouble();
    final coinCurrency = (pricing['coinValueCurrency'] as String?) ?? 'INR';

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BuyCoinsSheet(
        coinValue: coinValue,
        coinCurrency: coinCurrency,
        displayCurrencyData: currencyData,
        initialDisplayCurrency: selectedCurrency,
      ),
    );

    if (result == null || !mounted) return;
    final newBal = result['newCoinBalance'];
    if (newBal != null) {
      setState(() => _fetchedBalance = (newBal as num).toInt());
      session.updateUserCoins((newBal as num).toInt());
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Bought ${result['coins']} coins for $coinCurrency ${result['totalCost']}!'),
      backgroundColor: const Color(0xFF2E7D32),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── date grouping ──────────────────────────────────────────────────────────

  String _getDateGroupKey(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final d = DateTime(date.year, date.month, date.day);
      if (d == today) return 'Today';
      if (d == yesterday) return 'Yesterday';
      return DateFormat('EEEE, MMM d').format(date);
    } catch (_) {
      return '';
    }
  }

  List<dynamic> get _groupedEntries {
    if (_entries.isEmpty) return [];
    final result = <dynamic>[];
    String? lastKey;
    for (final entry in _entries) {
      final key = _getDateGroupKey(entry['occurredAt']?.toString());
      if (key != lastKey) {
        result.add(key);
        lastKey = key;
      }
      result.add(entry);
    }
    return result;
  }

  // ── shared visual helpers ──────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      );

  Widget _buildSectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
      child: Row(children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
              color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(
          text.toUpperCase(),
          style: TextStyle(
              fontSize: context.sp(10),
              fontWeight: FontWeight.bold,
              color: AppColors.cyan,
              letterSpacing: 1.0),
        ),
      ]),
    );
  }

  Widget _buildMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: context.sp(11),
                        color: AppThemeColors.secondaryText(context),
                        letterSpacing: 0.2)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: context.sp(20),
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: context.sp(11),
                          color: AppThemeColors.mutedText(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewRemainingButton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: OutlinedButton.icon(
        onPressed: _isLoadingMore ? null : _fetchAllHistory,
        icon: _isLoadingMore
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(_isLoadingMore ? AppLocalizations.of(context).t('loading') : AppLocalizations.of(context).t('view_remaining_label')),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cyan),
          foregroundColor: AppColors.cyan,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildDateHeader(String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
              color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
              fontSize: context.sp(10),
              fontWeight: FontWeight.bold,
              color: AppColors.cyan,
              letterSpacing: 1.0),
        ),
      ]),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final grouped = _groupedEntries;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppThemeColors.primaryText(context),
        title: Text(
          t('lenden_coins_title'),
          style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
            onPressed: () async {
              await _fetchBalance();
              if (_hasFetchedHistory) await _fetchHistory();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: context.sh(160),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(top: context.sh(35)),
              child: RefreshIndicator(
                onRefresh: () async {
                  await _fetchBalance();
                  if (_hasFetchedHistory) await _fetchHistory();
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildBalanceCard()),
                    SliverToBoxAdapter(child: _buildBuyButton()),
                    SliverToBoxAdapter(child: _buildInfoSection()),
                    SliverToBoxAdapter(child: _buildFetchPanel()),
                    if (_hasFetchedHistory && _summary != null) ...[
                      SliverToBoxAdapter(child: _buildStatsSection()),
                      SliverToBoxAdapter(child: _buildSourcesSection()),
                    ],
                    if (_hasFetchedHistory) ...[
                      SliverToBoxAdapter(child: _buildHistorySectionHeader()),
                      if (_entries.isEmpty)
                        SliverToBoxAdapter(child: _buildEmptyHistory())
                      else
                        SliverList.builder(
                          itemCount: grouped.length,
                          itemBuilder: (context, index) {
                            final item = grouped[index];
                            if (item is String) return _buildDateHeader(item);
                            return _buildHistoryTile(
                                item as Map<String, dynamic>);
                          },
                        ),
                      if (!_allLoaded)
                        SliverToBoxAdapter(child: _buildViewRemainingButton()),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── balance card ───────────────────────────────────────────────────────────

  Widget _buildBalanceCard() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(t('lenden_coins_title')),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _isLoadingBalance
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 22),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          ),
                        )
                      : _buildMetric(
                          icon: Icons.monetization_on_rounded,
                          label: t('current_balance_label'),
                          value: '$_displayBalance',
                          color: Colors.amber,
                          subtitle: t('available_lenden_coins_label'),
                        ),
                ),
                VerticalDivider(
                    width: 1,
                    color:
                        AppThemeColors.border(context).withValues(alpha: 0.4)),
                Expanded(
                  child: _buildMetric(
                    icon: Icons.currency_exchange_rounded,
                    label: t('est_value_label'),
                    value: _isLoadingBalance
                        ? '...'
                        : _formatCoinMoney(_displayBalance),
                    color: Colors.teal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── buy button ─────────────────────────────────────────────────────────────

  Widget _buildBuyButton() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _showBuyCoinsSheet,
          icon: const Icon(Icons.shopping_cart_rounded),
          label: const Text('Buy Coins with Wallet'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4A017),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  // ── info section ───────────────────────────────────────────────────────────

  Widget _buildInfoSection() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(t('about_coins_label')),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          _buildInfoRow(
            icon: Icons.manage_search_rounded,
            color: AppColors.cyan,
            title: t('history_tracking_title'),
            subtitle: t('coin_history_lazy_load_message'),
          ),
          Divider(
              height: 1,
              indent: 66,
              color: AppThemeColors.border(context).withValues(alpha: 0.3)),
          _buildInfoRow(
            icon: Icons.account_tree_outlined,
            color: Colors.orange,
            title: t('tracked_sources_title'),
            subtitle: t('tracked_coin_sources_message'),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: context.sp(14),
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: context.sp(12),
                        color: AppThemeColors.secondaryText(context),
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── fetch panel ────────────────────────────────────────────────────────────

  Widget _buildFetchPanel() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(t('coin_history_label')),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _hasFetchedHistory
                      ? t('tap_below_latest_coin_trail_message')
                      : t('coin_history_not_fetched_automatically_message'),
                  style: TextStyle(
                      fontSize: context.sp(13),
                      color: AppThemeColors.secondaryText(context),
                      height: 1.45),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isFetchingHistory ? null : _fetchHistory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    icon: _isFetchingHistory
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : Icon(
                            _hasFetchedHistory ? Icons.refresh : Icons.download),
                    label: Text(
                      _isFetchingHistory
                          ? t('fetching_ellipsis_message')
                          : _hasFetchedHistory
                              ? t('refresh_history_label')
                              : t('fetch_history_label'),
                    ),
                  ),
                ),
                if (_historyError != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.error_rounded, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_historyError!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4))),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── stats section ──────────────────────────────────────────────────────────

  Widget _buildStatsSection() {
    final t = AppLocalizations.of(context).t;
    final totalEarned = (_summary?['totalEarned'] ?? 0) as num;
    final totalSpent = (_summary?['totalSpent'] ?? 0) as num;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(t('overview_label')),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetric(
                    icon: Icons.trending_up_rounded,
                    label: t('earned_label'),
                    value: '+${totalEarned.toInt()}',
                    color: Colors.green,
                  ),
                ),
                VerticalDivider(
                    width: 1,
                    color:
                        AppThemeColors.border(context).withValues(alpha: 0.4)),
                Expanded(
                  child: _buildMetric(
                    icon: Icons.trending_down_rounded,
                    label: t('spent_label'),
                    value: '-${totalSpent.toInt()}',
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── sources section ────────────────────────────────────────────────────────

  Widget _buildSourcesSection() {
    final t = AppLocalizations.of(context).t;
    final sources = List<Map<String, dynamic>>.from(_summary?['sources'] ?? []);
    if (sources.isEmpty) return const SizedBox.shrink();
    const kInitial = 3;
    final displayed = _sourcesExpanded ? sources : sources.take(kInitial).toList();
    final remaining = sources.length - kInitial;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(t('source_split_label')),
          Divider(height: 1, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          ...displayed.asMap().entries.map((e) => Column(children: [
                if (e.key > 0)
                  Divider(height: 1, indent: 66, color: AppThemeColors.border(context).withValues(alpha: 0.3)),
                _buildSourceRow(e.value),
              ])),
          if (!_sourcesExpanded && remaining > 0) ...[
            Divider(height: 1, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
            InkWell(
              onTap: () => setState(() => _sourcesExpanded = true),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.expand_more_rounded, color: AppColors.cyan, size: 18),
                  const SizedBox(width: 6),
                  Text('View $remaining more', style: TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600, fontSize: context.sp(13))),
                ]),
              ),
            ),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildSourceRow(Map<String, dynamic> source) {
    final t = AppLocalizations.of(context).t;
    final earned = (source['earned'] ?? 0) as num;
    final spent = (source['spent'] ?? 0) as num;
    final label = (source['label'] ?? t('source_label')).toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.account_tree_outlined,
              color: AppColors.cyan, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: context.sp(14),
                  color: AppThemeColors.primaryText(context))),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Text('+${earned.toInt()}',
              style: TextStyle(
                  fontSize: context.sp(12),
                  fontWeight: FontWeight.bold,
                  color: Colors.green)),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Text('-${spent.toInt()}',
              style: TextStyle(
                  fontSize: context.sp(12),
                  fontWeight: FontWeight.bold,
                  color: Colors.red)),
        ),
      ]),
    );
  }

  // ── history section header ─────────────────────────────────────────────────

  Widget _buildHistorySectionHeader() {
    final t = AppLocalizations.of(context).t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Container(
              width: 3,
              height: 13,
              decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 8),
            Text(
              t('history_label').toUpperCase(),
              style: TextStyle(
                  fontSize: context.sp(10),
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan,
                  letterSpacing: 1.0),
            ),
          ]),
          buildCurrencySelector(),
        ],
      ),
    );
  }

  // ── empty history ──────────────────────────────────────────────────────────

  Widget _buildEmptyHistory() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.monetization_on_outlined,
                  size: 40, color: AppColors.cyan.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).t('no_coin_history_title'),
              style: TextStyle(
                  fontSize: context.sp(18),
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context)),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).t('no_coin_history_subtitle'),
              style: TextStyle(color: AppThemeColors.mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }

  // ── history tile ───────────────────────────────────────────────────────────

  Widget _buildHistoryTile(Map<String, dynamic> entry) {
    final isEarned = (entry['direction'] ?? '') == 'earned';
    final color = isEarned ? Colors.green : Colors.red;
    final amount = (entry['coins'] ?? 0) as num;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isEarned
                    ? Icons.south_west_rounded
                    : Icons.north_east_rounded,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (entry['title'] ?? '').toString(),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: context.sp(14),
                              color: AppThemeColors.primaryText(context)),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '${isEarned ? '+' : '-'}${amount.toInt()}',
                          style: TextStyle(
                              fontSize: context.sp(11),
                              fontWeight: FontWeight.bold,
                              color: color),
                        ),
                      ),
                    ],
                  ),
                  if ((entry['description'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      (entry['description'] ?? '').toString(),
                      style: TextStyle(
                          fontSize: context.sp(12),
                          color: AppThemeColors.secondaryText(context)),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 11,
                          color: AppThemeColors.mutedText(context)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          _formatDate(entry['occurredAt'],
                              AppLocalizations.of(context).t),
                          style: TextStyle(
                              fontSize: context.sp(11),
                              color: AppThemeColors.mutedText(context)),
                        ),
                      ),
                      Text(
                        '≈ ${_formatCoinMoney(amount.toInt())}',
                        style: TextStyle(
                            fontSize: context.sp(11),
                            color: AppThemeColors.mutedText(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(dynamic rawDate, String Function(String) t) {
    if (rawDate == null) return t('unknown_time_message');
    final parsed = DateTime.tryParse(rawDate.toString());
    if (parsed == null) return rawDate.toString();
    final local = parsed.toLocal();
    final month = _monthName(local.month);
    final hour = local.hour == 0
        ? 12
        : local.hour > 12
            ? local.hour - 12
            : local.hour;
    final minute = local.minute.toString().padLeft(2, '0');
    final meridiem = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day} $month ${local.year}, $hour:$minute $meridiem';
  }

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[month - 1];
  }
}

// ---------------------------------------------------------------------------
// Buy-coins bottom sheet — owns its own TextEditingController so Flutter's
// normal dispose order handles the lifecycle: the sheet widget is disposed
// (and the controller cleaned up) before showModalBottomSheet's Future
// resolves, eliminating the "controller used after disposed" timing crash.
// SingleChildScrollView prevents the 99702-pixel RenderFlex overflow when
// the keyboard is open inside an isScrollControlled sheet.
// ---------------------------------------------------------------------------

class _BuyCoinsSheet extends StatefulWidget {
  final double coinValue;
  final String coinCurrency;
  final DisplayCurrencyData? displayCurrencyData;
  final String initialDisplayCurrency;

  const _BuyCoinsSheet({
    required this.coinValue,
    required this.coinCurrency,
    required this.displayCurrencyData,
    required this.initialDisplayCurrency,
  });

  @override
  State<_BuyCoinsSheet> createState() => _BuyCoinsSheetState();
}

class _BuyCoinsSheetState extends State<_BuyCoinsSheet>
    with CurrencyDisplayMixin<_BuyCoinsSheet> {
  late final TextEditingController _ctrl;
  bool _buying = false;
  int _step = 0; // 0 = amount form, 1 = wallet auth
  bool _hasPinSet = false;
  String? _authError;
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '10');
    loadCurrencies(
      seedData: widget.displayCurrencyData,
      seedCode: widget.initialDisplayCurrency,
    );
    _loadPinStatus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _hasPinSet = data['hasPin'] == true);
      }
    } catch (_) {}
  }

  int get _coins => int.tryParse(_ctrl.text.trim()) ?? 0;
  double get _baseCost => _coins * widget.coinValue;
  String get _displayCost => formatCurrencyAmount(
        _baseCost,
        from: widget.coinCurrency,
        to: selectedCurrency,
        data: currencyData,
      );
  String get _totalCost => _baseCost.toStringAsFixed(2);

  Future<void> _buy(String authField, String authCredential) async {
    if (_coins < 1) return;
    setState(() => _buying = true);
    try {
      final body = <String, dynamic>{'coinsToBuy': _coins};
      body[authField] = authCredential;
      final res = await ApiClient.post('/api/coins/buy-with-wallet', body: body);
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.of(context).pop(<String, dynamic>{
            'newCoinBalance': data['newCoinBalance'],
            'coins': _coins,
            'totalCost': _totalCost,
          });
        }
      } else {
        final err = (data['error'] ?? data['message'] ?? 'Purchase failed.').toString();
        if (mounted) setState(() => _authError = err);
      }
    } catch (_) {
      if (mounted) setState(() => _authError = AppLocalizations.of(context).t('connection_error_retry_message'));
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Widget _buildAuthStep() {
    final coins = _coins;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Purchase summary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFFFF8E1),
                      dark: const Color(0xFF2A2010)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.monetization_on_rounded,
                        color: Color(0xFFD4A017), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Buying $coins Coin${coins == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppThemeColors.primaryText(context)),
                    ),
                    Text(
                      '${widget.coinCurrency} $_totalCost',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppThemeColors.secondaryText(context)),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              WalletAuthStep(
                hasPinSet: _hasPinSet,
                paying: _buying,
                onAuthenticated: (authField, credential) {
                  setState(() => _authError = null);
                  _buy(authField, credential);
                },
                onBack: () => setState(() { _step = 0; _authError = null; }),
              ),
              if (_authError != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_authError!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4))),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_step == 1) return _buildAuthStep();

    final coins = _coins;
    final displayCost = _displayCost;
    final baseCost = '${widget.coinCurrency} ${_totalCost}';
    final showConversion =
        selectedCurrency.toUpperCase() != widget.coinCurrency.toUpperCase();

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: const Color(0xFFFFF8E1),
                          dark: const Color(0xFF2A2010)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.monetization_on_rounded,
                        color: Color(0xFFD4A017), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).t('buy_lenden_coins_title'),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        Text(
                          '1 coin = ${widget.coinCurrency} ${widget.coinValue.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppThemeColors.secondaryText(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              buildSheetCurrencySelector(),
              const SizedBox(height: 18),
              Text(
                AppLocalizations.of(context).t('how_many_coins_label'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppThemeColors.secondaryText(context),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
                decoration: InputDecoration(
                  suffixText: 'coins',
                  suffixStyle: TextStyle(
                    fontSize: 16,
                    color: AppThemeColors.secondaryText(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.cyan),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.cyan, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: (_) {
                  final c = int.tryParse(_ctrl.text.trim()) ?? 0;
                  setState(() {
                    _amountError = c > 10000
                        ? AppLocalizations.of(context).t('max_coins_per_purchase_error')
                        : null;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_amountError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_rounded, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_amountError!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                children: [10, 25, 50, 100, 200].map((n) {
                  return ActionChip(
                    label: Text('+$n'),
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12),
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.10),
                    side: const BorderSide(color: AppColors.cyan),
                    onPressed: () {
                      _ctrl.text = '$n';
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFEAF5FF),
                      dark: const Color(0xFF1B3A4A)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context).t('total_cost_label'),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColors.secondaryText(context),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayCost,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.cyan,
                          ),
                        ),
                        if (showConversion)
                          Text(
                            baseCost,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.mutedText(context),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final t = AppLocalizations.of(context).t;
                    if (coins < 1) {
                      setState(() => _amountError = t('enter_at_least_one_coin_error'));
                      return;
                    }
                    if (coins > 10000) {
                      setState(() => _amountError = t('max_coins_per_purchase_error'));
                      return;
                    }
                    setState(() { _amountError = null; _step = 1; });
                  },
                  icon: const Icon(Icons.lock_rounded),
                  label: Text('Buy $coins Coin${coins == 1 ? '' : 's'}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4A017),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
