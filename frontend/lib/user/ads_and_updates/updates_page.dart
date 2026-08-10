import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';
import '../../widgets/search_tab_bar.dart';

class UserUpdatesPage extends StatefulWidget {
  const UserUpdatesPage({super.key});

  @override
  State<UserUpdatesPage> createState() => _UserUpdatesPageState();
}

class _UserUpdatesPageState extends State<UserUpdatesPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  bool _hasError = false;
  String _filter = 'all';
  List<Map<String, dynamic>> _updates = [];

  static const _sky = AppColors.cyan;
  static const _deepBlue = Color(0xFF0077B6);

  List<Map<String, dynamic>> get _filteredUpdates {
    final query = _searchController.text.trim().toLowerCase();
    return _updates.where((update) {
      if (_filter == 'unread' && update['isRead'] == true) return false;
      if (_filter == 'critical' && update['importance'] != 'critical') return false;
      if (_filter == 'feature' && update['category'] != 'feature') return false;
      if (_filter == 'security' && update['category'] != 'security') return false;
      if (_filter == 'bug_fix' && update['category'] != 'bug_fix') return false;

      if (query.isEmpty) return true;
      final haystack = [
        update['title'],
        update['summary'],
        update['body'],
        update['versionTag'],
        (update['tags'] as List?)?.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  int get _unreadCount =>
      _updates.where((update) => update['isRead'] != true).length;

  int get _criticalCount =>
      _updates.where((u) => u['importance'] == 'critical').length;

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadUpdates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _loadUpdates() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      final res = await ApiClient.get('/api/app-updates');
      if (!mounted) return;
      final data = _decodeJson(res.body);
      if (res.statusCode != 200) {
        setState(() { _loading = false; _hasError = true; });
        return;
      }
      setState(() {
        _updates = List<Map<String, dynamic>>.from(
          (data['updates'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _markRead(Map<String, dynamic> update) async {
    final updateId = update['_id']?.toString();
    if (updateId == null || updateId.isEmpty || update['isRead'] == true) return;

    try {
      await ApiClient.post('/api/app-updates/$updateId/read');
      if (!mounted) return;
      setState(() {
        update['isRead'] = true;
        update['readAt'] = DateTime.now().toIso8601String();
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.post('/api/app-updates/read-all');
      if (!mounted) return;
      setState(() {
        final now = DateTime.now().toIso8601String();
        for (final update in _updates) {
          update['isRead'] = true;
          update['readAt'] = now;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: context.sh(170),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ── Header row ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('app_updates_label'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert,
                            color: AppThemeColors.primaryText(context)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        onSelected: (value) {
                          if (value == 'mark_read') _markAllRead();
                          if (value == 'refresh') _loadUpdates();
                        },
                        itemBuilder: (_) => [
                          if (_unreadCount > 0)
                            PopupMenuItem(
                              value: 'mark_read',
                              child: Row(children: [
                                const Icon(Icons.done_all,
                                    color: AppColors.cyan, size: 20),
                                const SizedBox(width: 10),
                                Text(t('mark_all_read_label')),
                              ]),
                            ),
                          PopupMenuItem(
                            value: 'refresh',
                            child: Row(children: [
                              const Icon(Icons.refresh_rounded,
                                  color: Colors.orange, size: 20),
                              const SizedBox(width: 10),
                              Text(t('refresh_label')),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Summary card ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildSummaryCard(),
                ),

                const SizedBox(height: 16),

                // ── Scrollable body ──────────────────────────────────────
                Expanded(
                  child: RefreshIndicator(
                    color: _sky,
                    onRefresh: _loadUpdates,
                    child: ListView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        _buildSearchCard(),
                        const SizedBox(height: 12),
                        _buildFilterRow(),
                        const SizedBox(height: 16),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Center(
                              child:
                                  CircularProgressIndicator(color: _sky),
                            ),
                          )
                        else if (_hasError)
                          _buildErrorState()
                        else if (_filteredUpdates.isEmpty)
                          _buildEmptyState()
                        else
                          ..._filteredUpdates.map(_buildUpdateCard),
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

  // ── Summary / stats card (mirrors notifications' _buildSummaryCard) ──────

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatTile(
              title: t('total_label'),
              value: '${_updates.length}',
              color: _sky,
              icon: Icons.system_update_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: t('unread_label'),
              value: '$_unreadCount',
              color: _unreadCount > 0 ? Colors.redAccent : Colors.green,
              icon: Icons.mark_email_unread_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: t('critical_label'),
              value: '$_criticalCount',
              color:
                  _criticalCount > 0 ? Colors.orange : Colors.green,
              icon: Icons.warning_amber_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeColors.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search card ──────────────────────────────────────────────────────────

  Widget _buildSearchCard() {
    return AppSearchBar(
      controller: _searchController,
      hintText: t('search_updates_hint'),
      onChanged: (v) {
        setState(() {});
      },
      margin: EdgeInsets.zero,
    );
  }

  // ── Filter chips ─────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip(
              'all', t('all_label'), Icons.list_rounded),
          _buildFilterChip('unread', t('unread_label'),
              Icons.mark_email_unread_rounded),
          _buildFilterChip('critical', t('critical_label'),
              Icons.warning_amber_rounded),
          _buildFilterChip('feature', t('features_filter_label'),
              Icons.star_rounded),
          _buildFilterChip('security', t('security_filter_label'),
              Icons.security_rounded),
          _buildFilterChip('bug_fix', t('bug_fixes_filter_label'),
              Icons.bug_report_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String value, String label, IconData icon) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        child: FilterChip(
          avatar: Icon(
            icon,
            size: 16,
            color: selected ? Colors.white : _sky,
          ),
          label: Text(label),
          selected: selected,
          onSelected: (_) => setState(() => _filter = value),
          selectedColor: _sky,
          backgroundColor: AppThemeColors.cardBg(context),
          labelStyle: TextStyle(
            color: selected
                ? Colors.white
                : AppThemeColors.primaryText(context),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          side: BorderSide(
            color: selected ? _sky : _sky.withValues(alpha: 0.25),
          ),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }

  // ── Error state (mirrors notifications page _hasError block) ─────────────

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 56,
                  color: AppThemeColors.secondaryText(context)),
              const SizedBox(height: 16),
              Text(
                t('no_internet_connection_title'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                t('check_connection_and_retry_message'),
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(context)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadUpdates,
                icon: const Icon(Icons.refresh,
                    color: Colors.white),
                label: Text(t('retry_label'),
                    style:
                        const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Empty state (mirrors notifications page empty-tab block) ─────────────

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 72,
              color: AppThemeColors.divider(context),
            ),
            const SizedBox(height: 14),
            Text(
              t('no_updates_matched_filter_message'),
              style: TextStyle(
                  fontSize: 16,
                  color: AppThemeColors.secondaryText(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Update card ──────────────────────────────────────────────────────────

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final pinned = update['pinned'] == true;
    final isRead = update['isRead'] == true;
    final importance = (update['importance'] ?? 'normal').toString();
    final category = (update['category'] ?? 'general').toString();
    final title = (update['title'] ?? '').toString();
    final summary = (update['summary'] ?? '').toString().trim();
    final body = (update['body'] ?? '').toString().trim();
    final versionTag = (update['versionTag'] ?? '').toString().trim();
    final tags = ((update['tags'] as List?) ?? const [])
        .map((tag) => tag.toString())
        .where((tag) => tag.trim().isNotEmpty)
        .toList();

    final importanceColor = importance == 'critical'
        ? const Color(0xFFD32F2F)
        : importance == 'important'
            ? const Color(0xFFE65100)
            : _deepBlue;

    return GestureDetector(
      onTap: () => _markRead(update),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: AppColors.tricolorGradient,
          boxShadow: [
            BoxShadow(
              color: importanceColor.withValues(alpha: isRead ? 0.05 : 0.13),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Left accent strip ───────────────────────────────
                  Container(
                    width: 5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          importanceColor,
                          importanceColor.withValues(alpha: 0.45),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // ── Card content ─────────────────────────────────────
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: icon badge + title + unread dot
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      importanceColor.withValues(alpha: 0.18),
                                      importanceColor.withValues(alpha: 0.06),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _categoryIcon(category),
                                  color: importanceColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppThemeColors
                                                  .primaryText(context),
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                        if (pinned) ...[
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.push_pin_rounded,
                                            size: 15,
                                            color: const Color(0xFF0E5A8A),
                                          ),
                                        ],
                                        if (!isRead) ...[
                                          const SizedBox(width: 7),
                                          Container(
                                            width: 9,
                                            height: 9,
                                            decoration: const BoxDecoration(
                                              color: AppColors.cyan,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Meta chips
                                    Wrap(
                                      spacing: 5,
                                      runSpacing: 4,
                                      children: [
                                        _metaChip(
                                          _categoryLabel(category),
                                          _sky,
                                          icon: _categoryIcon(category),
                                        ),
                                        _metaChip(
                                          _importanceLabel(importance),
                                          importanceColor,
                                        ),
                                        if (versionTag.isNotEmpty)
                                          _versionChip(versionTag),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Summary blockquote
                          if (summary.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: importanceColor.withValues(alpha: 0.07),
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                  bottomLeft: Radius.circular(4),
                                  topLeft: Radius.circular(4),
                                ),
                                border: Border(
                                  left: BorderSide(
                                      color: importanceColor, width: 3.5),
                                ),
                              ),
                              child: Text(
                                summary,
                                style: TextStyle(
                                  color: importanceColor.withValues(
                                      alpha: AppThemeColors.isDark(context)
                                          ? 0.9
                                          : 1.0),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],

                          // Body text
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Text(
                              body,
                              style: TextStyle(
                                height: 1.5,
                                color: AppThemeColors.secondaryText(context),
                                fontSize: 13.5,
                              ),
                            ),
                          ],

                          // Tags
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 5,
                              children: tags
                                  .map((tag) => _tagChip('#$tag'))
                                  .toList(),
                            ),
                          ],

                          // Footer: date + mark-read button
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (update['lastEditedAt'] != null) ...[
                                Icon(Icons.edit_rounded,
                                    size: 12,
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.85)),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'Edited ${_formatDateTime(update['lastEditedAt'])}',
                                    style: const TextStyle(
                                      color: Color(0xFFF59E0B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => _showEditHistorySheet(context, update),
                                  child: Icon(Icons.history_rounded,
                                      size: 15,
                                      color: _sky.withValues(alpha: 0.75)),
                                ),
                              ] else ...[
                                Icon(Icons.access_time_rounded,
                                    size: 12,
                                    color: AppThemeColors.mutedText(context)
                                        .withValues(alpha: 0.7)),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDate(update['publishedAt']),
                                  style: TextStyle(
                                    color: AppThemeColors.mutedText(context)
                                        .withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const Spacer(),
                              if (!isRead)
                                GestureDetector(
                                  onTap: () => _markRead(update),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _sky.withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                          color:
                                              _sky.withValues(alpha: 0.30)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_rounded,
                                            size: 13, color: _sky),
                                        const SizedBox(width: 4),
                                        Text(
                                          t('mark_read_label'),
                                          style: const TextStyle(
                                            color: _sky,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
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

  Widget _metaChip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _versionChip(String version) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _deepBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _deepBlue.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.code_rounded,
              size: 10,
              color: _deepBlue.withValues(
                  alpha: AppThemeColors.isDark(context) ? 0.8 : 1.0)),
          const SizedBox(width: 3),
          Text(
            'v$version',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _deepBlue.withValues(
                  alpha: AppThemeColors.isDark(context) ? 0.8 : 1.0),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'feature':
        return Icons.star_rounded;
      case 'security':
        return Icons.security_rounded;
      case 'bug_fix':
        return Icons.bug_report_rounded;
      case 'maintenance':
        return Icons.build_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'bug_fix':
        return t('bug_fix_label');
      case 'feature':
        return t('feature_label');
      case 'security':
        return t('security_category_label');
      case 'maintenance':
        return t('maintenance_label');
      case 'general':
        return t('general_label');
      default:
        return category[0].toUpperCase() + category.substring(1);
    }
  }

  String _importanceLabel(String importance) {
    switch (importance) {
      case 'critical':
        return t('critical_label');
      case 'important':
        return t('important_label');
      default:
        return t('normal_label');
    }
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _sky.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _sky.withValues(alpha: 0.20)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: AppThemeColors.isDark(context)
              ? _sky
              : _deepBlue,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final date =
        DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return t('unknown_date_label');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDateTime(dynamic value) {
    final date =
        DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return t('unknown_date_label');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}, $h:$m';
  }

  // Reconstruct the full version timeline from editHistory + current doc.
  // editHistory[i] = content BEFORE edit i+1, editedAt = when edit i+1 happened.
  // So:
  //   versions[0]   = original  (content=editHistory[0],  date=publishedAt)
  //   versions[1]   = after edit1 (content=editHistory[1], date=editHistory[0].editedAt)
  //   versions[N]   = current   (content=doc fields,       date=lastEditedAt)
  List<Map<String, dynamic>> _buildVersionTimeline(Map<String, dynamic> update) {
    final rawHistory = ((update['editHistory'] as List?) ?? [])
        .cast<Map<String, dynamic>>()
        .toList();
    final versions = <Map<String, dynamic>>[];

    if (rawHistory.isEmpty) {
      // Never edited — single entry: the current doc
      versions.add({
        'label': 'Published',
        'isCurrent': true,
        'date': update['publishedAt'],
        ...{
          for (final k in ['title', 'body', 'summary', 'versionTag',
              'category', 'importance', 'tags'])
            k: update[k],
        },
      });
      return versions;
    }

    // Version 0: original — content from editHistory[0], date from publishedAt
    versions.add({
      'label': 'Original',
      'isCurrent': false,
      'date': update['publishedAt'],
      ...{
        for (final k in ['title', 'body', 'summary', 'versionTag',
            'category', 'importance', 'tags'])
          k: rawHistory[0][k],
      },
    });

    // Versions 1..N-1: intermediate edits
    // version i content = rawHistory[i], date = rawHistory[i-1].editedAt
    for (int i = 1; i < rawHistory.length; i++) {
      versions.add({
        'label': 'Edit $i',
        'isCurrent': false,
        'date': rawHistory[i - 1]['editedAt'],
        ...{
          for (final k in ['title', 'body', 'summary', 'versionTag',
              'category', 'importance', 'tags'])
            k: rawHistory[i][k],
        },
      });
    }

    // Final (current) version: date = lastEditedAt (= rawHistory.last.editedAt)
    versions.add({
      'label': 'Latest',
      'isCurrent': true,
      'date': update['lastEditedAt'],
      ...{
        for (final k in ['title', 'body', 'summary', 'versionTag',
            'category', 'importance', 'tags'])
          k: update[k],
      },
    });

    return versions;
  }

  void _showEditHistorySheet(
      BuildContext context, Map<String, dynamic> update) {
    // Newest first for the sheet
    final versions = _buildVersionTimeline(update).reversed.toList();
    final totalVersions = versions.length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.70,
          minChildSize: 0.40,
          maxChildSize: 0.95,
          expand: false,
          builder: (sheetContext, scrollController) {
            final isDark = AppThemeColors.isDark(sheetContext);
            return Container(
              decoration: BoxDecoration(
                color: AppThemeColors.scaffoldBg(sheetContext),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // ── Header ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      children: [
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppThemeColors.divider(sheetContext),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _sky.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.history_rounded,
                                  size: 18, color: _sky),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Version History',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: AppThemeColors.primaryText(
                                        sheetContext),
                                  ),
                                ),
                                Text(
                                  '$totalVersions version${totalVersions == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        AppThemeColors.mutedText(sheetContext),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Divider(
                            color: AppThemeColors.divider(sheetContext),
                            height: 1),
                      ],
                    ),
                  ),
                  // ── Version cards ──
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                      itemCount: versions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, index) {
                        final ver = versions[index];
                        final isCurrent = ver['isCurrent'] == true;
                        final label = (ver['label'] ?? '').toString();
                        final vTitle = (ver['title'] ?? '').toString();
                        final vSummary =
                            (ver['summary'] ?? '').toString().trim();
                        final vBody = (ver['body'] ?? '').toString().trim();
                        final vVersionTag =
                            (ver['versionTag'] ?? '').toString().trim();
                        final vCategory =
                            (ver['category'] ?? 'general').toString();
                        final vImportance =
                            (ver['importance'] ?? 'normal').toString();
                        final vTags = ((ver['tags'] as List?) ?? [])
                            .map((t) => t.toString())
                            .where((t) => t.trim().isNotEmpty)
                            .toList();

                        final accentColor = isCurrent
                            ? _sky
                            : vImportance == 'critical'
                                ? const Color(0xFFD32F2F)
                                : vImportance == 'important'
                                    ? const Color(0xFFE65100)
                                    : _deepBlue;

                        final labelBg = isCurrent
                            ? _sky.withValues(
                                alpha: isDark ? 0.18 : 0.10)
                            : label == 'Original'
                                ? const Color(0xFF22C55E)
                                    .withValues(alpha: isDark ? 0.18 : 0.10)
                                : const Color(0xFFF59E0B)
                                    .withValues(alpha: isDark ? 0.18 : 0.10);
                        final labelColor = isCurrent
                            ? _sky
                            : label == 'Original'
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFF59E0B);

                        return Container(
                          decoration: BoxDecoration(
                            color: AppThemeColors.cardBg(ctx),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrent
                                  ? _sky.withValues(alpha: 0.35)
                                  : AppThemeColors.divider(ctx),
                              width: isCurrent ? 1.5 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  // Accent strip
                                  Container(
                                    width: 4,
                                    color:
                                        accentColor.withValues(alpha: 0.65),
                                  ),
                                  // Content
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 12, 12, 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Row: label + date
                                          Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: labelBg,
                                                  borderRadius:
                                                      BorderRadius.circular(7),
                                                ),
                                                child: Text(
                                                  label,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: labelColor,
                                                  ),
                                                ),
                                              ),
                                              const Spacer(),
                                              Icon(
                                                isCurrent
                                                    ? Icons.star_rounded
                                                    : Icons.access_time_rounded,
                                                size: 11,
                                                color: AppThemeColors.mutedText(
                                                    ctx),
                                              ),
                                              const SizedBox(width: 3),
                                              Text(
                                                _formatDateTime(ver['date']),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: AppThemeColors
                                                      .mutedText(ctx),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 9),
                                          // Title
                                          Text(
                                            vTitle,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.5,
                                              color: AppThemeColors.primaryText(
                                                  ctx),
                                            ),
                                          ),
                                          // Version tag
                                          if (vVersionTag.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(Icons.code_rounded,
                                                    size: 12,
                                                    color: _sky
                                                        .withValues(alpha: 0.8)),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'v$vVersionTag',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: _sky,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          // Chips: category + importance
                                          const SizedBox(height: 7),
                                          Wrap(
                                            spacing: 5,
                                            runSpacing: 4,
                                            children: [
                                              _metaChip(
                                                vCategory.replaceAll('_', ' '),
                                                isDark
                                                    ? const Color(0xFF334155)
                                                    : const Color(0xFFE2E8F0),
                                              ),
                                              _metaChip(
                                                vImportance,
                                                vImportance == 'critical'
                                                    ? const Color(0xFFD32F2F)
                                                        .withValues(alpha: 0.18)
                                                    : vImportance == 'important'
                                                        ? const Color(0xFFE65100)
                                                            .withValues(alpha: 0.15)
                                                        : isDark
                                                            ? const Color(
                                                                0xFF1E3A4A)
                                                            : const Color(
                                                                0xFFDCF5EC),
                                                icon: vImportance == 'critical'
                                                    ? Icons.warning_amber_rounded
                                                    : vImportance == 'important'
                                                        ? Icons.priority_high
                                                        : Icons.check_circle_outline,
                                              ),
                                            ],
                                          ),
                                          // Summary
                                          if (vSummary.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      8, 6, 8, 6),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  left: BorderSide(
                                                    color: accentColor
                                                        .withValues(alpha: 0.5),
                                                    width: 3,
                                                  ),
                                                ),
                                                color: accentColor.withValues(
                                                    alpha: isDark ? 0.06 : 0.04),
                                              ),
                                              child: Text(
                                                vSummary,
                                                style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 12,
                                                  color: AppThemeColors
                                                      .secondaryText(ctx),
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                          ],
                                          // Body
                                          if (vBody.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              vBody,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                height: 1.5,
                                                color: AppThemeColors
                                                    .secondaryText(ctx),
                                              ),
                                            ),
                                          ],
                                          // Tags
                                          if (vTags.isNotEmpty) ...[
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 5,
                                              runSpacing: 4,
                                              children: vTags
                                                  .map((tag) => Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 7,
                                                                vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: _deepBlue
                                                              .withValues(
                                                                  alpha: 0.08),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(6),
                                                          border: Border.all(
                                                            color: _deepBlue
                                                                .withValues(
                                                                    alpha: 0.20),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '#$tag',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: AppThemeColors
                                                                .secondaryText(
                                                                    ctx),
                                                          ),
                                                        ),
                                                      ))
                                                  .toList(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
