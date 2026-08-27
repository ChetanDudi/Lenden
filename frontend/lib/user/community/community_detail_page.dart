import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/image_picker_utils.dart';
import '../../widgets/app_colors.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/community_helpers.dart';
import '../../api_config.dart';
import '../../session.dart';
import '../../l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import '../../utils/share_utils.dart';
import '../transaction/group_transactions/group_detail_page.dart';

class CommunityDetailPage extends StatefulWidget {
  final String communityId;
  final Map<String, dynamic>? initialData;

  const CommunityDetailPage({required this.communityId, this.initialData, super.key});

  @override
  State<CommunityDetailPage> createState() => _CommunityDetailPageState();
}

class _CommunityDetailPageState extends State<CommunityDetailPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _community = {};
  bool _loading = true;
  String? _error;
  double _totalBalance = 0;
  double _netBalance = 0;
  List<Map<String, dynamic>> _groupBalances = [];
  bool _loadingBalance = false;

  // Members selection (bulk remove)
  bool _memberSelectMode = false;
  final Set<String> _selectedMemberIds = {};

  // Feed
  List<Map<String, dynamic>> _posts = [];
  bool _feedLoading = false;
  bool _hasMorePosts = false;
  bool _loadingMorePosts = false;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    if (widget.initialData != null) _community = widget.initialData!;
    _load();
    _loadPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    if (_feedLoading) return;
    setState(() => _feedLoading = true);
    try {
      final res = await ApiClient.get('/api/communities/${widget.communityId}/posts');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          _posts = List<Map<String, dynamic>>.from(data['posts'] ?? []);
          _hasMorePosts = data['hasMore'] == true;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _feedLoading = false);
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMorePosts || !_hasMorePosts || _posts.isEmpty) return;
    setState(() => _loadingMorePosts = true);
    try {
      final before = Uri.encodeComponent(_posts.last['createdAt']?.toString() ?? '');
      final res = await ApiClient.get('/api/communities/${widget.communityId}/posts?before=$before');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final more = List<Map<String, dynamic>>.from(data['posts'] ?? []);
        setState(() {
          _posts = [..._posts, ...more];
          _hasMorePosts = data['hasMore'] == true;
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMorePosts = false);
    }
  }

  Future<void> _submitPost(Map<String, dynamic> body) async {
    setState(() => _posting = true);
    try {
      final res = await ApiClient.post('/api/communities/${widget.communityId}/posts', body: body);
      if (res.statusCode == 201 && mounted) {
        final data = jsonDecode(res.body);
        _showSnack(AppLocalizations.of(context).t('post_published'), icon: Icons.check_circle_rounded);
        if (data['post'] != null) {
          setState(() => _posts = [Map<String, dynamic>.from(data['post']), ..._posts]);
        } else {
          _loadPosts();
        }
      } else if (mounted) {
        final d = jsonDecode(res.body);
        _showSnack(d['error'] ?? 'Failed to post', isError: true);
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _votePoll(String postId, String optionId, bool wasVotedOnTarget) async {
    final idx = _posts.indexWhere((p) => p['_id'].toString() == postId);
    if (idx == -1) return;
    try {
      final res = await ApiClient.post(
        '/api/communities/${widget.communityId}/posts/$postId/vote',
        body: {'optionId': optionId},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final i = _posts.indexWhere((p) => p['_id'].toString() == postId);
        if (i == -1) return;
        final updatedOptions = (data['options'] as List).map((o) => Map<String, dynamic>.from(o as Map)).toList();
        final existing = List<Map<String, dynamic>>.from(_posts[i]['poll']['options']);
        for (int j = 0; j < existing.length; j++) {
          final match = updatedOptions.firstWhere((o) => o['_id'].toString() == existing[j]['_id'].toString(), orElse: () => <String, dynamic>{});
          if (match.isNotEmpty) {
            existing[j] = {...existing[j], ...match};
          }
        }
        setState(() {
          _posts[i] = {
            ..._posts[i],
            'poll': {...(_posts[i]['poll'] as Map), 'options': existing, 'totalVotes': data['totalVotes']},
          };
        });
      }
    } catch (_) {}
  }

  Future<void> _pinPost(String postId, bool pin) async {
    try {
      final res = await ApiClient.patch(
        '/api/communities/${widget.communityId}/posts/$postId',
        body: {'isPinned': pin},
      );
      if (res.statusCode == 200 && mounted) {
        final updated = Map<String, dynamic>.from(jsonDecode(res.body)['post'] as Map);
        setState(() {
          if (pin) {
            for (int i = 0; i < _posts.length; i++) {
              if (_posts[i]['isPinned'] == true) _posts[i] = {..._posts[i], 'isPinned': false};
            }
          }
          final idx = _posts.indexWhere((p) => p['_id'].toString() == postId);
          if (idx != -1) _posts[idx] = updated;
          if (pin && idx > 0) {
            final pinned = _posts.removeAt(idx);
            _posts.insert(0, pinned);
          }
        });
        _showSnack(pin ? 'Post pinned' : 'Post unpinned', icon: Icons.push_pin_rounded);
      }
    } catch (_) {}
  }

  void _showEditPostSheet(Map<String, dynamic> post) {
    final editCtrl = TextEditingController(text: (post['text'] ?? '').toString());
    bool saving = false;
    final postId = post['_id'].toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 14),
              Text('Edit Post', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppThemeColors.primaryText(ctx))),
              const SizedBox(height: 14),
              TextField(
                controller: editCtrl,
                maxLines: 5, minLines: 2, maxLength: 1000,
                style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Edit your post…',
                  hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13)),
                  onPressed: saving ? null : () async {
                    final newText = editCtrl.text.trim();
                    if (newText.isEmpty) return;
                    setSheet(() => saving = true);
                    try {
                      final res = await ApiClient.patch(
                        '/api/communities/${widget.communityId}/posts/$postId',
                        body: {'text': newText},
                      );
                      if (res.statusCode == 200 && mounted) {
                        final updated = Map<String, dynamic>.from(jsonDecode(res.body)['post'] as Map);
                        final idx = _posts.indexWhere((p) => p['_id'].toString() == postId);
                        if (idx != -1) setState(() => _posts[idx] = updated);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } else {
                        setSheet(() => saving = false);
                      }
                    } catch (_) { setSheet(() => saving = false); }
                  },
                  child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() => editCtrl.dispose());
  }

  void _showNewPostSheet(Color color) {
    String selectedType = 'text';
    final textCtrl = TextEditingController();
    DateTime? dueDate;
    final amountCtrl = TextEditingController();
    final List<TextEditingController> pollCtrls = [TextEditingController(), TextEditingController()];
    bool posting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final types = <String, Map<String, dynamic>>{
            'text': {'label': 'Text', 'icon': Icons.notes_rounded, 'color': AppColors.cyan},
            if (_isAdmin) 'announcement': {'label': 'Announce', 'icon': Icons.campaign_rounded, 'color': const Color(0xFFFF9800)},
            'reminder': {'label': 'Reminder', 'icon': Icons.alarm_rounded, 'color': const Color(0xFF8B5CF6)},
            'poll': {'label': 'Poll', 'icon': Icons.poll_rounded, 'color': const Color(0xFF10B981)},
          };

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 14),

                  // Type selector chips
                  SizedBox(
                    height: 38,
                    child: ListView(scrollDirection: Axis.horizontal, children: types.entries.map((e) {
                      final sel = selectedType == e.key;
                      final tc = e.value['color'] as Color;
                      return GestureDetector(
                        onTap: () => setSheet(() => selectedType = e.key),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: sel ? tc : AppThemeColors.surfaceBg(ctx),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sel ? tc : AppThemeColors.border(ctx)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(e.value['icon'] as IconData, size: 14, color: sel ? Colors.white : tc),
                            const SizedBox(width: 5),
                            Text(e.value['label'] as String,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                                color: sel ? Colors.white : AppThemeColors.primaryText(ctx))),
                          ]),
                        ),
                      );
                    }).toList()),
                  ),
                  const SizedBox(height: 14),

                  // Announcement notice
                  if (selectedType == 'announcement') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.campaign_rounded, color: Color(0xFFFF9800), size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text('Announcements are pinnable and visible at the top of the feed.',
                          style: TextStyle(fontSize: 11.5, color: AppThemeColors.secondaryText(ctx)))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Text field (always shown)
                  TextField(
                    controller: textCtrl,
                    maxLines: selectedType == 'poll' ? 2 : 4,
                    minLines: 2,
                    maxLength: 1000,
                    style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 13),
                    decoration: InputDecoration(
                      hintText: selectedType == 'reminder'
                        ? 'Describe what needs to be paid…'
                        : selectedType == 'poll'
                          ? 'What are you deciding on?'
                          : selectedType == 'announcement'
                            ? 'Write your announcement…'
                            : 'Share something with the community…',
                      hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: types[selectedType]!['color'] as Color)),
                      contentPadding: const EdgeInsets.all(12),
                      counterText: '',
                    ),
                  ),

                  // Reminder extras
                  if (selectedType == 'reminder') ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: dueDate ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) setSheet(() => dueDate = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppThemeColors.surfaceBg(ctx),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: dueDate != null
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
                                : AppThemeColors.border(ctx)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF8B5CF6)),
                              const SizedBox(width: 8),
                              Text(dueDate != null
                                ? 'Due: ${dueDate!.day}/${dueDate!.month}/${dueDate!.year}'
                                : 'Due date (optional)',
                                style: TextStyle(fontSize: 13, color: dueDate != null
                                  ? AppThemeColors.primaryText(ctx) : AppThemeColors.mutedText(ctx))),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Amount (₹)',
                            hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                            prefixText: '₹ ',
                            prefixStyle: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                      ),
                    ]),
                  ],

                  // Poll options
                  if (selectedType == 'poll') ...[
                    const SizedBox(height: 12),
                    ...List.generate(pollCtrls.length, (i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Expanded(
                          child: TextField(
                            controller: pollCtrls[i],
                            maxLength: 200,
                            style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 13),
                            decoration: InputDecoration(
                              hintText: 'Option ${i + 1}',
                              hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppThemeColors.border(ctx))),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              counterText: '',
                            ),
                          ),
                        ),
                        if (i >= 2) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setSheet(() => pollCtrls.removeAt(i)),
                            child: const Icon(Icons.remove_circle_outline_rounded, color: Colors.red, size: 22),
                          ),
                        ],
                      ]),
                    )),
                    if (pollCtrls.length < 6)
                      GestureDetector(
                        onTap: () => setSheet(() => pollCtrls.add(TextEditingController())),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF10B981), size: 18),
                            const SizedBox(width: 6),
                            Text('Add option', style: TextStyle(color: AppThemeColors.secondaryText(ctx), fontSize: 13)),
                          ]),
                        ),
                      ),
                  ],

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: types[selectedType]!['color'] as Color,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: posting ? null : () async {
                        final text = textCtrl.text.trim();
                        if (text.isEmpty) return;
                        if (selectedType == 'poll') {
                          final opts = pollCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                          if (opts.length < 2) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Add at least 2 poll options')));
                            return;
                          }
                        }
                        setSheet(() => posting = true);
                        final body = <String, dynamic>{'text': text, 'type': selectedType};
                        if (selectedType == 'reminder') {
                          if (dueDate != null) body['dueDate'] = dueDate!.toIso8601String();
                          final amt = double.tryParse(amountCtrl.text.trim());
                          if (amt != null && amt > 0) body['amount'] = amt;
                        }
                        if (selectedType == 'poll') {
                          body['pollOptions'] = pollCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await _submitPost(body);
                      },
                      child: posting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text('Post', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      textCtrl.dispose();
      amountCtrl.dispose();
      for (final c in pollCtrls) c.dispose();
    });
  }

  Future<void> _toggleLike(Map<String, dynamic> post) async {
    final postId = post['_id'].toString();
    final idx = _posts.indexWhere((p) => p['_id'].toString() == postId);
    if (idx == -1) return;
    final wasLiked = _posts[idx]['likedByMe'] == true;
    final prevCount = (_posts[idx]['likesCount'] ?? 0) as int;
    setState(() {
      _posts[idx] = {
        ..._posts[idx],
        'likedByMe': !wasLiked,
        'likesCount': wasLiked ? prevCount - 1 : prevCount + 1,
      };
    });
    try {
      final res = await ApiClient.post('/api/communities/${widget.communityId}/posts/$postId/like', body: {});
      if (!mounted) return;
      final i = _posts.indexWhere((p) => p['_id'].toString() == postId);
      if (i == -1) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _posts[i] = {..._posts[i], 'likedByMe': data['likedByMe'], 'likesCount': data['likesCount']};
        });
      } else {
        setState(() {
          _posts[i] = {..._posts[i], 'likedByMe': wasLiked, 'likesCount': prevCount};
        });
      }
    } catch (_) {
      if (!mounted) return;
      final i = _posts.indexWhere((p) => p['_id'].toString() == postId);
      if (i != -1) setState(() => _posts[i] = {..._posts[i], 'likedByMe': wasLiked, 'likesCount': prevCount});
    }
  }

  Future<void> _deletePost(String postId) async {
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
    final idx = _posts.indexWhere((p) => p['_id'].toString() == postId);
    if (idx == -1) return;
    final removed = _posts[idx];
    setState(() => _posts.removeAt(idx));
    try {
      final res = await ApiClient.delete('/api/communities/${widget.communityId}/posts/$postId');
      if (res.statusCode != 200 && mounted) {
        setState(() => _posts.insert(idx, removed));
        _showSnack(AppLocalizations.of(context).t('failed_to_delete_post'), isError: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _posts.insert(idx, removed));
        _showSnack(AppLocalizations.of(context).t('failed_to_delete_post'), isError: true);
      }
    }
  }

  void _showComments(Map<String, dynamic> post, Color color) {
    final postId = post['_id'].toString();
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
                        final cDiff = cCreated != null ? DateTime.now().difference(cCreated) : null;
                        final cAgo = cDiff == null ? '' : cDiff.inMinutes < 1 ? 'just now' : cDiff.inMinutes < 60 ? '${cDiff.inMinutes}m ago' : cDiff.inHours < 24 ? '${cDiff.inHours}h ago' : '${cDiff.inDays}d ago';
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _profileAvatar(cAuthorId, size: 30, color: color),
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
                                    final res = await ApiClient.delete('/api/communities/${widget.communityId}/posts/$postId/comments/$commentId');
                                    if (res.statusCode == 200) {
                                      setSheet(() => comments.removeAt(i));
                                      final pi = _posts.indexWhere((p) => p['_id'].toString() == postId);
                                      if (pi != -1 && mounted) setState(() => _posts[pi] = {..._posts[pi], 'comments': comments});
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
                  _profileAvatar(userId, size: 32, color: color),
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
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: color)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        counterText: '',
                      ),
                      style: TextStyle(color: AppThemeColors.primaryText(ctx), fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // ignore: dead_code
                  posting
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.send_rounded, color: color, size: 20),
                        onPressed: () async {
                          final t = commentCtrl.text.trim();
                          if (t.isEmpty) return;
                          setSheet(() => posting = true);
                          try {
                            final res = await ApiClient.post(
                              '/api/communities/${widget.communityId}/posts/$postId/comments',
                              body: {'text': t},
                            );
                            if (res.statusCode == 201) {
                              final data = jsonDecode(res.body);
                              final newComment = Map<String, dynamic>.from(data['comment'] as Map);
                              commentCtrl.clear();
                              setSheet(() { comments = [...comments, newComment]; posting = false; });
                              final pi = _posts.indexWhere((p) => p['_id'].toString() == postId);
                              if (pi != -1 && mounted) setState(() => _posts[pi] = {..._posts[pi], 'comments': comments});
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/communities/${widget.communityId}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() { _community = data['community']; _loading = false; });
        _loadBalance();
      } else {
        if (mounted) setState(() { _error = AppLocalizations.of(context).t('failed_to_load_community'); _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadBalance() async {
    setState(() => _loadingBalance = true);
    try {
      final res = await ApiClient.get('/api/communities/${widget.communityId}/balance');
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        if (mounted) setState(() {
          _totalBalance = (d['totalSplits'] ?? 0).toDouble();
          _netBalance = (d['netBalance'] ?? 0).toDouble();
          _groupBalances = List<Map<String, dynamic>>.from(d['groups'] ?? []);
        });
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBalance = false);
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

  String get _uid => Provider.of<SessionProvider>(context, listen: false).user?['_id']?.toString() ?? '';

  bool get _isAdmin {
    final members = (_community['members'] as List?) ?? [];
    final me = members.firstWhere((m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == _uid, orElse: () => null);
    return me?['role']?.toString() == 'admin';
  }

  bool get _isMember {
    final members = (_community['members'] as List?) ?? [];
    return members.any((m) => (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() == _uid);
  }

  void _loadCommunity() => _load();

  Color get _communityColor => _parseColor(_community['color']);
  String get _name => (_community['name'] ?? 'Community').toString();
  String get _inviteCode => (_community['inviteCode'] ?? '').toString();
  List get _members => (_community['members'] as List?) ?? [];
  List get _groups => (_community['groups'] as List?) ?? [];

  void _showSnack(String msg, {bool isError = false, IconData? icon}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon ?? (isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded), color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor: isError ? Colors.red.shade700 : AppColors.cyan,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.all(16),
    ));
  }

  Future<void> _addGroupToCommunity() async {
    List<Map<String, dynamic>> available = [];
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final allGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final communityGroupIds = _groups.map((g) => (g['_id'] ?? g).toString()).toSet();
        available = allGroups.where((g) => !communityGroupIds.contains((g['_id'] ?? '').toString())).toList();
      }
    } catch (_) {}

    if (!mounted) return;
    if (available.isEmpty) {
      _showSnack(AppLocalizations.of(context).t('no_available_groups_snack'), icon: Icons.info_outline_rounded);
      return;
    }

    final Set<String> selected = {};

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final color = _communityColor;
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.88,
            expand: false,
            builder: (ctx2, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx2),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(children: [
                    Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: AppThemeColors.divider(ctx2), borderRadius: BorderRadius.circular(2)))),
                    const SizedBox(height: 14),
                    Row(children: [
                      Container(width: 38, height: 38,
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Add Groups', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx2))),
                        Text('Select one or more groups', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx2))),
                      ])),
                      if (selected.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text('${selected.length} selected', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                        ),
                    ]),
                  ]),
                ),
                Divider(height: 1, color: AppThemeColors.divider(ctx2)),
                Expanded(
                  child: ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: available.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final g = available[i];
                      final gId = (g['_id'] ?? '').toString();
                      final gName = (g['title'] ?? '').toString();
                      final gColor = _parseColor(g['color']);
                      final isSelected = selected.contains(gId);
                      return GestureDetector(
                        onTap: () => setSheet(() {
                          if (isSelected) selected.remove(gId); else selected.add(gId);
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? color.withValues(alpha: 0.07) : AppThemeColors.surfaceBg(ctx2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? color : gColor.withValues(alpha: 0.3),
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Container(width: 38, height: 38,
                              decoration: BoxDecoration(color: gColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                              child: Center(child: Text(gName.isNotEmpty ? gName[0].toUpperCase() : 'G',
                                style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 16)))),
                            const SizedBox(width: 12),
                            Expanded(child: Text(gName, style: TextStyle(fontWeight: FontWeight.w600,
                              color: AppThemeColors.primaryText(ctx2)))),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              child: isSelected
                                ? Icon(Icons.check_circle_rounded, color: color, size: 22, key: const ValueKey('checked'))
                                : Icon(Icons.radio_button_unchecked_rounded, color: AppThemeColors.mutedText(ctx2), size: 22, key: const ValueKey('unchecked')),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(ctx2).padding.bottom + 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: selected.isEmpty ? null : () async {
                        Navigator.pop(ctx);
                        try {
                          final r = await ApiClient.post(
                            '/api/communities/${widget.communityId}/groups',
                            body: {'groupIds': selected.toList()},
                          );
                          if (r.statusCode == 200 && mounted) {
                            _load();
                            final d = jsonDecode(r.body);
                            final skipped = (d['skippedCount'] ?? 0) as int;
                            final addedMsg = selected.length == 1 ? 'Group added' : '${selected.length} groups added';
                            if (skipped > 0) {
                              _showSkippedMembersSheet(addedMsg, skipped);
                            } else {
                              _showSnack(addedMsg, icon: Icons.check_rounded);
                            }
                          } else if (mounted) {
                            _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true);
                          }
                        } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
                      },
                      child: Text(
                        selected.isEmpty ? 'Select groups to add' : 'Add ${selected.length} group${selected.length == 1 ? "" : "s"}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  static const _presetColors = [
    Color(0xFF00B4D8), Color(0xFF0096C7), Color(0xFF023E8A), Color(0xFF2196F3),
    Color(0xFF3F51B5), Color(0xFF673AB7), Color(0xFF9C27B0), Color(0xFFE91E63),
    Color(0xFFF44336), Color(0xFFFF5722), Color(0xFFFF9800), Color(0xFFFFC107),
    Color(0xFF4CAF50), Color(0xFF009688), Color(0xFF8BC34A), Color(0xFF607D8B),
  ];

  Future<void> _pickAndUploadImage() async {
    final result = await ImagePickerUtils.pickWithSheet(context);
    if (result == null || !mounted) return;
    try {
      final res = await ApiClient.postMultipart(
        '/api/communities/${widget.communityId}/image',
        files: [ApiMultipartFile(field: 'image', filename: result.file.name, bytes: result.bytes)],
      );
      if (res.statusCode == 200) {
        _load();
        _showSnack(AppLocalizations.of(context).t('photo_updated_snack'), icon: Icons.check_rounded);
      } else {
        _showSnack(jsonDecode(res.body)['error'] ?? 'Upload failed', isError: true);
      }
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showEditCommunity() {
    final nameCtrl = TextEditingController(text: _name);
    final descCtrl = TextEditingController(text: (_community['description'] ?? '').toString());
    Color tempColor = _communityColor;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
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
              const SizedBox(height: 16),
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.edit_rounded, color: Color(0xFF8B5CF6), size: 20)),
                const SizedBox(width: 12),
                Text(AppLocalizations.of(ctx).t('edit_community_label'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx))),
              ]),
              const SizedBox(height: 20),

              // Name field
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: TextField(
                  controller: nameCtrl,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx), fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).t('community_name_label'),
                    labelStyle: TextStyle(color: AppThemeColors.secondaryText(ctx), fontSize: 13),
                    prefixIcon: Icon(Icons.hub_rounded, color: AppThemeColors.secondaryText(ctx), size: 18),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Description field
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppThemeColors.border(ctx)),
                ),
                child: TextField(
                  controller: descCtrl,
                  minLines: 2, maxLines: 3,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).t('description_optional_label'),
                    labelStyle: TextStyle(color: AppThemeColors.secondaryText(ctx), fontSize: 13),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Icon(Icons.notes_rounded, color: AppThemeColors.secondaryText(ctx), size: 18),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Color picker
              Row(children: [
                Text(AppLocalizations.of(ctx).t('color_picker_label'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(ctx))),
                const SizedBox(width: 10),
                Container(width: 22, height: 22, decoration: BoxDecoration(color: tempColor, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: tempColor.withValues(alpha: 0.4), blurRadius: 6)])),
              ]),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8, crossAxisSpacing: 10, mainAxisSpacing: 10),
                itemCount: _presetColors.length,
                itemBuilder: (_, i) {
                  final c = _presetColors[i];
                  final sel = tempColor.toARGB32() == c.toARGB32();
                  return GestureDetector(
                    onTap: () => setSheet(() => tempColor = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2),
                        boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)] : [],
                      ),
                      child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 14) : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Save button
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [tempColor, Color.lerp(tempColor, Colors.black, 0.2)!]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: tempColor.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                    minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                  onPressed: saving ? null : () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    setSheet(() => saving = true);
                    final hexColor = '#${tempColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                    try {
                      final res = await ApiClient.patch(
                        '/api/communities/${widget.communityId}',
                        body: {'name': name, 'description': descCtrl.text.trim(), 'color': hexColor},
                      );
                      if (res.statusCode == 200) {
                        Navigator.pop(ctx);
                        _load();
                        _showSnack(AppLocalizations.of(context).t('community_updated_snack'), icon: Icons.check_rounded);
                      } else {
                        _showSnack(jsonDecode(res.body)['error'] ?? 'Failed', isError: true);
                      }
                    } catch (e) {
                      _showSnack(e.toString(), isError: true);
                    }
                    setSheet(() => saving = false);
                  },
                  child: saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(AppLocalizations.of(ctx).t('save_changes_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showShareSheet() async {
    final appLink = await fetchAppInviteLink();
    final referralCode = await fetchReferralCode();
    if (!mounted) return;

    final memberCount = _members.length;
    final groupCount = _groups.length;
    final downloadLine = appLink.isNotEmpty ? '\n📥 Download LenDen: $appLink' : '';
    final referralLine = referralCode.isNotEmpty
        ? '\n🎁 *Referral Code: $referralCode*\n'
          '   (New to LenDen? Enter this code on sign-up to earn bonus coins!)'
        : '';
    final msg = '🏘️ You\'re invited to join *$_name* on LenDen!\n\n'
        '👥 Community: $_name\n'
        '${_community['description']?.toString().isNotEmpty == true ? '📝 ${_community['description']}\n' : ''}'
        '👤 Members: $memberCount   📁 Groups: $groupCount\n\n'
        '🔑 Community Invite Code:\n'
        '*$_inviteCode*\n\n'
        '📱 How to join:\n'
        '1. Open the LenDen app\n'
        '2. Go to Communities → tap the 🔗 link icon\n'
        '3. Enter the code: $_inviteCode\n'
        '$referralLine\n'
        '------------------\n'
        'LenDen – Split expenses effortlessly with friends & family. '
        'Track debts, settle instantly, and manage group expenses with ease.'
        '$downloadLine';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _communityColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.hub_rounded, color: _communityColor, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
              Text('$memberCount members · $groupCount groups',
                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
            ])),
          ]),
          const SizedBox(height: 20),
          // Invite code display
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _communityColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _communityColor.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(ctx).t('invite_code_display_label'),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(ctx), letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(_inviteCode, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                    letterSpacing: 8, color: _communityColor)),
              ])),
              IconButton(
                icon: Icon(Icons.copy_rounded, color: _communityColor),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode));
                  Navigator.pop(ctx);
                  _showSnack(AppLocalizations.of(context).t('invite_code_copied_snack'), icon: Icons.copy_rounded);
                },
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Share button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
              label: Text(AppLocalizations.of(ctx).t('share_invite_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _communityColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Share.share(msg, subject: 'Join $_name on LenDen');
              },
            ),
          ),
          const SizedBox(height: 10),
          // Copy full message
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Icon(Icons.copy_all_rounded, color: _communityColor, size: 18),
              label: Text(AppLocalizations.of(ctx).t('copy_message_btn'),
                style: TextStyle(color: _communityColor, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: _communityColor.withValues(alpha: 0.5), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: msg));
                Navigator.pop(ctx);
                _showSnack(AppLocalizations.of(context).t('message_copied_snack'), icon: Icons.copy_rounded);
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx2, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            // Drag handle + title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx2), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text('Community Settings', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx2))),
              ]),
            ),
            Divider(height: 1, color: AppThemeColors.divider(ctx2)),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx2).padding.bottom + 32),
                children: [
                  // ── General ─────────────────────────────────────────────
                  _settingsSectionLabel(ctx2, 'General'),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.camera_alt_rounded, const Color(0xFF00897B), 'Change Photo', () {
                    Navigator.pop(ctx);
                    _pickAndUploadImage();
                  }),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.edit_rounded, const Color(0xFF8B5CF6), 'Edit Community', () {
                    Navigator.pop(ctx);
                    _showEditCommunity();
                  }),

                  const SizedBox(height: 20),
                  // ── Invite ───────────────────────────────────────────────
                  _settingsSectionLabel(ctx2, 'Invite'),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.copy_rounded, AppColors.cyan, 'Copy Invite Code', () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    Navigator.pop(ctx);
                    _showSnack('Invite code copied', icon: Icons.copy_rounded);
                  }),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.refresh_rounded, const Color(0xFFFF9800), 'Regenerate Invite Code', () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        backgroundColor: AppThemeColors.cardBg(d),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text('Regenerate Invite Code', style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                        content: Text('The old invite code will stop working. Members who haven\'t joined yet will need the new code.',
                          style: TextStyle(color: AppThemeColors.secondaryText(d))),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(d, true),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Text('Regenerate')),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      try {
                        final r = await ApiClient.post('/api/communities/${widget.communityId}/invite/regenerate', body: {});
                        if (r.statusCode == 200 && mounted) {
                          final newCode = jsonDecode(r.body)['inviteCode'] as String;
                          setState(() => _community['inviteCode'] = newCode);
                          _showSnack('New invite code: $newCode', icon: Icons.refresh_rounded);
                        } else if (mounted) {
                          _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true);
                        }
                      } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
                    }
                  }),

                  const SizedBox(height: 20),
                  // ── Admin ────────────────────────────────────────────────
                  _settingsSectionLabel(ctx2, 'Admin'),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.admin_panel_settings_rounded, const Color(0xFF3F51B5), 'Transfer Admin', () async {
                    Navigator.pop(ctx);
                    _showTransferAdminSheet();
                  }),

                  const SizedBox(height: 20),
                  // ── Danger ───────────────────────────────────────────────
                  _settingsSectionLabel(ctx2, 'Danger Zone'),
                  const SizedBox(height: 8),
                  _settingsRow(ctx2, Icons.delete_rounded, Colors.red, 'Delete Community', () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        backgroundColor: AppThemeColors.cardBg(d),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(AppLocalizations.of(d).t('delete_community_confirm_title'),
                          style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                        content: Text(AppLocalizations.of(d).t('delete_community_confirm_body'),
                          style: TextStyle(color: AppThemeColors.secondaryText(d))),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(AppLocalizations.of(d).t('cancel'))),
                          ElevatedButton(onPressed: () => Navigator.pop(d, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: Text(AppLocalizations.of(d).t('delete'))),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      try {
                        final r = await ApiClient.delete('/api/communities/${widget.communityId}');
                        if (r.statusCode == 200) { if (mounted) Navigator.pop(context); }
                        else if (mounted) { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
                      } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
                    }
                  }, isDestructive: true),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // Settings sheet for non-admin members (Leave only)
  void _showMemberSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(ctx).padding.bottom + 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 14),
          Text('Options', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
          const SizedBox(height: 16),
          _settingsRow(ctx, Icons.exit_to_app_rounded, Colors.red, 'Leave Community', () async {
            Navigator.pop(ctx);
            final confirm = await showDialog<bool>(
              context: context,
              builder: (d) => AlertDialog(
                backgroundColor: AppThemeColors.cardBg(d),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('Leave Community', style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                content: Text('Are you sure you want to leave "${_name}"?',
                  style: TextStyle(color: AppThemeColors.secondaryText(d))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                  ElevatedButton(onPressed: () => Navigator.pop(d, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    child: const Text('Leave')),
                ],
              ),
            );
            if (confirm == true && mounted) {
              try {
                final r = await ApiClient.delete('/api/communities/${widget.communityId}/members/$_uid');
                if (r.statusCode == 200) { if (mounted) Navigator.pop(context); }
                else if (mounted) { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
              } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
            }
          }, isDestructive: true),
        ]),
      ),
    );
  }

  void _showTransferAdminSheet() {
    final others = _members.where((m) {
      final userId = (m['user'] is Map ? (m['user'] as Map)['_id'] : m['user'])?.toString() ?? '';
      return userId != _uid;
    }).toList();

    if (others.isEmpty) {
      _showSnack('No other members to transfer admin to', isError: true);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx2, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
              child: Column(children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx2), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Text('Transfer Admin', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx2))),
                const SizedBox(height: 4),
                Text('Choose a member to become the new admin', style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx2))),
              ]),
            ),
            Divider(height: 1, color: AppThemeColors.divider(ctx2)),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx2).padding.bottom + 24),
                itemCount: others.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final m = others[i];
                  final user = m['user'] is Map ? m['user'] as Map : <String, dynamic>{};
                  final name = (user['name'] ?? user['email'] ?? 'Member').toString();
                  final initials = name.isNotEmpty ? name[0].toUpperCase() : 'M';
                  final targetId = (user['_id'] ?? m['user'])?.toString() ?? '';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _communityColor.withValues(alpha: 0.15),
                      child: Text(initials, style: TextStyle(color: _communityColor, fontWeight: FontWeight.bold)),
                    ),
                    title: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx2))),
                    subtitle: Text((user['email'] ?? '').toString(), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx2))),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            backgroundColor: AppThemeColors.cardBg(d),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: Text('Transfer Admin', style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                            content: Text('Make $name the admin? You\'ll become a regular member.',
                              style: TextStyle(color: AppThemeColors.secondaryText(d))),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(d, true),
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3F51B5), foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                child: const Text('Transfer')),
                            ],
                          ),
                        );
                        if (confirm == true && mounted) {
                          try {
                            // Promote target to admin
                            final r1 = await ApiClient.patch(
                              '/api/communities/${widget.communityId}/members/$targetId/role',
                              body: {'role': 'admin'});
                            // Demote self to member
                            if (r1.statusCode == 200) {
                              await ApiClient.patch(
                                '/api/communities/${widget.communityId}/members/$_uid/role',
                                body: {'role': 'member'});
                            }
                            if (r1.statusCode == 200 && mounted) {
                              _showSnack('$name is now the admin');
                              _loadCommunity();
                            } else if (mounted) {
                              _showSnack(jsonDecode(r1.body)['error'] ?? 'Failed', isError: true);
                            }
                          } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3F51B5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                      child: const Text('Select'),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _settingsSectionLabel(BuildContext ctx, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 0.8, color: AppThemeColors.secondaryText(ctx))),
    );
  }

  Widget _settingsRow(BuildContext ctx, IconData icon, Color color, String label, VoidCallback onTap, {bool isDestructive = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppThemeColors.surfaceBg(ctx),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDestructive
              ? Colors.red.withValues(alpha: 0.2)
              : AppThemeColors.border(ctx)),
        ),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.red : AppThemeColors.primaryText(ctx)))),
          Icon(Icons.chevron_right_rounded, size: 18,
              color: AppThemeColors.mutedText(ctx)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _community.isEmpty) {
      return Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: const Center(child: CircularProgressIndicator(color: AppColors.cyan)),
      );
    }
    if (_error != null && _community.isEmpty) {
      return Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: TextStyle(color: AppThemeColors.secondaryText(context))),
          TextButton(onPressed: _load, child: Text(AppLocalizations.of(context).t('retry_label'), style: const TextStyle(color: AppColors.cyan))),
        ])),
      );
    }

    final communityColor = _communityColor;
    final initials = _name.isNotEmpty ? _name[0].toUpperCase() : 'C';
    final imgUrl = '${ApiConfig.baseUrl}/api/communities/${widget.communityId}/image';
    final defImg = defaultCommunityImageUrl(_name);
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(children: [
        // ── Hero image banner ──────────────────────────────────────────
        SizedBox(
          height: 220 + topPad,
          child: Stack(fit: StackFit.expand, children: [
            // Background image (community photo or keyword default)
            Image.network(imgUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.network(defImg, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [communityColor, Color.lerp(communityColor, Colors.black, 0.4)!],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                  ),
                ))),
            // Dark gradient overlay so text is readable
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x55000000), Color(0xDD000000)],
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                ),
              ),
            ),
            // SafeArea content: top row + bottom info
            SafeArea(
              child: Column(children: [
                // Top row: back / settings / share
                Row(children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  if (_isMember)
                    IconButton(
                      icon: Icon(Icons.settings_rounded, color: AppThemeColors.primaryText(context)),
                      onPressed: _isAdmin ? _showSettings : _showMemberSettings,
                    ),
                  if (_inviteCode.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.share_rounded, color: AppThemeColors.primaryText(context)),
                      onPressed: _showShareSheet,
                    ),
                ]),
                const Spacer(),
                // Community info overlay
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_name, style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 22,
                      fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(Icons.people_rounded, color: AppThemeColors.secondaryText(context), size: 14),
                      const SizedBox(width: 5),
                      Text('${_members.length} ${_members.length == 1 ? AppLocalizations.of(context).t('member_singular') : AppLocalizations.of(context).t('member_plural')}  ·  ${_groups.length} ${_groups.length == 1 ? AppLocalizations.of(context).t('group_singular') : AppLocalizations.of(context).t('group_plural')}',
                        style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12)),
                    ]),
                    if ((_community['description'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text((_community['description'] ?? '').toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12,
                          fontStyle: FontStyle.italic, height: 1.4)),
                    ],
                  ]),
                ),
              ]),
            ),
          ]),
        ),

        // ── Tab bar ────────────────────────────────────────────────────
        Container(
          color: AppThemeColors.cardBg(context),
          child: TabBar(
            controller: _tabController,
            labelColor: communityColor,
            unselectedLabelColor: AppThemeColors.secondaryText(context),
            indicatorColor: communityColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: AppLocalizations.of(context).t('tab_overview')),
              Tab(text: AppLocalizations.of(context).t('tab_groups')),
              Tab(text: AppLocalizations.of(context).t('tab_members')),
              Tab(text: AppLocalizations.of(context).t('tab_feed')),
            ],
          ),
        ),

        // ── Tab content ────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildOverview(communityColor, initials, imgUrl),
              _buildGroupsTab(communityColor),
              _buildMembersTab(communityColor),
              _buildFeedTab(communityColor),
            ],
          ),
        ),
      ]),
    );
  }

  // ─── OVERVIEW TAB ───────────────────────────────────────────────────────────
  Widget _buildOverview(Color color, String initials, String imgUrl) {
    return RefreshIndicator(
      onRefresh: _load,
      color: color,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Community identity card
          _card(children: [
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(15)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(imgUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: Text(initials,
                      style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold),
                    )),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
                if ((_community['description'] ?? '').toString().isNotEmpty)
                  Text((_community['description'] ?? '').toString(),
                    style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.4)),
              ])),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              _miniStat(color, Icons.folder_shared_rounded, '${_groups.length}', AppLocalizations.of(context).t('tab_groups')),
              const SizedBox(width: 10),
              _miniStat(color, Icons.people_rounded, '${_members.length}', AppLocalizations.of(context).t('tab_members')),
            ]),
          ]),

          const SizedBox(height: 12),

          // Splits card — shows the total amount this user was split across all community groups
          _card(children: [
            Row(children: [
              Container(width: 38, height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.receipt_long_rounded, size: 20, color: color)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLocalizations.of(context).t('my_total_splits_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
                const SizedBox(height: 2),
                _loadingBalance
                    ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('₹${_totalBalance.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                        const SizedBox(height: 4),
                        if (_netBalance > 0.005)
                          Text('${AppLocalizations.of(context).t('you_owe_label').toUpperCase()}  ₹${_netBalance.abs().toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red))
                        else if (_netBalance < -0.005)
                          Text('${AppLocalizations.of(context).t('you_are_owed_label')}  ₹${_netBalance.abs().toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00897B)))
                        else
                          Text(AppLocalizations.of(context).t('all_settled_label'),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00897B))),
                      ]),
              ])),
            ]),
            if (_groupBalances.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: AppThemeColors.border(context)),
              const SizedBox(height: 10),
              ..._groupBalances.where((g) => (g['pendingAmount'] ?? g['amount'] ?? 0) != 0).map((g) {
                final pending = (g['pendingAmount'] ?? 0).toDouble();
                final gColor = _parseColor(g['color']);
                final isOwes = pending > 0.005;
                final isOwed = pending < -0.005;
                final amtColor = isOwes ? Colors.red : (isOwed ? const Color(0xFF00897B) : AppThemeColors.secondaryText(context));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Container(width: 30, height: 30,
                      decoration: BoxDecoration(color: gColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text((g['title'] ?? 'G').toString()[0].toUpperCase(),
                        style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 13)))),
                    const SizedBox(width: 10),
                    Expanded(child: Text((g['title'] ?? '').toString(),
                      style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context), fontWeight: FontWeight.w500))),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('₹${pending.abs().toStringAsFixed(0)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: amtColor)),
                      if (isOwes || isOwed)
                        Text(isOwes ? AppLocalizations.of(context).t('you_owe_small') : AppLocalizations.of(context).t('you_are_owed_small'),
                          style: TextStyle(fontSize: 10, color: amtColor, fontWeight: FontWeight.w500)),
                    ]),
                  ]),
                );
              }),
            ],
          ]),

          const SizedBox(height: 12),

          // Invite code card
          if (_inviteCode.isNotEmpty)
            _card(children: [
              Row(children: [
                Container(width: 38, height: 38,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
                  child: Icon(Icons.key_rounded, size: 20, color: color)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLocalizations.of(context).t('invite_code_display_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppThemeColors.mutedText(context), letterSpacing: 1.2)),
                  Text(_inviteCode, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      letterSpacing: 8, color: color)),
                ]),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: color, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    _showSnack(AppLocalizations.of(context).t('code_copied_snack'), icon: Icons.copy_rounded);
                  },
                ),
              ]),
            ]),
        ],
      ),
    );
  }

  // ─── GROUPS TAB ─────────────────────────────────────────────────────────────
  Widget _buildGroupsTab(Color color) {
    return Column(children: [
      if (_isAdmin)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, AppColors.blue]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ElevatedButton.icon(
              onPressed: _addGroupToCommunity,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
              icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
              label: Text(AppLocalizations.of(context).t('add_group_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      Expanded(
        child: _groups.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 60, height: 60,
                  decoration: BoxDecoration(color: AppThemeColors.surfaceBg(context), borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppThemeColors.border(context))),
                  child: Icon(Icons.folder_open_rounded, size: 28, color: AppThemeColors.mutedText(context))),
                const SizedBox(height: 14),
                Text(AppLocalizations.of(context).t('no_groups_yet_label'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
                Text(_isAdmin ? AppLocalizations.of(context).t('add_group_link_hint') : AppLocalizations.of(context).t('ask_admin_groups_hint'),
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: _groups.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final g = _groups[i];
                  final gId = (g['_id'] ?? g).toString();
                  final gName = (g['title'] ?? g['name'] ?? 'Group').toString();
                  final gColor = _parseColor(g['color']);
                  final gInitial = gName.isNotEmpty ? gName[0].toUpperCase() : 'G';
                  return GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => GroupDetailPage(groupId: gId, initialGroup: g is Map<String, dynamic> ? g : {}),
                    )).then((_) => _load()),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: gColor.withValues(alpha: 0.3)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        leading: Container(width: 42, height: 42,
                          decoration: BoxDecoration(color: gColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: Center(child: Text(gInitial, style: TextStyle(color: gColor, fontWeight: FontWeight.bold, fontSize: 18)))),
                        title: Text(gName, style: TextStyle(fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(context))),
                        trailing: _isAdmin
                            ? IconButton(
                                icon: Icon(Icons.remove_circle_outline_rounded, color: Colors.red.withValues(alpha: 0.7), size: 22),
                                tooltip: AppLocalizations.of(context).t('remove_from_community_tooltip'),
                                onPressed: () async {
                                  try {
                                    final r = await ApiClient.delete('/api/communities/${widget.communityId}/groups/$gId');
                                    if (r.statusCode == 200) {
                                      _load();
                                      final d = jsonDecode(r.body);
                                      final removed = d['removedMembers'] ?? 0;
                                      final extra = removed > 0 ? ' · $removed member${removed == 1 ? "" : "s"} auto-removed' : '';
                                      _showSnack('Group removed$extra');
                                    } else { _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true); }
                                  } catch (e) { _showSnack(e.toString(), isError: true); }
                                },
                              )
                            : const Icon(Icons.chevron_right_rounded, size: 20),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showSkippedMembersSheet(String addedMsg, int skippedCount) {
    final color = _communityColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 32),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.cyan, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(addedMsg, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
              Text('Groups linked to community', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx))),
            ])),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.person_off_rounded, color: Color(0xFFFF9800), size: 20),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$skippedCount member${skippedCount == 1 ? "" : "s"} not added',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
                const SizedBox(height: 4),
                Text(
                  'These members have privacy settings that restrict direct community additions. '
                  'They can still join using the invite code.',
                  style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(ctx), height: 1.5),
                ),
              ])),
            ]),
          ),
          if (_inviteCode.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Icon(Icons.key_rounded, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Share this code with them', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(ctx), letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(_inviteCode, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    letterSpacing: 6, color: color)),
                ])),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: color, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    Navigator.pop(ctx);
                    _showSnack('Invite code copied', icon: Icons.copy_rounded);
                  },
                ),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showRestrictedAddSheet(String email, String serverMsg) {
    final color = _communityColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(ctx).padding.bottom + 32),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          // Icon + title row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_person_rounded, color: Color(0xFFFF9800), size: 32),
          ),
          const SizedBox(height: 14),
          Text('Direct Add Restricted', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.bold,
            color: AppThemeColors.primaryText(ctx),
          )),
          const SizedBox(height: 8),
          Text(email, style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(ctx))),
          const SizedBox(height: 16),
          // Info card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.notifications_active_rounded, color: Color(0xFFFF9800), size: 16),
                const SizedBox(width: 8),
                Text('Invite Sent Automatically', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFFF9800))),
              ]),
              const SizedBox(height: 8),
              Text(
                'This user has turned off direct community adds in their privacy settings. '
                'An in-app invite notification has been sent — they can join using the community code.',
                style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(ctx), height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Invite code row
          if (_inviteCode.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Row(children: [
                Icon(Icons.key_rounded, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Community Code', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: AppThemeColors.mutedText(ctx), letterSpacing: 1.1)),
                  const SizedBox(height: 2),
                  Text(_inviteCode, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    letterSpacing: 6, color: color)),
                ])),
                IconButton(
                  icon: Icon(Icons.copy_rounded, color: color, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteCode));
                    Navigator.pop(ctx);
                    _showSnack('Invite code copied', icon: Icons.copy_rounded);
                  },
                ),
              ]),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color, elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _showAddMemberSheet(Color color) async {
    final emailCtrl = TextEditingController();
    bool sending = false;
    final allowDirect = (_community['settings'] as Map?)?['allowDirectAdd'] as bool? ?? true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(width: 40, height: 40,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]), borderRadius: BorderRadius.circular(12)),
                  child: Icon(allowDirect ? Icons.person_add_rounded : Icons.mail_rounded, color: Colors.white, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(allowDirect ? AppLocalizations.of(ctx).t('add_member_title') : AppLocalizations.of(ctx).t('send_invite_title'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                  Text(allowDirect ? AppLocalizations.of(ctx).t('direct_add_mode_desc') : AppLocalizations.of(ctx).t('invite_mode_desc'),
                    style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx))),
                ])),
              ]),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.surfaceBg(ctx),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
                ),
                child: TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(ctx).t('enter_email_hint'),
                    hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                    prefixIcon: Icon(Icons.email_outlined, color: color, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: sending ? null : () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty) return;
                    setSheet(() => sending = true);
                    try {
                      final r = await ApiClient.post('/api/communities/${widget.communityId}/members', body: {'email': email});
                      final body = jsonDecode(r.body);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (r.statusCode == 200) {
                        _load();
                        if (body['notified'] == true) {
                          _showRestrictedAddSheet(email, body['message']?.toString() ?? '');
                        } else {
                          _showSnack(body['message'] ?? (allowDirect ? 'Member added!' : 'Invite sent!'),
                            icon: allowDirect ? Icons.person_add_rounded : Icons.mail_rounded);
                        }
                      } else {
                        _showSnack(body['error'] ?? 'Failed', isError: true);
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(allowDirect ? AppLocalizations.of(ctx).t('add_member_title') : AppLocalizations.of(ctx).t('send_invite_title'),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── MEMBERS TAB ────────────────────────────────────────────────────────────
  Widget _buildMembersTab(Color color) {
    final oid = RegExp(r'^[0-9a-f]{24}$');
    String sanitize(dynamic v, String fb) {
      final s = (v ?? '').toString();
      return s.isEmpty || oid.hasMatch(s) ? fb : s;
    }

    return Column(children: [
      // Header row
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _memberSelectMode ? Colors.red.withValues(alpha: 0.06) : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _memberSelectMode ? Colors.red.withValues(alpha: 0.3) : color.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(_memberSelectMode ? Icons.check_box_rounded : Icons.people_rounded,
              color: _memberSelectMode ? Colors.red : color, size: 18),
            const SizedBox(width: 8),
            Text(
              _memberSelectMode
                ? '${_selectedMemberIds.length} selected'
                : '${_members.length} ${_members.length == 1 ? AppLocalizations.of(context).t('member_singular') : AppLocalizations.of(context).t('member_plural')}',
              style: TextStyle(fontWeight: FontWeight.w700,
                color: _memberSelectMode ? Colors.red : color, fontSize: 13)),
            const Spacer(),
            if (_isAdmin && !_memberSelectMode) ...[
              GestureDetector(
                onTap: () => _showAddMemberSheet(color),
                child: Row(children: [
                  Icon(Icons.person_add_rounded, color: color, size: 15),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).t('add_btn'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() { _memberSelectMode = true; _selectedMemberIds.clear(); }),
                child: Row(children: [
                  Icon(Icons.remove_circle_outline_rounded, color: Colors.red.withValues(alpha: 0.7), size: 15),
                  const SizedBox(width: 4),
                  Text('Remove', style: TextStyle(color: Colors.red.shade600, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(width: 10),
            ],
            if (!_memberSelectMode && _inviteCode.isNotEmpty)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _inviteCode));
                  _showSnack(AppLocalizations.of(context).t('invite_code_copied_snack'), icon: Icons.copy_rounded);
                },
                child: Row(children: [
                  Icon(Icons.link_rounded, color: color, size: 15),
                  const SizedBox(width: 4),
                  Text(AppLocalizations.of(context).t('invite_label'), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            if (_memberSelectMode) ...[
              TextButton(
                onPressed: () => setState(() { _memberSelectMode = false; _selectedMemberIds.clear(); }),
                child: Text('Cancel', style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12)),
              ),
              if (_selectedMemberIds.isNotEmpty)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final count = _selectedMemberIds.length;
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        backgroundColor: AppThemeColors.cardBg(d),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text('Remove $count member${count == 1 ? "" : "s"}?',
                          style: TextStyle(color: AppThemeColors.primaryText(d), fontWeight: FontWeight.bold)),
                        content: Text('This action cannot be undone. Removed members can rejoin via invite code.',
                          style: TextStyle(color: AppThemeColors.secondaryText(d))),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          ElevatedButton(onPressed: () => Navigator.pop(d, true),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            child: const Text('Remove')),
                        ],
                      ),
                    );
                    if (confirmed != true || !mounted) return;
                    try {
                      final r = await ApiClient.delete(
                        '/api/communities/${widget.communityId}/members',
                        body: {'userIds': _selectedMemberIds.toList()},
                      );
                      if (r.statusCode == 200 && mounted) {
                        setState(() { _memberSelectMode = false; _selectedMemberIds.clear(); });
                        _load();
                        _showSnack('$count member${count == 1 ? "" : "s"} removed', icon: Icons.check_rounded);
                      } else if (mounted) {
                        _showSnack(jsonDecode(r.body)['error'] ?? 'Failed', isError: true);
                      }
                    } catch (e) { if (mounted) _showSnack(e.toString(), isError: true); }
                  },
                  child: Text('Remove ${_selectedMemberIds.length}', style: const TextStyle(color: Colors.white)),
                ),
            ],
          ]),
        ),
      ),

      Expanded(
        child: Builder(builder: (ctx) {
          final pendingInvites = List<Map<String, dynamic>>.from((_community['pendingInvites'] as List?) ?? []);
          final totalCount = _members.length + (pendingInvites.isNotEmpty ? pendingInvites.length + 1 : 0);
          return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: totalCount,
          separatorBuilder: (_, i) {
            if (pendingInvites.isNotEmpty && i == _members.length - 1) return const SizedBox(height: 4);
            return const SizedBox(height: 8);
          },
          itemBuilder: (_, i) {
            // Pending invites section header
            if (pendingInvites.isNotEmpty && i == _members.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.mail_outline_rounded, color: Color(0xFFFF9800), size: 13),
                      SizedBox(width: 5),
                      Text('Invited — awaiting response',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
                    ]),
                  ),
                ]),
              );
            }
            // Pending invite rows
            if (pendingInvites.isNotEmpty && i > _members.length) {
              final inv = pendingInvites[i - _members.length - 1];
              final invEmail = (inv['email'] ?? '').toString();
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.25)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  leading: Container(width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text(invEmail.isNotEmpty ? invEmail[0].toUpperCase() : '?',
                      style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold, fontSize: 16)))),
                  title: Text(invEmail, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context)), overflow: TextOverflow.ellipsis),
                  subtitle: const Text('Invite sent · not yet joined', style: TextStyle(fontSize: 11, color: Color(0xFFFF9800))),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFFF9800).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Invited', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
                  ),
                ),
              );
            }
            // Regular member rows
            final m = _members[i];
            final user = m['user'] is Map ? m['user'] as Map : <String, dynamic>{};
            final rawName = sanitize(user['name'], '');
            final rawEmail = sanitize(user['email'], '');
            final mName = rawName.isNotEmpty ? rawName : (rawEmail.isNotEmpty ? rawEmail
              : (user.isEmpty ? AppLocalizations.of(context).t('deleted_account_label') : AppLocalizations.of(context).t('member_singular')));
            final mEmail = rawEmail;
            final role = (m['role'] ?? 'member').toString();
            final memberId = (user['_id'] ?? '').toString();
            final isMe = memberId == _uid;
            final isSelected = _selectedMemberIds.contains(memberId);
            // Admins can't be removed via bulk select (protect accidentally removing all admins)
            final canSelect = _memberSelectMode && _isAdmin && !isMe && role != 'admin';

            return GestureDetector(
              onTap: canSelect ? () => setState(() {
                if (isSelected) _selectedMemberIds.remove(memberId);
                else _selectedMemberIds.add(memberId);
              }) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                    ? Colors.red.withValues(alpha: 0.06)
                    : AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSelected
                    ? Colors.red.withValues(alpha: 0.4)
                    : role == 'admin'
                      ? color.withValues(alpha: 0.25)
                      : AppThemeColors.border(context).withValues(alpha: 0.5)),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: _memberSelectMode
                    ? Container(width: 42, height: 42,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red : AppThemeColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isSelected ? Colors.red : AppThemeColors.border(context)),
                        ),
                        child: Icon(
                          isSelected ? Icons.check_rounded : (canSelect ? Icons.check_box_outline_blank_rounded : Icons.block_rounded),
                          color: isSelected ? Colors.white : (canSelect ? AppThemeColors.mutedText(context) : Colors.orange),
                          size: 20,
                        ))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 42, height: 42,
                          child: Image.network(
                            '${ApiConfig.baseUrl}/api/users/$memberId/profile-image',
                            width: 42, height: 42, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 42, height: 42,
                              decoration: BoxDecoration(
                                color: role == 'admin' ? color : AppThemeColors.surfaceBg(context),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(child: Text(
                                mName.isNotEmpty ? mName[0].toUpperCase() : 'M',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18,
                                  color: role == 'admin' ? Colors.white : AppThemeColors.secondaryText(context)),
                              )),
                            ),
                          ),
                        ),
                      ),
                  title: Row(children: [
                    Flexible(child: Text(mName, style: TextStyle(fontWeight: FontWeight.w700,
                        color: AppThemeColors.primaryText(context)))),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: AppThemeColors.surfaceBg(context), borderRadius: BorderRadius.circular(20)),
                        child: Text(AppLocalizations.of(context).t('you_chip_label'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: AppThemeColors.secondaryText(context))),
                      ),
                    ],
                  ]),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(mEmail, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                    if (m['invitedBy'] != null) ...[
                      const SizedBox(height: 2),
                      Row(mainAxisSize: MainAxisSize.min, children: const [
                        Icon(Icons.mail_outline_rounded, size: 10, color: Color(0xFF00897B)),
                        SizedBox(width: 3),
                        Text('Joined via invite', style: TextStyle(fontSize: 10, color: Color(0xFF00897B), fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ]),
                  trailing: _memberSelectMode
                    ? null
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: role == 'admin' ? color.withValues(alpha: 0.10) : AppThemeColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: role == 'admin' ? color.withValues(alpha: 0.3) : AppThemeColors.border(context)),
                        ),
                        child: Text(
                          role == 'admin' ? AppLocalizations.of(context).t('role_admin_badge') : AppLocalizations.of(context).t('role_member_badge'),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: role == 'admin' ? color : AppThemeColors.secondaryText(context)),
                        ),
                      ),
                ),
              ),
            );
          },
        );
      }),
    ),
  ]);
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────
  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _miniStat(Color color, IconData icon, String value, String label) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
        ]),
      ]),
    ));
  }

  // ─── FEED TAB ────────────────────────────────────────────────────────────────
  Widget _buildFeedTab(Color color) {
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
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
              child: Icon(Icons.lock_rounded, color: color, size: 34),
            ),
            const SizedBox(height: 20),
            Text(AppLocalizations.of(context).t('community_feed_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(AppLocalizations.of(context).t('community_feed_subscribe_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.blue, 0.5)!]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0,
                ),
                icon: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 18),
                label: Text(AppLocalizations.of(context).t('upgrade_to_subscribe_btn'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => _showSnack(AppLocalizations.of(context).t('subscribe_for_feed_snack'), icon: Icons.info_outline_rounded),
              ),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      color: color,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // New post button
          GestureDetector(
            onTap: () => _showNewPostSheet(color),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Row(children: [
                _profileAvatar(userId, size: 36, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text('Share an update, reminder or poll…',
                  style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Post', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          if (_feedLoading)
            const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
          else if (_posts.isEmpty)
            Center(child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
                  child: Icon(Icons.forum_outlined, color: color, size: 30)),
                const SizedBox(height: 14),
                Text(AppLocalizations.of(context).t('no_posts_yet'),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 6),
                Text(AppLocalizations.of(context).t('be_first_to_post'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5)),
              ]),
            ))
          else ...[
            ..._posts.map((p) => _buildPostCard(p, color, userId)),
            if (_hasMorePosts)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Center(
                  child: _loadingMorePosts
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _loadMorePosts,
                        child: Text(AppLocalizations.of(context).t('load_more_btn'), style: TextStyle(color: color, fontSize: 13)),
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPostCard(Map<String, dynamic> p, Color color, String userId) {
    final postType = (p['type'] ?? 'text').toString();
    final isPinned = p['isPinned'] == true;
    final author = p['author'] as Map<String, dynamic>? ?? {};
    final authorId = (author['_id'] ?? '').toString();
    final authorName = (author['name'] ?? author['email'] ?? 'Unknown').toString();
    final text = (p['text'] ?? '').toString();
    final postId = (p['_id'] ?? '').toString();
    final createdAt = p['createdAt'] != null ? DateTime.tryParse(p['createdAt'].toString()) : null;
    final diff = createdAt != null ? DateTime.now().difference(createdAt) : null;
    final ago = diff == null ? '' : diff.inMinutes < 1 ? 'just now' : diff.inMinutes < 60 ? '${diff.inMinutes}m ago' : diff.inHours < 24 ? '${diff.inHours}h ago' : '${diff.inDays}d ago';
    final isOwn = authorId == userId;
    final likedByMe = p['likedByMe'] == true;
    final likesCount = (p['likesCount'] ?? 0) as int;
    final commentCount = (p['comments'] as List? ?? []).length;

    // Type-specific accent
    Color typeColor = color;
    IconData typeIcon = Icons.notes_rounded;
    if (postType == 'announcement') { typeColor = const Color(0xFFFF9800); typeIcon = Icons.campaign_rounded; }
    else if (postType == 'reminder')  { typeColor = const Color(0xFF8B5CF6); typeIcon = Icons.alarm_rounded; }
    else if (postType == 'poll')      { typeColor = const Color(0xFF10B981); typeIcon = Icons.poll_rounded; }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPinned ? typeColor.withValues(alpha: 0.4) : AppThemeColors.border(context)),
        boxShadow: isPinned ? [BoxShadow(color: typeColor.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Pinned / type banner for non-text posts
        if (isPinned || postType != 'text')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              if (isPinned) ...[
                const Icon(Icons.push_pin_rounded, size: 13, color: Color(0xFFFF9800)),
                const SizedBox(width: 4),
                Text('Pinned', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFFFF9800))),
                const SizedBox(width: 10),
              ],
              if (postType != 'text') ...[
                Icon(typeIcon, size: 13, color: typeColor),
                const SizedBox(width: 4),
                Text(postType == 'announcement' ? 'Announcement' : postType == 'reminder' ? 'Reminder' : 'Poll',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: typeColor)),
              ],
              const Spacer(),
              if (_isAdmin && postType != 'poll')
                GestureDetector(
                  onTap: () => _pinPost(postId, !isPinned),
                  child: Icon(isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 16, color: isPinned ? const Color(0xFFFF9800) : AppThemeColors.mutedText(context)),
                ),
            ]),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header: avatar + author + time + menu
            Row(children: [
              _profileAvatar(authorId, size: 34, color: typeColor),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(authorName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppThemeColors.primaryText(context))),
                Text(ago, style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context))),
              ])),
              if (isOwn && postType != 'poll') ...[
                GestureDetector(
                  onTap: () => _showEditPostSheet(p),
                  child: Padding(padding: const EdgeInsets.only(right: 10),
                    child: Icon(Icons.edit_outlined, size: 16, color: AppThemeColors.mutedText(context))),
                ),
              ],
              if (isOwn || _isAdmin)
                GestureDetector(
                  onTap: () => _deletePost(postId),
                  child: Icon(Icons.delete_outline_rounded, size: 16, color: AppThemeColors.mutedText(context)),
                ),
            ]),
            const SizedBox(height: 10),

            // Post text
            Text(text, style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(context), height: 1.45)),

            // Reminder extras
            if (postType == 'reminder') ...[
              const SizedBox(height: 10),
              _buildReminderExtras(p, typeColor),
            ],

            // Poll
            if (postType == 'poll') ...[
              const SizedBox(height: 12),
              _buildPollWidget(p, postId, typeColor, userId),
            ],

            const SizedBox(height: 12),
            // Like / comment row
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
                onTap: () => _showComments(p, color),
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
        ),
      ]),
    );
  }

  Widget _buildReminderExtras(Map<String, dynamic> p, Color typeColor) {
    final dueDate = p['dueDate'] != null ? DateTime.tryParse(p['dueDate'].toString()) : null;
    final amount = (p['amount'] as num?)?.toDouble();
    final now = DateTime.now();
    final overdue = dueDate != null && dueDate.isBefore(now);
    final daysLeft = dueDate != null ? dueDate.difference(now).inDays : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (overdue ? Colors.red : typeColor).withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (overdue ? Colors.red : typeColor).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        if (amount != null) ...[
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AMOUNT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 1, color: AppThemeColors.mutedText(context))),
            Text('₹${amount.toStringAsFixed(0)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: typeColor)),
          ]),
          const SizedBox(width: 16),
          Container(width: 1, height: 36, color: typeColor.withValues(alpha: 0.2)),
          const SizedBox(width: 16),
        ],
        if (dueDate != null)
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DUE DATE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
              letterSpacing: 1, color: AppThemeColors.mutedText(context))),
            Text('${dueDate.day}/${dueDate.month}/${dueDate.year}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                color: overdue ? Colors.red : AppThemeColors.primaryText(context))),
            if (daysLeft != null)
              Text(overdue ? 'Overdue by ${(-daysLeft)} days' : daysLeft == 0 ? 'Due today!' : '$daysLeft days left',
                style: TextStyle(fontSize: 11, color: overdue ? Colors.red : typeColor, fontWeight: FontWeight.w600)),
          ])),
      ]),
    );
  }

  Widget _buildPollWidget(Map<String, dynamic> p, String postId, Color typeColor, String userId) {
    final poll = p['poll'] as Map<String, dynamic>? ?? {};
    final options = (poll['options'] as List? ?? []).map((o) => Map<String, dynamic>.from(o as Map)).toList();
    final totalVotes = (poll['totalVotes'] as num?)?.toInt() ?? 0;

    if (options.isEmpty) return const SizedBox.shrink();

    final myVote = options.firstWhere(
      (o) => o['votedByMe'] == true,
      orElse: () => <String, dynamic>{},
    );
    final hasVoted = myVote.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...options.map((opt) {
          final optId = (opt['_id'] ?? '').toString();
          final voteCount = (opt['voteCount'] as num?)?.toInt() ?? 0;
          final votedThis = opt['votedByMe'] == true;
          final pct = totalVotes > 0 ? voteCount / totalVotes : 0.0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () => _votePoll(postId, optId, votedThis),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: votedThis ? typeColor.withValues(alpha: 0.12) : AppThemeColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: votedThis ? typeColor : AppThemeColors.border(context), width: votedThis ? 1.5 : 1),
                ),
                child: Stack(children: [
                  // Progress fill
                  if (hasVoted)
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: pct,
                        child: Container(
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  Row(children: [
                    Expanded(child: Text((opt['text'] ?? '').toString(),
                      style: TextStyle(fontSize: 13, fontWeight: votedThis ? FontWeight.w700 : FontWeight.normal,
                        color: AppThemeColors.primaryText(context)))),
                    if (hasVoted) Text('$voteCount ${voteCount == 1 ? "vote" : "votes"}',
                      style: TextStyle(fontSize: 11, color: typeColor, fontWeight: FontWeight.w600)),
                    if (votedThis) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle_rounded, size: 15, color: typeColor),
                    ],
                  ]),
                ]),
              ),
            ),
          );
        }),
        Text('$totalVotes ${totalVotes == 1 ? "vote" : "votes"} total',
          style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
      ],
    );
  }

  Widget _profileAvatar(String userId, {double size = 38, Color? color}) {
    final fallback = color ?? AppColors.cyan;
    if (userId.isEmpty) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(color: fallback.withValues(alpha: 0.10), shape: BoxShape.circle),
        child: Icon(Icons.person_rounded, color: fallback, size: size * 0.5),
      );
    }
    return ClipOval(
      child: Image.network(
        '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size,
          decoration: BoxDecoration(color: fallback.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(Icons.person_rounded, color: fallback, size: size * 0.5),
        ),
      ),
    );
  }
}
