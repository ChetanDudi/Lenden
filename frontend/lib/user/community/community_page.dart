import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../api_config.dart';
import 'create_community_page.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _joinCodeCtrl.dispose();
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

  Color _parseColor(dynamic c) {
    try {
      if (c is String && c.startsWith('#')) {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      }
    } catch (_) {}
    return AppColors.cyan;
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
            Container(width: 52, height: 52,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.link_rounded, color: AppColors.cyan, size: 26),
            ),
            const SizedBox(height: 14),
            Text('Join a Community', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
            const SizedBox(height: 6),
            Text('Enter the invite code shared by the community admin', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx))),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(ctx),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemeColors.border(ctx)),
              ),
              child: TextField(
                controller: _joinCodeCtrl,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 6, color: AppThemeColors.primaryText(ctx)),
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'ABC123',
                  hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx), letterSpacing: 6),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
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
                    } else {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(d['error'] ?? 'Failed to join'), backgroundColor: Colors.red));
                    }
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
                  }
                },
                child: const Text('Join Community', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Communities', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppThemeColors.cardBg(context),
        foregroundColor: AppThemeColors.primaryText(context),
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_rounded),
            tooltip: 'Join with code',
            onPressed: _joinWithCode,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.cyan,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Create', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () async {
          final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
          if (result != null) _load();
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _error != null
              ? _buildError()
              : _communities.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.cyan,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _communities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _buildCard(_communities[i]),
                      ),
                    ),
    );
  }

  Widget _buildError() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 56, height: 56,
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.error_outline, size: 28, color: Colors.red)),
      const SizedBox(height: 14),
      Text(_error!, style: TextStyle(color: AppThemeColors.secondaryText(context))),
      const SizedBox(height: 12),
      ElevatedButton(
        onPressed: _load,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: const Text('Retry'),
      ),
    ]));
  }

  Widget _buildEmpty() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 72, height: 72,
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.hub_rounded, size: 36, color: AppColors.cyan),
        ),
        const SizedBox(height: 20),
        Text('No Communities Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 8),
        Text('Organize multiple groups under one community — office, family, college, and more.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context), height: 1.5)),
        const SizedBox(height: 28),
        SizedBox(width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Create Community', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              onPressed: () async {
                final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
                if (result != null) _load();
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: BorderSide(color: AppThemeColors.border(context)),
              foregroundColor: AppThemeColors.primaryText(context)),
            icon: Icon(Icons.link_rounded, size: 18, color: AppThemeColors.secondaryText(context)),
            label: const Text('Join with Invite Code', style: TextStyle(fontWeight: FontWeight.w600)),
            onPressed: _joinWithCode,
          ),
        ),
      ]),
    ));
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final id = (c['_id'] ?? '').toString();
    final name = (c['name'] ?? 'Community').toString();
    final desc = (c['description'] ?? '').toString();
    final color = _parseColor(c['color']);
    final members = (c['members'] as List?)?.length ?? 0;
    final groups = (c['groups'] as List?)?.length ?? 0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final imgUrl = id.isNotEmpty ? '${ApiConfig.baseUrl}/api/communities/$id/image' : null;

    return GestureDetector(
      onTap: () {
        // TODO: navigate to community_detail_page
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community detail coming soon'), duration: Duration(seconds: 1)));
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // Avatar box — community color as bg tint
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(13),
                ),
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
                Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(context))),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(desc, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ])),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ]),
          ),
          Divider(height: 1, indent: 76, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(children: [
              _statRow(Icons.folder_shared_rounded, '$groups group${groups == 1 ? '' : 's'}'),
              const SizedBox(width: 20),
              _statRow(Icons.people_rounded, '$members member${members == 1 ? '' : 's'}'),
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
