import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
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
  final bool initialShowStarredOnly;
  const CommunityPage({Key? key, this.initialShowStarredOnly = false}) : super(key: key);

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _communities = [];
  List<Map<String, dynamic>> _myInvites = [];
  Set<String> _starredIds = {};
  bool _loading = true;
  String? _error;
  final _joinCodeCtrl = TextEditingController();
  late TabController _tabController;

  // Feed state
  List<Map<String, dynamic>> _feedPosts = [];
  bool _feedLoading = false;
  bool _hasMoreFeed = false;
  bool _loadingMoreFeed = false;
  final _postCtrl = TextEditingController();
  bool _posting = false;

  // Filter state for communities tab
  String _communityFilter = 'all'; // all | mine | joined | starred

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (_tabController.index == 0 && _feedPosts.isEmpty) _loadFeed(); });
    if (widget.initialShowStarredOnly) {
      _communityFilter = 'starred';
      _tabController.index = 1; // jump to My Communities tab
    }
    _load();
    _loadMyInvites();
    _loadFeed();
  }

  @override
  void dispose() {
    _joinCodeCtrl.dispose();
    _tabController.dispose();
    _postCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFeed() async {
    if (_feedLoading) return;
    setState(() => _feedLoading = true);
    try {
      final res = await ApiClient.get('/api/communities/feed');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _feedPosts = List<Map<String, dynamic>>.from(data['posts'] ?? []);
          _hasMoreFeed = data['hasMore'] == true;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _feedLoading = false);
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_loadingMoreFeed || !_hasMoreFeed || _feedPosts.isEmpty) return;
    setState(() => _loadingMoreFeed = true);
    try {
      final before = Uri.encodeComponent(_feedPosts.last['createdAt']?.toString() ?? '');
      final res = await ApiClient.get('/api/communities/feed?before=$before');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final more = List<Map<String, dynamic>>.from(data['posts'] ?? []);
        setState(() {
          _feedPosts = [..._feedPosts, ...more];
          _hasMoreFeed = data['hasMore'] == true;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMoreFeed = false);
    }
  }

  Future<void> _submitPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty) { _showSnack(AppLocalizations.of(context).t('post_text_empty'), isError: true); return; }
    setState(() => _posting = true);
    try {
      if (_communities.isEmpty) return;
      final communityId = _communities[0]['_id'].toString();
      final res = await ApiClient.post('/api/communities/$communityId/posts', body: {'text': text});
      if (res.statusCode == 201 && mounted) {
        final data = jsonDecode(res.body);
        _postCtrl.clear();
        _showSnack(AppLocalizations.of(context).t('post_published'), icon: Icons.check_circle_rounded);
        if (data['post'] != null) {
          setState(() => _feedPosts = [Map<String, dynamic>.from(data['post']), ..._feedPosts]);
        } else {
          _loadFeed();
        }
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  String _communityIdOf(dynamic raw) {
    if (raw is Map) return (raw['_id'] ?? '').toString();
    return raw?.toString() ?? '';
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final postId = post['_id'].toString();
    final communityId = _communityIdOf(post['community']);
    final idx = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
    if (idx == -1) return;
    final wasLiked = _feedPosts[idx]['likedByMe'] == true;
    final prevCount = (_feedPosts[idx]['likesCount'] ?? 0) as int;
    setState(() {
      _feedPosts[idx] = {
        ..._feedPosts[idx],
        'likedByMe': !wasLiked,
        'likesCount': wasLiked ? prevCount - 1 : prevCount + 1,
      };
    });
    try {
      final res = await ApiClient.post('/api/communities/$communityId/posts/$postId/like', body: {});
      if (!mounted) return;
      final i = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
      if (i == -1) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _feedPosts[i] = {..._feedPosts[i], 'likedByMe': data['likedByMe'], 'likesCount': data['likesCount']};
        });
      } else {
        setState(() {
          _feedPosts[i] = {..._feedPosts[i], 'likedByMe': wasLiked, 'likesCount': prevCount};
        });
      }
    } catch (_) {
      if (!mounted) return;
      final i = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
      if (i != -1) setState(() => _feedPosts[i] = {..._feedPosts[i], 'likedByMe': wasLiked, 'likesCount': prevCount});
    }
  }

  Future<void> _deleteFeedPost(String postId, String communityId) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(t('delete_post_title'), style: TextStyle(color: AppThemeColors.primaryText(ctx))),
        content: Text(t('delete_post_confirm'), style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('delete'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final idx = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
    if (idx == -1) return;
    final removed = _feedPosts[idx];
    setState(() => _feedPosts.removeAt(idx));
    try {
      final res = await ApiClient.delete('/api/communities/$communityId/posts/$postId');
      if (res.statusCode != 200 && mounted) {
        setState(() => _feedPosts.insert(idx, removed));
        _showSnack(AppLocalizations.of(context).t('failed_to_delete_post'), isError: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _feedPosts.insert(idx, removed));
        _showSnack(AppLocalizations.of(context).t('failed_to_delete_post'), isError: true);
      }
    }
  }

  void _showFeedComments(Map<String, dynamic> post) {
    final postId = post['_id'].toString();
    final communityId = _communityIdOf(post['community']);
    final commentCtrl = TextEditingController();
    List<Map<String, dynamic>> comments = List<Map<String, dynamic>>.from(
      (post['comments'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)),
    );
    final session = Provider.of<SessionProvider>(context, listen: false);
    final userId = session.user?['_id']?.toString() ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        bool posting = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 36, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.border(ctx), borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(AppLocalizations.of(ctx).t('post_comments_title'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppThemeColors.primaryText(ctx))),
                ),
                Divider(height: 1, color: AppThemeColors.border(ctx)),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.45),
                  child: comments.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(AppLocalizations.of(ctx).t('no_comments_yet'), style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 13))))
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: comments.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.border(ctx), indent: 56),
                        itemBuilder: (_, i) {
                          final c = comments[i];
                          final cAuthor = c['author'] as Map<String, dynamic>? ?? {};
                          final cAuthorId = (cAuthor['_id'] ?? '').toString();
                          final cAuthorName = (cAuthor['name'] ?? cAuthor['username'] ?? 'Unknown').toString();
                          final cCreated = c['createdAt'] != null ? DateTime.tryParse(c['createdAt'].toString()) : null;
                          final cAgo = _timeAgo(cCreated);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _profileAvatar(cAuthorId, size: 30),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(cAuthorName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppThemeColors.primaryText(ctx))),
                                  const SizedBox(width: 6),
                                  Text(cAgo, style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(ctx))),
                                ]),
                                const SizedBox(height: 3),
                                Text((c['text'] ?? '').toString(), style: TextStyle(fontSize: 12.5, color: AppThemeColors.primaryText(ctx), height: 1.4)),
                              ])),
                              if (cAuthorId == userId)
                                GestureDetector(
                                  onTap: () async {
                                    final commentId = (c['_id'] ?? '').toString();
                                    try {
                                      final res = await ApiClient.delete('/api/communities/$communityId/posts/$postId/comments/$commentId');
                                      if (res.statusCode == 200) {
                                        setSheet(() => comments.removeAt(i));
                                        final pi = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
                                        if (pi != -1 && mounted) setState(() => _feedPosts[pi] = {..._feedPosts[pi], 'comments': comments});
                                      }
                                    } catch (_) {}
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(Icons.close_rounded, size: 14, color: AppThemeColors.mutedText(ctx)),
                                  ),
                                ),
                            ]),
                          );
                        }),
                ),
                Divider(height: 1, color: AppThemeColors.border(ctx)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(children: [
                    _profileAvatar(userId, size: 32),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: commentCtrl,
                        maxLines: 1, maxLength: 500,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(ctx).t('write_comment_hint'),
                          hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 12.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                          focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20)), borderSide: BorderSide(color: AppColors.cyan)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          counterText: '',
                        ),
                        style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ignore: dead_code
                    posting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                      : IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.send_rounded, color: AppColors.cyan, size: 20),
                          onPressed: () async {
                            final t = commentCtrl.text.trim();
                            if (t.isEmpty) return;
                            setSheet(() => posting = true);
                            try {
                              final res = await ApiClient.post(
                                '/api/communities/$communityId/posts/$postId/comments',
                                body: {'text': t},
                              );
                              if (res.statusCode == 201) {
                                final data = jsonDecode(res.body);
                                final newComment = Map<String, dynamic>.from(data['comment'] as Map);
                                commentCtrl.clear();
                                setSheet(() { comments = [...comments, newComment]; posting = false; });
                                final pi = _feedPosts.indexWhere((p) => p['_id'].toString() == postId);
                                if (pi != -1 && mounted) setState(() => _feedPosts[pi] = {..._feedPosts[pi], 'comments': comments});
                              } else {
                                setSheet(() => posting = false);
                              }
                            } catch (_) { setSheet(() => posting = false); }
                          },
                        ),
                  ]),
                ),
              ]),
            );
          },
        );
      },
    ).whenComplete(() => commentCtrl.dispose());
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
        _showSnack(accept ? AppLocalizations.of(context).t('joined_community_success') : AppLocalizations.of(context).t('invite_declined'),
          icon: accept ? Icons.hub_rounded : Icons.close_rounded);
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  Future<void> _toggleStar(String communityId) async {
    final wasStarred = _starredIds.contains(communityId);
    setState(() { wasStarred ? _starredIds.remove(communityId) : _starredIds.add(communityId); });
    try {
      final res = await ApiClient.post('/api/communities/$communityId/star', body: {});
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() { data['starred'] == true ? _starredIds.add(communityId) : _starredIds.remove(communityId); });
      } else {
        setState(() { wasStarred ? _starredIds.add(communityId) : _starredIds.remove(communityId); });
      }
    } catch (_) {
      if (mounted) setState(() { wasStarred ? _starredIds.add(communityId) : _starredIds.remove(communityId); });
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/communities');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final communities = List<Map<String, dynamic>>.from(data['communities'] ?? []);
        if (mounted) setState(() {
          _communities = communities;
          _starredIds = communities.where((c) => c['isStarred'] == true).map((c) => (c['_id'] ?? '').toString()).toSet();
        });
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
      body: Stack(children: [
        // Blue wave banner
        ClipPath(
          clipper: const DeeperTopWaveClipper(),
          child: Container(
            height: context.sh(90),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppThemeColors.waveGradient(context),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        SafeArea(
        child: Column(children: [
          // Header on wave
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: AppThemeColors.primaryText(context).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.hub_rounded, color: AppThemeColors.primaryText(context), size: 18),
              ),
              const SizedBox(width: 10),
              Text(t('communities_title'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.link_rounded, color: AppThemeColors.primaryText(context)),
                onPressed: _joinWithCode,
                tooltip: 'Join with code',
              ),
              IconButton(
                icon: Icon(Icons.add_circle_rounded, color: AppThemeColors.primaryText(context)),
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
                      Text('${_myInvites.length} ${_myInvites.length == 1 ? t('pending_invite_singular') : t('pending_invite_plural')}',
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
                        Text(t('invited_to_join'), style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
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
                            child: Text(t('decline_btn'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red)),
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
                            child: Text(t('accept_btn'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
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
                  Text(t('all_communities_label'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppThemeColors.primaryText(context))),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _tabController.animateTo(1),
                    child: Text(t('view_all_label'), style: const TextStyle(fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
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
                  Tab(text: t('my_feed_tab')),
                  Tab(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(t('my_communities_tab')),
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
      ]),
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
    final t = AppLocalizations.of(context).t;
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
            Text(t('community_feed_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(t('community_feed_subscribe_desc'),
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
                label: Text(t('upgrade_to_subscribe_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => _showSnack(t('subscribe_for_feed_snack')),
              ),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async { await _loadFeed(); },
      color: AppColors.cyan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // Compose box
          Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppThemeColors.border(context)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _profileAvatar(userId),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _postCtrl,
                    maxLines: 3, minLines: 1,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      hintText: t('feed_write_placeholder'),
                      hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(context))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(context))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.cyan)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      counterText: '',
                    ),
                    style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 13),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                  onPressed: _posting ? null : _submitPost,
                  child: _posting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(t('publish_post_btn'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          // Feed posts
          if (_feedLoading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.cyan)))
          else if (_feedPosts.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.forum_outlined, color: AppColors.cyan, size: 30)),
                const SizedBox(height: 14),
                Text(t('no_posts_yet'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 6),
                Text(t('be_first_to_post'), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
              ]),
            ))
          else ...[
            ..._feedPosts.map((p) => _buildPostCard(p)),
            if (_hasMoreFeed)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Center(
                  child: _loadingMoreFeed
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))
                    : TextButton(
                        onPressed: _loadMoreFeed,
                        child: Text(AppLocalizations.of(context).t('load_more_btn'), style: const TextStyle(color: AppColors.cyan, fontSize: 13)),
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> p) {
    final author = p['author'] as Map<String, dynamic>? ?? {};
    final communityRaw = p['community'];
    final community = communityRaw is Map<String, dynamic> ? communityRaw : <String, dynamic>{};
    final authorId = (author['_id'] ?? '').toString();
    final authorName = (author['name'] ?? author['email'] ?? 'Unknown').toString();
    final communityName = (community['name'] ?? '').toString();
    final communityId = _communityIdOf(communityRaw);
    final postId = (p['_id'] ?? '').toString();
    final text = (p['text'] ?? '').toString();
    final createdAt = p['createdAt'] != null ? DateTime.tryParse(p['createdAt'].toString()) : null;
    final ago = _timeAgo(createdAt);
    final session = Provider.of<SessionProvider>(context, listen: false);
    final userId = session.user?['_id']?.toString() ?? '';
    final isOwn = authorId == userId;
    final likedByMe = p['likedByMe'] == true;
    final likesCount = (p['likesCount'] ?? 0) as int;
    final commentCount = (p['comments'] as List? ?? []).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _profileAvatar(authorId),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(authorName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppThemeColors.primaryText(context))),
            if (communityName.isNotEmpty)
              Text(communityName, style: const TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.w500)),
          ])),
          Text(ago, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
          if (isOwn) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _deleteFeedPost(postId, communityId),
              child: Icon(Icons.delete_outline_rounded, size: 17, color: AppThemeColors.mutedText(context)),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        Text(text, style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context), height: 1.45)),
        const SizedBox(height: 12),
        Row(children: [
          GestureDetector(
            onTap: () => _toggleLike(p),
            child: Row(children: [
              Icon(likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: likedByMe ? Colors.red : AppThemeColors.mutedText(context), size: 18),
              if (likesCount > 0) ...[
                const SizedBox(width: 4),
                Text('$likesCount', style: TextStyle(fontSize: 12, color: likedByMe ? Colors.red : AppThemeColors.mutedText(context))),
              ],
            ]),
          ),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: () => _showFeedComments(p),
            child: Row(children: [
              Icon(Icons.chat_bubble_outline_rounded, color: AppThemeColors.mutedText(context), size: 16),
              if (commentCount > 0) ...[
                const SizedBox(width: 4),
                Text('$commentCount', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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
    final t = AppLocalizations.of(context).t;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final myId = session.user?['_id']?.toString() ?? '';

    String creatorId(Map<String, dynamic> c) {
      final cr = c['creator'];
      if (cr is Map) return (cr['_id'] ?? '').toString();
      return (cr ?? '').toString();
    }

    final filtered = _communities.where((c) {
      if (_communityFilter == 'mine') return creatorId(c) == myId;
      if (_communityFilter == 'joined') return creatorId(c) != myId;
      if (_communityFilter == 'starred') return _starredIds.contains((c['_id'] ?? '').toString());
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.cyan,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in [
                  ('all', t('filter_all')),
                  ('starred', '⭐ ${t('filter_starred')}'),
                  ('mine', t('filter_created_by_me')),
                  ('joined', t('filter_joined')),
                ]) ...[
                  GestureDetector(
                    onTap: () => setState(() => _communityFilter = f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _communityFilter == f.$1 ? AppColors.cyan : AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _communityFilter == f.$1 ? AppColors.cyan : AppThemeColors.border(context)),
                      ),
                      child: Text(f.$2, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _communityFilter == f.$1 ? Colors.white : AppThemeColors.primaryText(context),
                      )),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(child: _buildFilteredEmpty())
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < filtered.length - 1 ? 14 : 0),
                  child: _buildCard(filtered[i]),
                ),
                childCount: filtered.length,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildCard(Map<String, dynamic> c) {
    final t = AppLocalizations.of(context).t;
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
            // Star button
            Positioned(
              top: 10, right: 10,
              child: GestureDetector(
                onTap: () => _toggleStar(id),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _starredIds.contains(id) ? Icons.star_rounded : Icons.star_border_rounded,
                    color: _starredIds.contains(id) ? Colors.amber : Colors.white70,
                    size: 20,
                  ),
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
                    Text('$memberCount ${memberCount == 1 ? t('member_singular') : t('member_plural')}',
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
                    child: Text(t('view_community_btn'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildFilteredEmpty() {
    final t = AppLocalizations.of(context).t;
    if (_communityFilter == 'starred') {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72,
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.star_border_rounded, size: 36, color: Colors.amber)),
            const SizedBox(height: 18),
            Text(t('no_starred_communities_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(t('no_starred_communities_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.6)),
          ]),
        ),
      );
    }
    if (_communityFilter == 'mine') {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72,
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.add_circle_outline_rounded, size: 36, color: AppColors.cyan)),
            const SizedBox(height: 18),
            Text(t('no_created_communities_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(t('no_created_communities_desc'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.6)),
            const SizedBox(height: 24),
            Container(width: double.infinity,
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(14)),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text(t('create_community_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
                  if (result != null) { _load(); _showSnack(t('community_created_success'), icon: Icons.hub_rounded); }
                },
              ),
            ),
          ]),
        ),
      );
    }
    if (_communityFilter == 'joined') {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72,
              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.link_rounded, size: 36, color: AppColors.cyan)),
            const SizedBox(height: 18),
            Text(t('no_joined_communities_title'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(t('no_joined_communities_desc'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.6)),
            const SizedBox(height: 24),
            SizedBox(width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: AppColors.cyan, width: 1.5),
                  foregroundColor: AppColors.cyan),
                icon: const Icon(Icons.link_rounded, size: 18, color: AppColors.cyan),
                label: Text(t('join_with_invite_code_btn'), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.cyan)),
                onPressed: _joinWithCode,
              ),
            ),
          ]),
        ),
      );
    }
    return _buildEmpty();
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
