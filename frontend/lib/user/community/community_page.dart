import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/wave_widget.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../api_config.dart';
import '../../session.dart';
import '../../l10n/app_localizations.dart';
import 'create_community_page.dart';
import 'community_detail_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({Key? key}) : super(key: key);

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  List<Map<String, dynamic>> _communities = [];
  bool _loading = true;
  String? _error;
  final _joinCodeCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  String _filter = 'all'; // all | admin | member

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _joinCodeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/communities');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => _communities = List<Map<String, dynamic>>.from(data['communities'] ?? []));
      } else {
        if (mounted) setState(() => _error = 'Failed to load communities');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final uid = Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString() ?? '';
    return _communities.where((c) {
      // search filter
      if (q.isNotEmpty) {
        final name = (c['name'] ?? '').toString().toLowerCase();
        final desc = (c['description'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !desc.contains(q)) return false;
      }
      // role filter
      if (_filter != 'all') {
        final members = (c['members'] as List?) ?? [];
        final me = members.firstWhere(
          (m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == uid,
          orElse: () => null,
        );
        final role = me?['role']?.toString() ?? 'member';
        if (_filter == 'admin' && role != 'admin') return false;
        if (_filter == 'member' && role == 'admin') return false;
      }
      return true;
    }).toList();
  }

  Color _parseColor(dynamic c) {
    try {
      if (c is String && c.startsWith('#')) {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      }
    } catch (_) {}
    return AppColors.cyan;
  }

  void _showSnack(String message, {bool isError = false, IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
            color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: isError ? Colors.red.shade700 : AppColors.cyan,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 2),
      elevation: 6,
    ));
  }

  Future<void> _joinWithCode() async {
    _joinCodeCtrl.clear();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Container(width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.link_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            Text(AppLocalizations.of(ctx).t('join_community_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
            const SizedBox(height: 6),
            Text(AppLocalizations.of(ctx).t('join_community_code_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx), height: 1.5)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(ctx),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4), width: 1.5),
              ),
              child: TextField(
                controller: _joinCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 10,
                  color: AppThemeColors.primaryText(ctx),
                ),
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: '• • • • • •',
                  hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx), letterSpacing: 10, fontSize: 20),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0,
                ),
                onPressed: () async {
                  final code = _joinCodeCtrl.text.trim().toUpperCase();
                  if (code.length < 4) return;
                  Navigator.pop(ctx);
                  try {
                    final res = await ApiClient.post('/api/communities/join', body: {'inviteCode': code});
                    final d = jsonDecode(res.body);
                    if (res.statusCode == 200) {
                      _joinCodeCtrl.clear();
                      _load();
                      _showSnack(AppLocalizations.of(context).t('joined_community_success'), icon: Icons.hub_rounded);
                    } else {
                      _showSnack(d['error'] ?? AppLocalizations.of(context).t('failed_to_join_community'), isError: true);
                    }
                  } catch (e) {
                    _showSnack(e.toString(), isError: true);
                  }
                },
                child: Text(AppLocalizations.of(ctx).t('join_community_btn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text(t('create'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
          if (result != null) {
            _load();
            _showSnack(t('community_created_success'), icon: Icons.hub_rounded);
          }
        },
      ),
      body: Stack(
        children: [
          // Top wave banner
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeeperTopWaveClipper(),
              child: Container(
                height: context.sh(70),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // Header row: back + title + join
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    t('communities_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      shadows: [Shadow(color: Colors.black26, blurRadius: 4)],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.link_rounded, color: Colors.white),
                  tooltip: 'Join with code',
                  onPressed: _joinWithCode,
                ),
              ]),
            ),
          ),
          // Content area
          Positioned(
            top: 80, left: 0, right: 0, bottom: 0,
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                : _error != null
                    ? _buildError()
                    : Column(children: [
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppThemeColors.cardBg(context),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppThemeColors.border(context)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 14),
                              decoration: InputDecoration(
                                hintText: t('search_communities_hint'),
                                hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 14),
                                prefixIcon: Icon(Icons.search_rounded, color: AppThemeColors.secondaryText(context), size: 20),
                                suffixIcon: _searchCtrl.text.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.close_rounded, color: AppThemeColors.secondaryText(context), size: 18),
                                        onPressed: () => _searchCtrl.clear(),
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                              ),
                            ),
                          ),
                        ),
                        // Filter chips
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Row(children: [
                            _filterChip('all', t('all'), Icons.apps_rounded),
                            const SizedBox(width: 8),
                            _filterChip('admin', t('role_admin_badge').replaceAll('★ ', ''), Icons.star_rounded),
                            const SizedBox(width: 8),
                            _filterChip('member', t('filter_member_label'), Icons.people_rounded),
                          ]),
                        ),
                        // List
                        Expanded(
                          child: _communities.isEmpty
                              ? _buildEmpty()
                              : _filtered.isEmpty
                                  ? _buildNoResults()
                                  : RefreshIndicator(
                                      onRefresh: _load,
                                      color: AppColors.cyan,
                                      child: ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                                        itemCount: _filtered.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                                        itemBuilder: (_, i) => _buildCard(_filtered[i]),
                                      ),
                                    ),
                        ),
                      ]),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label, IconData icon) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.cyan : AppThemeColors.border(context)),
          boxShadow: active ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? Colors.white : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppThemeColors.secondaryText(context))),
        ]),
      ),
    );
  }

  Widget _buildError() {
    final t = AppLocalizations.of(context).t;
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
          child: const Icon(Icons.wifi_off_rounded, size: 32, color: Colors.red)),
        const SizedBox(height: 16),
        Text(t('something_went_wrong'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 6),
        Text(_error!, textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.red, Color(0xFFEF4444)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ElevatedButton.icon(
            onPressed: _load,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
              elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
            label: Text(t('try_again'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    ));
  }

  Widget _buildEmpty() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.cyan.withValues(alpha: 0.15), AppColors.blue.withValues(alpha: 0.08)]),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.hub_rounded, size: 40, color: AppColors.cyan),
          ),
          const SizedBox(height: 20),
          Text(t('no_communities_title'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 8),
          Text(t('no_communities_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context), height: 1.6)),
          const SizedBox(height: 32),
          Container(width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(t('create_community_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
                if (result != null) { _load(); _showSnack(t('community_created_success'), icon: Icons.hub_rounded); }
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(color: AppThemeColors.border(context), width: 1.5),
                foregroundColor: AppThemeColors.primaryText(context)),
              icon: Icon(Icons.link_rounded, size: 18, color: AppThemeColors.secondaryText(context)),
              label: Text(t('join_with_invite_code_btn'), style: const TextStyle(fontWeight: FontWeight.w600)),
              onPressed: _joinWithCode,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildNoResults() {
    final t = AppLocalizations.of(context).t;
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(color: AppThemeColors.surfaceBg(context), borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppThemeColors.border(context))),
          child: Icon(Icons.search_off_rounded, size: 32, color: AppThemeColors.mutedText(context))),
        const SizedBox(height: 16),
        Text(t('no_results_found'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 6),
        Text(t('try_different_search_or_filter'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () { _searchCtrl.clear(); setState(() => _filter = 'all'); },
          icon: const Icon(Icons.refresh_rounded, size: 16, color: AppColors.cyan),
          label: Text(t('clear_filters_label'), style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w600)),
        ),
      ]),
    ));
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final id = (c['_id'] ?? '').toString();
    final name = (c['name'] ?? 'Community').toString();
    final desc = (c['description'] ?? '').toString();
    final color = _parseColor(c['color']);
    final members = (c['members'] as List?) ?? [];
    final groups = (c['groups'] as List?) ?? [];
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final imgUrl = id.isNotEmpty ? '${ApiConfig.baseUrl}/api/communities/$id/image' : null;
    final uid = Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString() ?? '';
    final me = members.firstWhere(
      (m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == uid,
      orElse: () => null,
    );
    final isAdmin = me?['role']?.toString() == 'admin';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CommunityDetailPage(communityId: id, initialData: c),
      )).then((_) => _load()),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(13)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: imgUrl != null
                      ? Image.network(imgUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(child: Text(initials,
                            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold))))
                      : Center(child: Text(initials,
                          style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(context)), overflow: TextOverflow.ellipsis)),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(AppLocalizations.of(context).t('role_admin_badge').replaceAll('★ ', ''),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: AppColors.cyan, letterSpacing: 0.3)),
                    ),
                  ],
                ]),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ])),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
          Divider(height: 1, indent: 76, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              _statRow(Icons.folder_shared_rounded, '${groups.length} group${groups.length == 1 ? '' : 's'}'),
              const SizedBox(width: 20),
              _statRow(Icons.people_rounded, '${members.length} member${members.length == 1 ? '' : 's'}'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statRow(IconData icon, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: AppThemeColors.secondaryText(context)),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w500)),
    ]);
  }
}
