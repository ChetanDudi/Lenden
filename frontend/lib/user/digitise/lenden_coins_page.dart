import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class LenDenCoinsPage extends StatefulWidget {
  final int coins;

  const LenDenCoinsPage({super.key, required this.coins});

  @override
  State<LenDenCoinsPage> createState() => _LenDenCoinsPageState();
}

class _LenDenCoinsPageState extends State<LenDenCoinsPage> {
  bool _isFetchingHistory = false;
  bool _hasFetchedHistory = false;
  String? _historyError;
  int? _fetchedBalance;
  bool _isLoadingBalance = true;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _fetchBalance();
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
      final res = await ApiClient.get('/api/coins/history?limit=80');
      final data = jsonDecode(res.body);
      if (res.statusCode != 200) {
        final t = AppLocalizations.of(context).t;
        throw Exception((data['error'] ?? t('failed_to_fetch_history_message')).toString());
      }

      setState(() {
        _hasFetchedHistory = true;
        _fetchedBalance = data['balance'] as int?;
        _summary = Map<String, dynamic>.from(data['summary'] ?? {});
        _entries = List<Map<String, dynamic>>.from(
          (data['entries'] ?? []).map((entry) => Map<String, dynamic>.from(entry)),
        );
      });
    } catch (e) {
      setState(() {
        _hasFetchedHistory = true;
        _historyError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingHistory = false;
        });
      }
    }
  }

  int get _displayBalance => _fetchedBalance ?? widget.coins;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('lenden_coins_title')),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, context.sh(70), 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBalanceCard(),
                  const SizedBox(height: 18),
                  _buildInfoCard(
                    title: t('history_tracking_title'),
                    icon: Icons.manage_search_rounded,
                    color: const Color(0xFFEAF4FF),
                    darkColor: const Color(0xFF15324A),
                    textColor: const Color(0xFF124E78),
                    darkTextColor: const Color(0xFFBFE3FF),
                    message: t('coin_history_lazy_load_message'),
                  ),
                  const SizedBox(height: 14),
                  _buildInfoCard(
                    title: t('tracked_sources_title'),
                    icon: Icons.account_tree_outlined,
                    color: const Color(0xFFFFF8E7),
                    darkColor: const Color(0xFF3A2E12),
                    textColor: const Color(0xFF7A4F01),
                    darkTextColor: const Color(0xFFFFD479),
                    message: t('tracked_coin_sources_message'),
                  ),
                  const SizedBox(height: 20),
                  _buildFetchPanel(),
                  const SizedBox(height: 20),
                  if (_hasFetchedHistory) ...[
                    _buildSummaryPanel(),
                    const SizedBox(height: 18),
                    _buildHistoryPanel(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    final t = AppLocalizations.of(context).t;
    return tricolorBorder(
      radius: 30,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            colors: [Color(0xFF5DA9FF), Color(0xFF8FD3FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.monetization_on,
                color: Colors.amber,
                size: 34,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('current_balance_label'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _isLoadingBalance
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.8,
                          ),
                        )
                      : Text(
                          '$_displayBalance',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                  const SizedBox(height: 4),
                  Text(
                    t('available_lenden_coins_label'),
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required Color darkColor,
    required Color textColor,
    required Color darkTextColor,
    required String message,
  }) {
    final resolvedColor =
        AppThemeColors.tinted(context, light: color, dark: darkColor);
    final resolvedTextColor = AppThemeColors.tinted(context,
        light: textColor, dark: darkTextColor);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(context,
                  light: Colors.white.withValues(alpha: 0.82),
                  dark: Colors.black.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: resolvedTextColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: resolvedTextColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: resolvedTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFetchPanel() {
    final t = AppLocalizations.of(context).t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: const Color(0xFFEAF4FF),
                      dark: const Color(0xFF15324A)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.history_toggle_off_rounded,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t('coin_history_label'),
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _hasFetchedHistory
                ? t('tap_below_latest_coin_trail_message')
                : t('coin_history_not_fetched_automatically_message'),
            style: TextStyle(
              fontSize: 13,
              color: AppThemeColors.secondaryText(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isFetchingHistory ? null : _fetchHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              icon: _isFetchingHistory
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_hasFetchedHistory ? Icons.refresh : Icons.download),
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
            const SizedBox(height: 12),
            Text(
              _historyError!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryPanel() {
    final t = AppLocalizations.of(context).t;
    final totalEarned = (_summary?['totalEarned'] ?? 0) as num;
    final totalSpent = (_summary?['totalSpent'] ?? 0) as num;
    final sources = List<Map<String, dynamic>>.from(_summary?['sources'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('overview_label'),
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: t('earned_label'),
                value: '+${totalEarned.toInt()}',
                accent: const Color(0xFF2E7D32),
                background: const Color(0xFFEAF8EC),
                icon: Icons.trending_up_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: t('spent_label'),
                value: '-${totalSpent.toInt()}',
                accent: const Color(0xFFC62828),
                background: const Color(0xFFFFEBEE),
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        tricolorBorder(
          radius: 26,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      t('source_split_label'),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppThemeColors.primaryText(context)),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right,
                        size: 18, color: AppThemeColors.mutedText(context)),
                  ],
                ),
                const SizedBox(height: 12),
                if (sources.isEmpty)
                  Text(
                    t('no_tracked_source_entries_message'),
                    style:
                        TextStyle(color: AppThemeColors.secondaryText(context)),
                  )
                else
                  SizedBox(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: sources.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) => _buildSourceChip(sources[i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required Color accent,
    required Color background,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(Map<String, dynamic> source) {
    final t = AppLocalizations.of(context).t;
    final earned = (source['earned'] ?? 0) as num;
    final spent = (source['spent'] ?? 0) as num;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF4F7FB), dark: const Color(0xFF233040)),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFD9E8F5), dark: const Color(0xFF35495C))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (source['label'] ?? t('source_label')).toString(),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppThemeColors.primaryText(context)),
          ),
          const SizedBox(height: 4),
          Text(
            '+${earned.toInt()}  /  -${spent.toInt()}',
            style: TextStyle(
              color: AppThemeColors.secondaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPanel() {
    final t = AppLocalizations.of(context).t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('history_label'),
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 12),
        if (_entries.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Text(
              t('no_tracked_coin_entries_message'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.secondaryText(context)),
            ),
          )
        else
          Column(
            children: _entries.map(_buildHistoryTile).toList(),
          ),
      ],
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> entry) {
    final t = AppLocalizations.of(context).t;
    final isEarned = (entry['direction'] ?? '') == 'earned';
    final accent = isEarned ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final bg = isEarned ? const Color(0xFFEAF8EC) : const Color(0xFFFFEBEE);
    final amount = (entry['coins'] ?? 0) as num;

    return tricolorBorder(
      margin: const EdgeInsets.only(bottom: 12),
      radius: 22,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isEarned ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (entry['title'] ?? '').toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (entry['description'] ?? '').toString(),
                    style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(entry['occurredAt'], t),
                    style: TextStyle(
                      color: AppThemeColors.mutedText(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${isEarned ? '+' : '-'}${amount.toInt()}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: accent,
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
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[month - 1];
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
