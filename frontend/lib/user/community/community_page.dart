import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
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

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _myInvites = [];
  bool _loading = true;
  String? _error;
  final _joinCodeCtrl = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _loadMyInvites();
  }

  @override
  void dispose() {
    _joinCodeCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMyInvites() async {
    try {
      final res = await ApiClient.get('/api/communities/my-invites');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _myInvites = List<Map<String, dynamic>>.from(data['invites'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _respondToInvite(String communityId, bool accept) async {
    try {
      final path = accept
          ? '/api/communities/$communityId/invites/accept'
          : '/api/communities/$communityId/invites/decline';
      final res = accept ? await ApiClient.post(path) : await ApiClient.delete(path);
      if (res.statusCode == 200) {
        _loadMyInvites();
        if (accept) _load();
        _showSnack(accept ? 'Joined community!' : 'Invite declined',
          icon: accept ? Icons.hub_rounded : Icons.close_rounded);
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
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
            Text(AppLocalizations.of(ctx).t('join_community_title'),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
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
                  fontSize: 28, fontWeight: FontWeight.bold,
                  letterSpacing: 10, color: AppThemeColors.primaryText(ctx),
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
                child: Text(AppLocalizations.of(ctx).t('join_community_btn'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.hub_rounded, color: AppColors.cyan, size: 18),
              ),
              const SizedBox(width: 10),
              Text(t('communities_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.link_rounded, color: AppColors.cyan),
                onPressed: _joinWithCode,
                tooltip: 'Join with code',
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: AppColors.cyan),
                onPressed: () async {
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
                  if (result != null) { _load(); _showSnack(t('community_created_success'), icon: Icons.hub_rounded); }
                },
                tooltip: 'Create community',
              ),
            ]),
          ),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_error != null)
            Expanded(child: errorStateWidget(context, _error!, _load))
          else ...[
            // Pending invites strip
            if (_myInvites.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.mail_rounded, size: 13, color: Colors.amber),
                      const SizedBox(width: 5),
                      Text('${_myInvites.length} pending invite${_myInvites.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.amber)),
                    ]),
                  ),
                ]),
              ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                itemCount: _myInvites.length,
                itemBuilder: (_, i) {
                  final inv = _myInvites[i];
                  final cId = (inv['communityId'] ?? '').toString();
                  final cName = (inv['name'] ?? 'Community').toString();
                  final cColor = _parseColor(inv['color']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: cColor.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: cColor.withValues(alpha: 0.4)),
                        ),
                        child: Center(child: Text(
                          cName.isNotEmpty ? cName[0].toUpperCase() : 'C',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: cColor),
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                            color: AppThemeColors.primaryText(context))),
                        Text('Invited to join', style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                      ])),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: () => _respondToInvite(cId, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppThemeColors.surfaceBg(context),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppThemeColors.border(context)),
                            ),
                            child: const Text('Decline', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _respondToInvite(cId, true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text('Accept', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ),
                      ]),
                    ]),
                  );
                },
              ),
            ],

            // "All communities" horizontal circle strip
            if (_communities.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: Row(children: [
                  Text('All communities', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(context))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _tabController.animateTo(1),
                    child: const Text('View all', style: TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: _communities.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _buildCircleAvatar(_communities[i]),
                ),
              ),
            ],

            // Tab bar
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F2E33) : const Color(0xFFE0F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.cyan,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                indicator: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(10)),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                padding: const EdgeInsets.all(3),
                tabs: [
                  const Tab(text: 'My feed'),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('My communities'),
                    if (_communities.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(10)),
                        child: Text('${_communities.length}',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ])),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFeedTab(),
                  _buildMyCommunitiesTab(),
                ],
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildCircleAvatar(Map<String, dynamic> c) {
    final id = (c['_id'] ?? '').toString();
    final name = (c['name'] ?? '').toString();
    final color = _parseColor(c['color']);
    final imgUrl = '${ApiConfig.baseUrl}/api/communities/$id/image';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CommunityDetailPage(communityId: id, initialData: c),
      )).then((_) => _load()),
      child: Column(children: [
        Container(
          width: 58, height: 58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.5),
          ),
          child: ClipOval(
            child: Image.network(imgUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: color,
                child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))))),
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: 64,
          child: Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }

  Widget _buildFeedTab() {
    if (_communities.isEmpty) return _buildEmpty();
    final session = Provider.of<SessionProvider>(context, listen: false);
    final hasAccess = session.hasFeature('community_feed');
    final userId = session.user?['_id']?.toString() ?? '';

    if (!hasAccess) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.lock_rounded, color: AppColors.cyan, size: 34),
            ),
            const SizedBox(height: 20),
            Text('Community Feed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text('Subscribe to post and view community\nupdates in the feed.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                ),
                icon: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                label: const Text('Upgrade to Subscribe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => _showSnack('Subscribe to access Community Feed'),
              ),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.cyan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppThemeColors.border(context)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _profileAvatar(userId),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _showSnack('Community feed coming soon!'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppThemeColors.border(context)),
                      ),
                      child: Text('Write your post here',
                        style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                  onPressed: () => _showSnack('Community feed coming soon!'),
                  child: const Text('Publish Post', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 32),
          Center(child: Column(children: [
            Container(width: 64, height: 64,
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.forum_outlined, color: AppColors.cyan, size: 30)),
            const SizedBox(height: 14),
            Text('Community feed coming soon',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 6),
            Text('Post updates and connect with your\ncommunity members.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
          ])),
        ],
      ),
    );
  }

  Widget _profileAvatar(String userId, {double size = 38}) {
    if (userId.isEmpty) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, color: AppColors.cyan, size: size * 0.5),
      );
    }
    return ClipOval(
      child: Image.network(
        '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size,
          decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(Icons.person_rounded, color: AppColors.cyan, size: size * 0.5),
        ),
      ),
    );
  }

  Widget _buildMyCommunitiesTab() {
    if (_communities.isEmpty) return _buildEmpty();
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.cyan,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        itemCount: _communities.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _buildCard(_communities[i]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final id = (c['_id'] ?? '').toString();
    final name = (c['name'] ?? 'Community').toString();
    final memberCount = (c['members'] as List?)?.length ?? 0;
    final color = _parseColor(c['color']);
    final imgUrl = '${ApiConfig.baseUrl}/api/communities/$id/image';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => CommunityDetailPage(communityId: id, initialData: c),
      )).then((_) => _load()),
      child: Container(
        height: 185,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [
            // Background image (backend redirects to keyword default when no custom image)
            Image.network(imgUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, Color.lerp(color, Colors.black, 0.35)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              )),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.80)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 6)])),
                  const SizedBox(height: 4),
                  if ((c['description'] ?? '').toString().isNotEmpty) ...[
                    Text(
                      (c['description'] ?? '').toString(),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(children: [
                    const Icon(Icons.people_rounded, color: Colors.white70, size: 14),
                    const SizedBox(width: 5),
                    Text('$memberCount member${memberCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => CommunityDetailPage(communityId: id, initialData: c),
                    )).then((_) => _load()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('View Community →', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 80, height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.cyan.withValues(alpha: 0.15), AppColors.cyan.withValues(alpha: 0.05)]),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.hub_rounded, size: 40, color: AppColors.cyan)),
          const SizedBox(height: 20),
          Text(t('no_communities_title'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 8),
          Text(t('no_communities_desc'), textAlign: TextAlign.center,
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
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(t('create_community_btn'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
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
                side: const BorderSide(color: AppColors.cyan, width: 1.5),
                foregroundColor: AppColors.cyan),
              icon: const Icon(Icons.link_rounded, size: 18, color: AppColors.cyan),
              label: Text(t('join_with_invite_code_btn'),
                style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.cyan)),
              onPressed: _joinWithCode,
            ),
          ),
        ]),
      ),
    );
  }
}
