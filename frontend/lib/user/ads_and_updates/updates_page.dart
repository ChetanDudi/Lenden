import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class UserUpdatesPage extends StatefulWidget {
  const UserUpdatesPage({super.key});

  @override
  State<UserUpdatesPage> createState() => _UserUpdatesPageState();
}

class _UserUpdatesPageState extends State<UserUpdatesPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
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
    final t = AppLocalizations.of(context).t;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get('/api/app-updates');
      final data = _decodeJson(res.body);
      if (res.statusCode != 200) {
        throw Exception((data['error'] ?? t('failed_to_load_updates_message')).toString());
      }
      setState(() {
        _updates = List<Map<String, dynamic>>.from(
          (data['updates'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          t('app_updates_label'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
              label: Text(
                t('mark_all_read_label'),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Top wave — same clipper & colour as user dashboard
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: (MediaQuery.of(context).padding.top + kToolbarHeight) * 1.5,
                color: AppColors.cyan,
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              color: _sky,
              onRefresh: _loadUpdates,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 4, 16, 24),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 14),
                  _buildSearchCard(),
                  const SizedBox(height: 12),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: _sky),
                      ),
                    )
                  else if (_error != null)
                    _buildStateCard(_error!, Colors.redAccent)
                  else if (_filteredUpdates.isEmpty)
                    _buildStateCard(t('no_updates_matched_filter_message'), Colors.black54)
                  else
                    ..._filteredUpdates.map(_buildUpdateCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _sky.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0077B6), _sky],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('whats_new_label'),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppThemeColors.primaryText(context)),
                    ),
                    Text(
                      t('features_fixes_security_message'),
                      style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _statBox(_updates.length.toString(), t('total_label'), _sky),
              const SizedBox(width: 10),
              _statBox(_unreadCount.toString(), t('unread_label'),
                  _unreadCount > 0 ? Colors.redAccent : Colors.green),
              const SizedBox(width: 10),
              _statBox(_criticalCount.toString(), t('critical_label'),
                  _criticalCount > 0 ? Colors.orange : Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: AppThemeColors.primaryText(context)),
        decoration: InputDecoration(
          hintText: t('search_updates_hint'),
          filled: true,
          fillColor: AppThemeColors.cardBg(context),
          prefixIcon: const Icon(Icons.search, color: _sky),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final t = AppLocalizations.of(context).t;
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildFilterChip('all', t('all_label'), Icons.list_rounded),
          _buildFilterChip('unread', t('unread_label'), Icons.mark_email_unread_rounded),
          _buildFilterChip('critical', t('critical_label'), Icons.warning_amber_rounded),
          _buildFilterChip('feature', t('features_filter_label'), Icons.star_rounded),
          _buildFilterChip('security', t('security_filter_label'), Icons.security_rounded),
          _buildFilterChip('bug_fix', t('bug_fixes_filter_label'), Icons.bug_report_rounded),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
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
            color: selected ? Colors.white : AppThemeColors.primaryText(context),
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

  Widget _buildStateCard(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(
            color == Colors.redAccent ? Icons.error_outline : Icons.inbox_rounded,
            color: color,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final t = AppLocalizations.of(context).t;
    final pinned = update['pinned'] == true;
    final isRead = update['isRead'] == true;
    final importance = (update['importance'] ?? 'normal').toString();
    final category = (update['category'] ?? 'general').toString();
    final tags = ((update['tags'] as List?) ?? const [])
        .map((tag) => tag.toString())
        .where((tag) => tag.trim().isNotEmpty)
        .toList();

    final importanceColor = importance == 'critical'
        ? Colors.redAccent
        : importance == 'important'
            ? Colors.orange
            : _deepBlue;

    return GestureDetector(
      onTap: () => _markRead(update),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? AppThemeColors.cardBg(context) : const Color(0xFFF0FAFF),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2, right: 10),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: importanceColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _categoryIcon(category),
                      color: importanceColor,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      (update['title'] ?? '').toString(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isRead ? AppThemeColors.primaryText(context) : const Color(0xFF0B1F33),
                      ),
                    ),
                  ),
                  if (pinned) ...[
                    const SizedBox(width: 6),
                    _pill(t('pinned_label'), const Color(0xFF0E5A8A)),
                  ],
                  if (!isRead) ...[
                    const SizedBox(width: 6),
                    _pill(t('new_label'), _sky),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _infoTag(_categoryLabel(category, t), _sky),
                  _infoTag(_importanceLabel(importance, t), importanceColor),
                  if ((update['versionTag'] ?? '').toString().trim().isNotEmpty)
                    _infoTag('v${update['versionTag']}', _deepBlue),
                ],
              ),
              if ((update['summary'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  (update['summary'] ?? '').toString(),
                  style: const TextStyle(
                    color: Color(0xFF0077B6),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                (update['body'] ?? '').toString(),
                style: TextStyle(height: 1.5, color: isRead ? AppThemeColors.primaryText(context) : const Color(0xFF0B1F33), fontSize: 14),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: tags.map((tag) => _tagChip('#$tag')).toList(),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatDate(update['publishedAt'], t),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (!isRead)
                    GestureDetector(
                      onTap: () => _markRead(update),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _sky.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _sky.withValues(alpha: 0.30)),
                        ),
                        child: Text(
                          t('mark_read_label'),
                          style: const TextStyle(
                            color: _sky,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  String _categoryLabel(String category, String Function(String) t) {
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

  String _importanceLabel(String importance, String Function(String) t) {
    switch (importance) {
      case 'critical':
        return t('critical_label');
      case 'important':
        return t('important_label');
      default:
        return t('normal_label');
    }
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  Widget _infoTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _sky.withValues(alpha: 0.20)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: _deepBlue,
        ),
      ),
    );
  }

  String _formatDate(dynamic value, String Function(String) t) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return t('unknown_date_label');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => false;
}
