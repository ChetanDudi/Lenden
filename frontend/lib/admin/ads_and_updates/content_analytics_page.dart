import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class AdminContentAnalyticsPage extends StatefulWidget {
  const AdminContentAnalyticsPage({super.key});

  @override
  State<AdminContentAnalyticsPage> createState() =>
      _AdminContentAnalyticsPageState();
}

class _AdminContentAnalyticsPageState extends State<AdminContentAnalyticsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _topAds = [];
  List<Map<String, dynamic>> _topUpdates = [];
  List<Map<String, dynamic>> _moderationQueue = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiClient.get('/api/admin/content-analytics');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
            (data['error'] ?? 'Failed to load analytics').toString());
      }

      setState(() {
        _summary = Map<String, dynamic>.from(data['summary'] ?? {});
        _topAds = List<Map<String, dynamic>>.from(
          (data['topAds'] ?? []).map((item) => Map<String, dynamic>.from(item)),
        );
        _topUpdates = List<Map<String, dynamic>>.from(
          (data['topUpdates'] ?? [])
              .map((item) => Map<String, dynamic>.from(item)),
        );
        _moderationQueue = List<Map<String, dynamic>>.from(
          (data['moderationQueue'] ?? [])
              .map((item) => Map<String, dynamic>.from(item)),
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
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
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.cyan, Color(0xFF48CAE4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.iconOnWave(context)),
                      ),
                      Expanded(
                        child: Text(
                          t('content_analytics'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.iconOnWave(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loadAnalytics,
                        icon: Icon(Icons.refresh,
                            color: AppThemeColors.iconOnWave(context)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadAnalytics,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 100),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: AppColors.cyan,
                              ),
                            ),
                          )
                        else if (_error != null)
                          _buildMessageCard(_error!, true)
                        else ...[
                          _buildSummarySection(),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: t('top_ads'),
                            subtitle: t('top_ads_subtitle'),
                            child: _topAds.isEmpty
                                ? _buildEmpty(t('no_ad_analytics_yet'))
                                : Column(
                                    children:
                                        _topAds.map(_buildTopAdTile).toList(),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: t('top_updates'),
                            subtitle: t('top_updates_subtitle'),
                            child: _topUpdates.isEmpty
                                ? _buildEmpty(t('no_update_analytics_yet'))
                                : Column(
                                    children: _topUpdates
                                        .map(_buildTopUpdateTile)
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _buildSectionCard(
                            title: t('moderation_queue'),
                            subtitle: t('moderation_queue_subtitle'),
                            child: _moderationQueue.isEmpty
                                ? _buildEmpty(t('no_moderation_items_right_now'))
                                : Column(
                                    children: _moderationQueue
                                        .map(_buildModerationTile)
                                        .toList(),
                                  ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummarySection() {
    final t = AppLocalizations.of(context).t;
    final cards = [
      _summaryCard(t('ads'), '${_summary['totalAds'] ?? 0}', Icons.ondemand_video),
      _summaryCard(t('active_ads'), '${_summary['activeAds'] ?? 0}',
          Icons.play_circle_fill),
      _summaryCard(t('ad_views'), '${_summary['totalImpressions'] ?? 0}',
          Icons.remove_red_eye),
      _summaryCard(
          t('ad_ctr'), '${_summary['averageCtr'] ?? 0}%', Icons.ads_click),
      _summaryCard(t('reports'), '${_summary['totalReports'] ?? 0}', Icons.report),
      _summaryCard(t('updates_label'), '${_summary['totalUpdates'] ?? 0}',
          Icons.campaign_outlined),
      _summaryCard(t('published'), '${_summary['publishedUpdates'] ?? 0}',
          Icons.publish_outlined),
      _summaryCard(
          t('reads'), '${_summary['totalReads'] ?? 0}', Icons.visibility_outlined),
      _summaryCard(t('critical'), '${_summary['criticalUpdates'] ?? 0}',
          Icons.priority_high),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 24) / 3;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: cards
                .map(
                  (card) => SizedBox(
                    width: cardWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: card,
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget _summaryCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 110,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.cyan),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: AppThemeColors.secondaryText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTopAdTile(Map<String, dynamic> ad) {
    final t = AppLocalizations.of(context).t;
    final stats = Map<String, dynamic>.from((ad['stats'] ?? {}) as Map);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppThemeColors.tinted(context,
            light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A4A)),
        child: Icon(
          (ad['mediaKind'] ?? 'none').toString() == 'video'
              ? Icons.play_circle_outline
              : Icons.image_outlined,
          color: AppColors.cyan,
        ),
      ),
      title: Text(
        (ad['title'] ?? '').toString(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppThemeColors.primaryText(context),
        ),
      ),
      subtitle: Text(
        '${t('clicks_label')} ${stats['clicks'] ?? 0} • ${t('views_label')} ${stats['impressions'] ?? 0} • ${t('ctr_label')} ${stats['ctr'] ?? 0}%',
        style: TextStyle(color: AppThemeColors.secondaryText(context)),
      ),
      trailing: Text(
        '${stats['reports'] ?? 0} ${t('reports_label')}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppThemeColors.primaryText(context),
        ),
      ),
    );
  }

  Widget _buildTopUpdateTile(Map<String, dynamic> update) {
    final t = AppLocalizations.of(context).t;
    final stats = Map<String, dynamic>.from((update['stats'] ?? {}) as Map);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppThemeColors.tinted(context,
            light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A4A)),
        child: const Icon(Icons.campaign_outlined, color: AppColors.cyan),
      ),
      title: Text(
        (update['title'] ?? '').toString(),
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppThemeColors.primaryText(context),
        ),
      ),
      subtitle: Text(
        '${(update['status'] ?? 'published').toString()} • ${(update['importance'] ?? 'normal').toString()}',
        style: TextStyle(color: AppThemeColors.secondaryText(context)),
      ),
      trailing: Text(
        '${stats['readCount'] ?? 0} ${t('reads_label')}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: AppThemeColors.primaryText(context),
        ),
      ),
    );
  }

  Widget _buildModerationTile(Map<String, dynamic> ad) {
    final t = AppLocalizations.of(context).t;
    final stats = Map<String, dynamic>.from((ad['stats'] ?? {}) as Map);
    final moderation =
        Map<String, dynamic>.from((ad['moderation'] ?? {}) as Map);
    final reports = List<Map<String, dynamic>>.from(
      (moderation['recentReports'] ?? [])
          .map((item) => Map<String, dynamic>.from(item)),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF7FBFF), dark: const Color(0xFF1C2A33)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (ad['title'] ?? '').toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
              Text(
                '${stats['reports'] ?? 0} ${t('reports_label')}',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${t('hidden_label')} ${stats['hides'] ?? 0} ${t('times_label')} • ${t('audience')} ${(ad['audience'] ?? 'nonsubscribed').toString()}',
            style: TextStyle(
              color: AppThemeColors.secondaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reports.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...reports.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${(report['reason'] ?? '').toString().trim().isEmpty ? t('no_reason_provided') : report['reason']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: AppThemeColors.secondaryText(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageCard(String message, bool isError) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
            dark: isError ? const Color(0xFF3A2020) : const Color(0xFF1E3324)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.redAccent : Colors.green.shade800,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
