import 'dart:convert';
import '../../../utils/avatar_helpers.dart' as ah;
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/api_client.dart';
import '../../../api_config.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';

final _oidRe = RegExp(r'^[0-9a-f]{24}$');
String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) {
    final e = (field['email'] ?? '').toString();
    return _oidRe.hasMatch(e) || e.isEmpty ? (field['name']?.toString().isNotEmpty == true ? field['name'].toString() : 'Deleted Account') : e;
  }
  final s = field.toString();
  return _oidRe.hasMatch(s) ? 'Deleted Account' : s;
}

String _nameOf(dynamic field) {
  if (field == null) return '';
  if (field is Map) {
    final n = (field['name'] ?? '').toString();
    return _oidRe.hasMatch(n) ? 'Deleted Account' : n;
  }
  final s = field.toString();
  return _oidRe.hasMatch(s) ? 'Deleted Account' : '';
}


class GroupMembersPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final bool isCreator;
  final String userEmail;
  final String creatorEmail;
  final List<dynamic> initialMembers;
  final List<dynamic> initialPendingInvites;
  final List<dynamic> initialDeclinedInvites;
  final bool openAddMember;

  const GroupMembersPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.isCreator,
    required this.userEmail,
    required this.creatorEmail,
    required this.initialMembers,
    this.initialPendingInvites = const [],
    this.initialDeclinedInvites = const [],
    this.openAddMember = false,
  });

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  late List<dynamic> _members;
  late List<dynamic> _pendingInvites;
  late List<dynamic> _declinedInvites;
  bool _loading = false;
  String? _error;
  String _filter = 'active';
  final _addEmailCtrl = TextEditingController();
  List<Map<String, dynamic>> _userCommunities = [];
  List<Map<String, dynamic>> _friends = [];
  bool _loadingFriends = false;
  List<Map<String, dynamic>> _counterparties = [];
  bool _loadingCounterparties = false;
  List<Map<String, dynamic>> _userGroups = [];
  bool _loadingGroups = false;

  @override
  void initState() {
    super.initState();
    _members = List<dynamic>.from(widget.initialMembers);
    _pendingInvites = List<dynamic>.from(widget.initialPendingInvites);
    _declinedInvites = List<dynamic>.from(widget.initialDeclinedInvites);
    if (widget.openAddMember) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showAddMemberSheet());
    }
  }

  @override
  void dispose() {
    _addEmailCtrl.dispose();
    super.dispose();
  }

  List<dynamic> get _filtered {
    if (_filter == 'active') {
      return _members.where((m) => m['leftAt'] == null).toList();
    }
    if (_filter == 'left') {
      return _members.where((m) => m['leftAt'] != null).toList();
    }
    return _members;
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final groups =
            List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final group = groups.firstWhere(
          (g) => g['_id'].toString() == widget.groupId,
          orElse: () => <String, dynamic>{},
        );
        if (group.isNotEmpty && mounted) {
          setState(() {
            _members = List<dynamic>.from(group['members'] ?? []);
            _pendingInvites = List<dynamic>.from(group['pendingInvites'] ?? []);
            _declinedInvites = List<dynamic>.from(group['declinedInvites'] ?? []);
          });
        }
      } else {
        if (mounted) setState(() => _error = 'Failed to load members. Please try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load members. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMember(String email, {bool silent = false}) async {
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/add-member',
      body: {'email': email.trim().toLowerCase()},
    );
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 || res.statusCode == 201) {
      if (body['notified'] == true) {
        _refresh();
        _showGroupRestrictedSheet(email, widget.groupTitle);
      } else if (!silent) {
        _showSnack(t('member_added_message'), success: true);
        _refresh();
      }
    } else {
      _showError(body['error'] ?? t('failed_to_add_member_message'));
    }
  }

  void _showGroupRestrictedSheet(String email, String groupTitle) {
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
          const SizedBox(height: 6),
          Text(email, style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(ctx))),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.notifications_active_rounded, color: Color(0xFFFF9800), size: 16),
                SizedBox(width: 8),
                Text('Invite Sent Automatically',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
              ]),
              const SizedBox(height: 8),
              Text(
                'This user has restricted direct group additions. An in-app notification and device push have been sent — they can join "$groupTitle" using the group join code.',
                style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(ctx), height: 1.5),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan, elevation: 0,
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

  Future<void> _removeMember(String email) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.person_remove_rounded, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(t('remove_member_title'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red)),
                ]),
                const SizedBox(height: 12),
                Text(t('remove_member_confirm_message').replaceFirst('{email}', email),
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  t('balance_auto_settled_message'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(t('cancel'))),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('remove'),
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/remove-member',
      body: {'email': email},
    );
    if (!mounted) return;
    if (res.statusCode == 200) {
      _showSnack(t('member_removed_message'), success: true);
      _refresh();
    } else {
      setState(() => _loading = false);
      final body = jsonDecode(res.body);
      _showError(body['error'] ?? t('failed_to_remove_member_message'));
    }
  }

  Future<void> _loadCommunities() async {
    try {
      final res = await ApiClient.get('/api/communities');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _userCommunities = List<Map<String, dynamic>>.from(data['communities'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadFriends() async {
    if (_loadingFriends) return;
    setState(() => _loadingFriends = true);
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFriends = false);
  }

  Future<void> _loadCounterparties() async {
    if (_loadingCounterparties) return;
    setState(() => _loadingCounterparties = true);
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final email = Uri.encodeComponent(session.user?['email']?.toString() ?? '');
      final res = await ApiClient.get('/api/counterparties/user?email=$email');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _counterparties = List<Map<String, dynamic>>.from(data['counterparties'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingCounterparties = false);
  }

  Future<void> _loadGroups() async {
    if (_loadingGroups || _userGroups.isNotEmpty) return;
    setState(() => _loadingGroups = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _userGroups = List<Map<String, dynamic>>.from(data['groups'] ?? []));
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingGroups = false);
  }

  // Generic flat people-picker (friends / counterparties / all-sources).
  // Returns the list of emails the user confirmed.
  Future<List<String>> _showPeoplePicker({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> people,
    String subtitle = '',
  }) async {
    final List<String> picked = [];
    String search = '';
    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';
    // Exclude self and current members
    final currentEmails = _members
        .map((m) => ((m['email'] ?? _emailOf(m['user'])) as String).toLowerCase())
        .toSet();

    final available = people.where((p) {
      final e = (p['email'] ?? '').toString().toLowerCase();
      return e.isNotEmpty && e != myEmail && !currentEmails.contains(e);
    }).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final filtered = available.where((p) {
            if (search.isEmpty) return true;
            final e = (p['email'] ?? '').toString().toLowerCase();
            final n = (p['name'] ?? p['username'] ?? '').toString().toLowerCase();
            return e.contains(search.toLowerCase()) || n.contains(search.toLowerCase());
          }).toList();
          final allSel = filtered.isNotEmpty && filtered.every((p) => picked.contains((p['email'] ?? '').toString()));
          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                      if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                    ])),
                    if (picked.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('${picked.length} selected', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 4),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    onChanged: (v) => setSheet(() => search = v),
                    style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                    decoration: InputDecoration(
                      hintText: 'Search by name or email...',
                      hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                      prefixIcon: Icon(Icons.search_rounded, color: AppThemeColors.mutedText(ctx)),
                      filled: true,
                      fillColor: AppThemeColors.surfaceBg(ctx),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Text('${filtered.length} available', style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx))),
                    const Spacer(),
                    if (filtered.isNotEmpty)
                      TextButton(
                        onPressed: () => setSheet(() {
                          if (allSel) {
                            for (final p in filtered) picked.remove((p['email'] ?? '').toString());
                          } else {
                            for (final p in filtered) {
                              final e = (p['email'] ?? '').toString();
                              if (e.isNotEmpty && !picked.contains(e)) picked.add(e);
                            }
                          }
                        }),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text(allSel ? 'Deselect All' : 'Select All', style: const TextStyle(color: AppColors.cyan, fontSize: 12)),
                      ),
                  ]),
                ),
                Divider(height: 1, color: AppThemeColors.divider(ctx)),
                Expanded(
                  child: filtered.isEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person_search_rounded, size: 48, color: AppThemeColors.mutedText(ctx)),
                          const SizedBox(height: 12),
                          Text(search.isEmpty ? 'No people available' : 'No match for "$search"',
                            style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 14), textAlign: TextAlign.center),
                        ]),
                      ))
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx)),
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          final email = (p['email'] ?? '').toString();
                          final name = (p['name'] ?? p['username'] ?? '').toString();
                          final isSel = picked.contains(email);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                              child: Text(name.isNotEmpty ? name[0].toUpperCase() : (email.isNotEmpty ? email[0].toUpperCase() : '?'),
                                style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(name.isNotEmpty ? name : email,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
                            subtitle: name.isNotEmpty ? Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))) : null,
                            trailing: Checkbox(value: isSel, activeColor: AppColors.cyan,
                              onChanged: (_) => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); })),
                            onTap: () => setSheet(() { if (isSel) picked.remove(email); else picked.add(email); }),
                          );
                        },
                      ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      picked.isEmpty ? 'Done' : 'Add ${picked.length} Member${picked.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    return picked;
  }

  // Groups two-tab picker (adapted from community picker pattern).
  Future<void> _showGroupMemberPicker() async {
    if (_userGroups.isEmpty) {
      await _loadGroups();
      if (!mounted) return;
    }
    if (_userGroups.isEmpty) {
      _showError('No groups found. Join or create a group first.');
      return;
    }

    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';
    final currentEmails = _members
        .map((m) => ((m['email'] ?? _emailOf(m['user'])) as String).toLowerCase())
        .toSet();
    final List<String> picked = [];
    int modeTab = 0;

    String getGMemberEmail(dynamic m) {
      if (m is Map) return (m['email'] ?? _emailOf(m['user'] ?? m)).toLowerCase().trim();
      return '';
    }
    String getGMemberName(dynamic m) {
      if (m is Map) return (m['name'] ?? (m['user'] is Map ? m['user']['name'] : '') ?? '').toString();
      return '';
    }
    List<Map<String, dynamic>> getGroupMembers(Map<String, dynamic> g) {
      final raw = g['members'];
      if (raw is! List) return [];
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) {
        final e = getGMemberEmail(m);
        return e.isNotEmpty && e != myEmail && !currentEmails.contains(e) && m['leftAt'] == null;
      }).toList();
    }
    Color parseGroupColor(dynamic v) {
      try {
        if (v is String && v.startsWith('#')) return Color(int.parse('FF${v.replaceFirst('#', '')}', radix: 16));
      } catch (_) {}
      return AppColors.cyan;
    }

    final otherGroups = _userGroups.where((g) => (g['_id'] ?? '').toString() != widget.groupId).toList();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final List<Map<String, dynamic>> allPickMembers = [];
          if (modeTab == 1) {
            final seen = <String>{};
            for (final g in otherGroups) {
              for (final m in getGroupMembers(g)) {
                final e = getGMemberEmail(m);
                if (e.isNotEmpty && seen.add(e)) allPickMembers.add(m);
              }
            }
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.82, minChildSize: 0.5, maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(color: AppThemeColors.cardBg(ctx), borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.group_work_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Add from Groups', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                      Text('${otherGroups.length} group${otherGroups.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                    ])),
                    if (picked.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('${picked.length} selected', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 4),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(child: GestureDetector(
                        onTap: () => setSheet(() => modeTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(gradient: modeTab == 0 ? const LinearGradient(colors: [AppColors.cyan, AppColors.blue]) : null, borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.group_work_rounded, size: 16, color: modeTab == 0 ? Colors.white : AppThemeColors.secondaryText(ctx)),
                            const SizedBox(width: 6),
                            Text('Choose Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: modeTab == 0 ? Colors.white : AppThemeColors.secondaryText(ctx))),
                          ]),
                        ),
                      )),
                      Expanded(child: GestureDetector(
                        onTap: () => setSheet(() => modeTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(gradient: modeTab == 1 ? const LinearGradient(colors: [AppColors.cyan, AppColors.blue]) : null, borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.person_search_rounded, size: 16, color: modeTab == 1 ? Colors.white : AppThemeColors.secondaryText(ctx)),
                            const SizedBox(width: 6),
                            Text('Pick Members', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: modeTab == 1 ? Colors.white : AppThemeColors.secondaryText(ctx))),
                          ]),
                        ),
                      )),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: AppThemeColors.divider(ctx)),
                Expanded(
                  child: modeTab == 0
                    ? (otherGroups.isEmpty
                      ? Center(child: Text('No other groups found', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: otherGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, gi) {
                            final g = otherGroups[gi];
                            final gName = (g['title'] ?? 'Group').toString();
                            final gMembers = getGroupMembers(g);
                            final gColor = parseGroupColor(g['color']);
                            final allAdded = gMembers.isNotEmpty && gMembers.every((m) => picked.contains(getGMemberEmail(m)));
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppThemeColors.border(ctx))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(gradient: LinearGradient(colors: [gColor.withValues(alpha: 0.8), gColor], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(13)),
                                    child: Center(child: Text(gName.isNotEmpty ? gName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(gName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                                    Text('${gMembers.length} addable member${gMembers.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                                  ])),
                                  TextButton.icon(
                                    onPressed: gMembers.isEmpty ? null : () => setSheet(() {
                                      if (allAdded) { for (final m in gMembers) picked.remove(getGMemberEmail(m)); }
                                      else { for (final m in gMembers) { final e = getGMemberEmail(m); if (e.isNotEmpty && !picked.contains(e)) picked.add(e); } }
                                    }),
                                    icon: Icon(allAdded ? Icons.remove_circle_outline : Icons.group_add, size: 16, color: allAdded ? Colors.orange : AppColors.cyan),
                                    label: Text(allAdded ? 'Deselect All' : 'Add All', style: TextStyle(fontSize: 12, color: allAdded ? Colors.orange : AppColors.cyan)),
                                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                  ),
                                ]),
                                if (gMembers.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(spacing: 8, runSpacing: 6, children: gMembers.map((m) {
                                    final e = getGMemberEmail(m);
                                    final n = getGMemberName(m);
                                    final isSel = picked.contains(e);
                                    return GestureDetector(
                                      onTap: () => setSheet(() { if (isSel) picked.remove(e); else picked.add(e); }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isSel ? AppColors.cyan.withValues(alpha: 0.15) : AppThemeColors.cardBg(ctx),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: isSel ? AppColors.cyan : AppThemeColors.border(ctx)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          if (isSel) ...[const Icon(Icons.check, size: 12, color: AppColors.cyan), const SizedBox(width: 4)],
                                          Text(n.isNotEmpty ? n.split(' ')[0] : e.split('@')[0],
                                            style: TextStyle(fontSize: 12, color: isSel ? AppColors.cyan : AppThemeColors.primaryText(ctx), fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                                        ]),
                                      ),
                                    );
                                  }).toList()),
                                ],
                              ]),
                            );
                          },
                        ))
                    : (allPickMembers.isEmpty
                      ? Center(child: Text('No members available', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: allPickMembers.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx)),
                          itemBuilder: (_, i) {
                            final m = allPickMembers[i];
                            final e = getGMemberEmail(m);
                            final n = getGMemberName(m);
                            final isSel = picked.contains(e);
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              leading: CircleAvatar(backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                                child: Text(n.isNotEmpty ? n[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold))),
                              title: Text(n.isNotEmpty ? n : e, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(ctx))),
                              subtitle: n.isNotEmpty ? Text(e, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))) : null,
                              trailing: Checkbox(value: isSel, activeColor: AppColors.cyan,
                                onChanged: (_) => setSheet(() { if (isSel) picked.remove(e); else picked.add(e); })),
                              onTap: () => setSheet(() { if (isSel) picked.remove(e); else picked.add(e); }),
                            );
                          },
                        )),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 4),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(picked.isEmpty ? 'Done' : 'Add ${picked.length} Member${picked.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

    for (final email in picked) {
      if (!mounted) break;
      await _addMember(email, silent: true);
    }
    if (mounted && picked.isNotEmpty) {
      _showSnack('${picked.length} member${picked.length == 1 ? '' : 's'} added', success: true);
      await _refresh();
    }
  }

  // Builds an "All Sources" combined list: friends + counterparties + all community/group members.
  Future<void> _showAllSourcesPicker() async {
    // Load all sources concurrently
    await Future.wait([
      if (_friends.isEmpty) _loadFriends(),
      if (_counterparties.isEmpty) _loadCounterparties(),
      if (_userCommunities.isEmpty) _loadCommunities(),
      if (_userGroups.isEmpty) _loadGroups(),
    ]);
    if (!mounted) return;

    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';
    final currentEmails = _members
        .map((m) => ((m['email'] ?? _emailOf(m['user'])) as String).toLowerCase())
        .toSet();

    final Map<String, Map<String, dynamic>> allPeople = {};
    void addPerson(String email, String name) {
      final e = email.toLowerCase().trim();
      if (e.isEmpty || e == myEmail || currentEmails.contains(e)) return;
      allPeople.putIfAbsent(e, () => {'email': e, 'name': name});
    }
    for (final f in _friends) addPerson((f['email'] ?? '').toString(), (f['name'] ?? f['username'] ?? '').toString());
    for (final c in _counterparties) addPerson((c['email'] ?? '').toString(), (c['name'] ?? c['username'] ?? '').toString());
    for (final comm in _userCommunities) {
      for (final m in List<dynamic>.from(comm['members'] ?? [])) {
        if (m is Map) {
          final u = m['user'];
          final e = (u is Map ? u['email'] : m['email'] ?? '').toString();
          final n = (u is Map ? (u['name'] ?? u['username'] ?? '') : m['name'] ?? '').toString();
          addPerson(e, n);
        }
      }
    }
    for (final g in _userGroups) {
      if ((g['_id'] ?? '') == widget.groupId) continue;
      for (final m in List<dynamic>.from(g['members'] ?? [])) {
        if (m is Map && m['leftAt'] == null) {
          final e = (m['email'] ?? _emailOf(m['user'] ?? m)).toString();
          final n = (m['name'] ?? (m['user'] is Map ? m['user']['name'] : '') ?? '').toString();
          addPerson(e, n);
        }
      }
    }

    final picked = await _showPeoplePicker(
      title: 'All Sources',
      icon: Icons.people_alt_rounded,
      people: allPeople.values.toList(),
      subtitle: '${allPeople.length} people from friends, groups & communities',
    );
    for (final email in picked) {
      if (!mounted) break;
      await _addMember(email, silent: true);
    }
    if (mounted && picked.isNotEmpty) {
      _showSnack('${picked.length} member${picked.length == 1 ? '' : 's'} added', success: true);
      await _refresh();
    }
  }

  Future<void> _showCommunityMemberPicker() async {
    if (_userCommunities.isEmpty) {
      await _loadCommunities();
      if (!mounted) return;
    }
    if (_userCommunities.isEmpty) {
      _showError('No communities found. Join or create a community first.');
      return;
    }

    final myEmail = Provider.of<SessionProvider>(context, listen: false)
        .user?['email']?.toString().toLowerCase() ?? '';

    final List<String> picked = [];
    int modeTab = 0;
    String? statusMsg;

    String getCMemberEmail(Map m) {
      final u = m['user'];
      if (u is Map) return (u['email'] ?? '').toString().toLowerCase().trim();
      return '';
    }
    String getCMemberName(Map m) {
      final u = m['user'];
      if (u is Map) return (u['name'] ?? u['username'] ?? '').toString();
      return '';
    }
    List<Map> getCMembers(Map c) {
      final raw = c['members'];
      if (raw is! List) return [];
      return raw.whereType<Map>().where((m) {
        final e = getCMemberEmail(m);
        return e.isNotEmpty && e != myEmail;
      }).toList();
    }
    Color parseCColor(dynamic v) {
      try {
        if (v is String && v.startsWith('#')) return Color(int.parse('FF${v.replaceFirst('#', '')}', radix: 16));
      } catch (_) {}
      return AppColors.cyan;
    }

    Widget buildModeTab(BuildContext ctx, int current, int value, IconData icon, String label, VoidCallback onTap) {
      final isActive = current == value;
      return Expanded(child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: isActive ? const LinearGradient(colors: [AppColors.cyan, AppColors.blue]) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : AppThemeColors.secondaryText(ctx)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppThemeColors.secondaryText(ctx))),
          ]),
        ),
      ));
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final List<Map<String, dynamic>> allPickMembers = [];
          if (modeTab == 1) {
            final seen = <String>{};
            for (final c in _userCommunities) {
              for (final m in getCMembers(c)) {
                final me = getCMemberEmail(m);
                if (me.isNotEmpty && seen.add(me)) allPickMembers.add(Map<String, dynamic>.from(m));
              }
            }
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            builder: (_, scrollCtrl) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Add from Communities', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                      Text('${_userCommunities.length} communit${_userCommunities.length == 1 ? 'y' : 'ies'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                    ])),
                    if (picked.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                        child: Text('${picked.length} selected', style: const TextStyle(color: AppColors.cyan, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: AppThemeColors.secondaryText(ctx))),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      buildModeTab(ctx, modeTab, 0, Icons.hub_rounded, 'Choose Community', () => setSheet(() { modeTab = 0; statusMsg = null; })),
                      buildModeTab(ctx, modeTab, 1, Icons.person_search_rounded, 'Pick Members', () => setSheet(() { modeTab = 1; statusMsg = null; })),
                    ]),
                  ),
                ),
                if (statusMsg != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withValues(alpha: 0.3))),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(statusMsg!, style: const TextStyle(color: Colors.green, fontSize: 13))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 8),
                Divider(height: 1, color: AppThemeColors.divider(ctx)),
                Expanded(
                  child: modeTab == 0
                    ? ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: _userCommunities.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, ci) {
                          final c = _userCommunities[ci];
                          final cName = (c['name'] ?? 'Community').toString();
                          final cMembers = getCMembers(c);
                          final cColor = parseCColor(c['color']);
                          final allAdded = cMembers.isNotEmpty && cMembers.every((m) => picked.contains(getCMemberEmail(m)));
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppThemeColors.surfaceBg(ctx), borderRadius: BorderRadius.circular(18), border: Border.all(color: AppThemeColors.border(ctx))),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(gradient: LinearGradient(colors: [cColor.withValues(alpha: 0.8), cColor], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(13)),
                                  child: Center(child: Text(cName.isNotEmpty ? cName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(cName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                                  Text('${cMembers.length} member${cMembers.length == 1 ? '' : 's'}', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                                ])),
                                TextButton.icon(
                                  onPressed: cMembers.isEmpty ? null : () => setSheet(() {
                                    if (allAdded) {
                                      for (final m in cMembers) picked.remove(getCMemberEmail(m));
                                      statusMsg = 'Deselected all from $cName';
                                    } else {
                                      int added = 0;
                                      for (final m in cMembers) {
                                        final me = getCMemberEmail(m);
                                        if (me.isNotEmpty && !picked.contains(me)) { picked.add(me); added++; }
                                      }
                                      statusMsg = 'Selected $added from $cName';
                                    }
                                  }),
                                  icon: Icon(allAdded ? Icons.remove_circle_outline : Icons.group_add, size: 16, color: allAdded ? Colors.orange : AppColors.cyan),
                                  label: Text(allAdded ? 'Deselect All' : 'Add All', style: TextStyle(fontSize: 12, color: allAdded ? Colors.orange : AppColors.cyan)),
                                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                ),
                              ]),
                              if (cMembers.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8, runSpacing: 6,
                                  children: cMembers.map((m) {
                                    final me = getCMemberEmail(m);
                                    final mn = getCMemberName(m);
                                    final isSel = picked.contains(me);
                                    return GestureDetector(
                                      onTap: () => setSheet(() { if (isSel) picked.remove(me); else picked.add(me); }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isSel ? AppColors.cyan.withValues(alpha: 0.15) : AppThemeColors.cardBg(ctx),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: isSel ? AppColors.cyan : AppThemeColors.border(ctx)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          if (isSel) ...[const Icon(Icons.check, size: 12, color: AppColors.cyan), const SizedBox(width: 4)],
                                          Text(mn.isNotEmpty ? mn.split(' ')[0] : me.split('@')[0],
                                            style: TextStyle(fontSize: 12, color: isSel ? AppColors.cyan : AppThemeColors.primaryText(ctx), fontWeight: isSel ? FontWeight.w600 : FontWeight.normal)),
                                        ]),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ]),
                          );
                        },
                      )
                    : ListView.separated(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        itemCount: allPickMembers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = allPickMembers[i];
                          final me = getCMemberEmail(m);
                          final mn = getCMemberName(m);
                          final isSel = picked.contains(me);
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                              child: Text(mn.isNotEmpty ? mn[0].toUpperCase() : '?', style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(mn.isNotEmpty ? mn : me, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppThemeColors.primaryText(ctx))),
                            subtitle: mn.isNotEmpty ? Text(me, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))) : null,
                            trailing: Checkbox(value: isSel, activeColor: AppColors.cyan, onChanged: (_) => setSheet(() { if (isSel) picked.remove(me); else picked.add(me); })),
                            onTap: () => setSheet(() { if (isSel) picked.remove(me); else picked.add(me); }),
                          );
                        },
                      ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan, minimumSize: const Size.fromHeight(50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 4),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(picked.isEmpty ? 'Done' : 'Add ${picked.length} Member${picked.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );

    // Add each picked community member to the group silently, then refresh once
    for (final email in picked) {
      if (!mounted) break;
      await _addMember(email, silent: true);
    }
    if (mounted && picked.isNotEmpty) {
      _showSnack('${picked.length} member${picked.length == 1 ? '' : 's'} added', success: true);
      await _refresh();
    }
  }

  void _showAddMemberSheet() {
    _addEmailCtrl.clear();
    final t = AppLocalizations.of(context).t;

    Widget _srcBtn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.cyan.withValues(alpha: 0.07),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: AppColors.cyan, size: 22),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.w600), textAlign: TextAlign.center, maxLines: 2),
          ]),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 0, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.person_add_rounded, color: AppColors.cyan, size: 20),
              ),
              const SizedBox(width: 12),
              Text(t('add_member_label'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            ]),
            const SizedBox(height: 16),
            // Source buttons row (scrollable to prevent overflow)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _srcBtn(icon: Icons.people_rounded, label: 'Friends',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _loadFriends();
                    if (!mounted) return;
                    final picked = await _showPeoplePicker(
                      title: 'Add from Friends',
                      icon: Icons.people_rounded,
                      people: _friends,
                      subtitle: '${_friends.length} friend${_friends.length == 1 ? '' : 's'}',
                    );
                    for (final email in picked) { if (!mounted) break; await _addMember(email, silent: true); }
                    if (mounted && picked.isNotEmpty) { _showSnack('${picked.length} member${picked.length == 1 ? '' : 's'} added', success: true); await _refresh(); }
                  }),
                const SizedBox(width: 8),
                _srcBtn(icon: Icons.swap_horiz_rounded, label: 'Counter-\nparties',
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _loadCounterparties();
                    if (!mounted) return;
                    final people = _counterparties.map((c) => <String, dynamic>{
                      'email': (c['email'] ?? '').toString(),
                      'name': (c['name'] ?? c['username'] ?? '').toString(),
                    }).toList();
                    final picked = await _showPeoplePicker(
                      title: 'Add from Counterparties',
                      icon: Icons.swap_horiz_rounded,
                      people: people,
                      subtitle: '${people.length} counterpart${people.length == 1 ? 'y' : 'ies'}',
                    );
                    for (final email in picked) { if (!mounted) break; await _addMember(email, silent: true); }
                    if (mounted && picked.isNotEmpty) { _showSnack('${picked.length} member${picked.length == 1 ? '' : 's'} added', success: true); await _refresh(); }
                  }),
                const SizedBox(width: 8),
                _srcBtn(icon: Icons.hub_rounded, label: 'Communit-\nies',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCommunityMemberPicker();
                  }),
                const SizedBox(width: 8),
                _srcBtn(icon: Icons.group_work_rounded, label: 'Groups',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showGroupMemberPicker();
                  }),
                const SizedBox(width: 8),
                _srcBtn(icon: Icons.people_alt_rounded, label: 'All\nSources',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showAllSourcesPicker();
                  }),
              ]),
            ),
            const SizedBox(height: 16),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or enter email', style: TextStyle(fontSize: 12))),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _addEmailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: t('enter_member_email_hint'),
                prefixIcon: const Icon(Icons.email_outlined),
                filled: true,
                fillColor: AppThemeColors.surfaceBg(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.person_add_rounded),
                label: Text(t('add_member_label'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: () {
                  final email = _addEmailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    _showError(t('enter_a_valid_email_message'));
                    return;
                  }
                  Navigator.pop(ctx);
                  _addMember(email);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: const Color(0xFFD32F2F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
      ),
    );
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.info_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(msg,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
        backgroundColor: success ? const Color(0xFF2E7D32) : Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final activeCount =
        _members.where((m) => m['leftAt'] == null).length;
    final leftCount =
        _members.where((m) => m['leftAt'] != null).length;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Column(
        children: [
          // Plain profile-style header
          Container(
            color: AppThemeColors.cardBg(context),
            child: SafeArea(
              bottom: false,
              child: Column(children: [
                // Top bar: back + title + refresh
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
                  child: Row(children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppThemeColors.primaryText(context), size: 20),
                    ),
                    Expanded(child: Text(t('members_title_label'),
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)))),
                    if (_loading)
                      SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: AppColors.cyan, strokeWidth: 2)),
                    IconButton(
                      onPressed: _refresh,
                      icon: Icon(Icons.refresh_rounded, color: AppThemeColors.secondaryText(context), size: 22),
                    ),
                  ]),
                ),
                // Group avatar + name
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                      child: Text(
                        widget.groupTitle.isNotEmpty ? widget.groupTitle[0].toUpperCase() : 'G',
                        style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold, fontSize: 30),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(widget.groupTitle,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 3),
                    Text(widget.isCreator ? t('creator_label') : t('member_label'),
                      style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                  ]),
                ),
                // Stats row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _statCard('$activeCount', t('active_label'), Icons.check_circle_outline_rounded, Colors.green),
                    _statDivider(),
                    _statCard('$leftCount', t('left_label'), Icons.exit_to_app_rounded, AppThemeColors.mutedText(context)),
                    _statDivider(),
                    _statCard('${_members.length}', t('filter_all_label'), Icons.people_rounded, AppColors.cyan),
                    if (_pendingInvites.isNotEmpty) ...[
                      _statDivider(),
                      _statCard('${_pendingInvites.length}', t('pending_label'), Icons.mail_outline_rounded, Colors.orange),
                    ],
                  ]),
                ),
                // Add member button (creator only)
                if (widget.isCreator)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(t('add_member_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        onPressed: _showAddMemberSheet,
                      ),
                    ),
                  ),
                Divider(height: 1, color: AppThemeColors.divider(context)),
              ]),
            ),
          ),

          // Filter tab row
          Container(
            color: AppThemeColors.cardBg(context),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              _filterChip(t('active_label'), 'active'),
              const SizedBox(width: 8),
              _filterChip(t('left_label'), 'left'),
              const SizedBox(width: 8),
              _filterChip(t('filter_all_label'), 'all'),
            ]),
          ),

          // Member list
          Expanded(
            child: _error != null
                ? errorStateWidget(context, _error!, _refresh)
                : filtered.isEmpty && _pendingInvites.isEmpty && _declinedInvites.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            color: AppThemeColors.mutedText(context), size: 64),
                        const SizedBox(height: 8),
                        Text(t('no_members_in_view_message'),
                            style: TextStyle(
                                color: AppThemeColors.secondaryText(context))),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length
                        + (_pendingInvites.isNotEmpty ? _pendingInvites.length + 1 : 0)
                        + (_declinedInvites.isNotEmpty ? _declinedInvites.length + 1 : 0),
                    itemBuilder: (_, i) {
                      final pendingStart = filtered.length;
                      final pendingEnd = filtered.length + (_pendingInvites.isNotEmpty ? _pendingInvites.length + 1 : 0);
                      final declinedStart = pendingEnd;

                      // Pending invites section header
                      if (_pendingInvites.isNotEmpty && i == pendingStart) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.mail_outline_rounded, color: Color(0xFFFF9800), size: 13),
                                const SizedBox(width: 5),
                                Text('Invited (${_pendingInvites.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
                              ]),
                            ),
                          ]),
                        );
                      }
                      // Pending invite rows
                      if (_pendingInvites.isNotEmpty && i > pendingStart && i < pendingEnd) {
                        final inv = _pendingInvites[i - pendingStart - 1] as Map<String, dynamic>;
                        final invEmail = (inv['email'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFFF9800).withValues(alpha: 0.15),
                              child: Text(invEmail.isNotEmpty ? invEmail[0].toUpperCase() : '?',
                                style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(invEmail, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppThemeColors.primaryText(context)), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              const Text('Invite sent · awaiting', style: TextStyle(fontSize: 11, color: Color(0xFFFF9800), fontWeight: FontWeight.w500)),
                            ])),
                            if (widget.isCreator) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _addMember(invEmail),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('Re-invite', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Invited', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFF9800))),
                            ),
                          ]),
                        );
                      }
                      // Declined invites section header
                      if (_declinedInvites.isNotEmpty && i == declinedStart) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.cancel_outlined, color: Colors.red, size: 13),
                                const SizedBox(width: 5),
                                Text('Declined (${_declinedInvites.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red)),
                              ]),
                            ),
                          ]),
                        );
                      }
                      // Declined invite rows
                      if (_declinedInvites.isNotEmpty && i > declinedStart) {
                        final dec = _declinedInvites[i - declinedStart - 1] as Map<String, dynamic>;
                        final decEmail = (dec['email'] ?? '').toString();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.red.withValues(alpha: 0.12),
                              child: Text(decEmail.isNotEmpty ? decEmail[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(decEmail, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppThemeColors.primaryText(context)), overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              const Text('Invite declined', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w500)),
                            ])),
                            if (widget.isCreator) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _addMember(decEmail),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text('Re-invite', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.cyan)),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text('Declined', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.red)),
                            ),
                          ]),
                        );
                      }
                      // Normal member rows
                      final m = filtered[i] as Map<String, dynamic>;
                      final email = (m['email'] != null
                              ? m['email'].toString()
                              : _emailOf(m['user']));
                      final name = (m['name'] != null
                              ? m['name'].toString()
                              : _nameOf(m['user']));
                      final isLeft = m['leftAt'] != null;
                      final isMe = email.toLowerCase() ==
                          widget.userEmail.toLowerCase();
                      final isGroupCreator = email.toLowerCase() ==
                          widget.creatorEmail.toLowerCase();
                      final memberId = (m['_id'] ?? '').toString();
                      final profileImageUrl = (m['profileImage'] as String?) ?? '';
                      // Parse joined date
                      String joinedLabel = '';
                      final rawJoined = m['joinedAt'];
                      if (rawJoined != null) {
                        try {
                          final dt = DateTime.parse(rawJoined.toString()).toLocal();
                          joinedLabel = 'Joined ${_fmtDate(dt)}';
                        } catch (_) {}
                      }
                      final leftLabel = m['leftAt'] != null ? () {
                        try {
                          final dt = DateTime.parse(m['leftAt'].toString()).toLocal();
                          return 'Left ${_fmtDate(dt)}';
                        } catch (_) { return 'Left'; }
                      }() : '';

                      Widget avatar = ClipOval(
                        child: profileImageUrl.isNotEmpty
                          ? Image.network(profileImageUrl, width: 64, height: 64, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(email.isNotEmpty ? email[0].toUpperCase() : '?',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)))
                          : (memberId.isNotEmpty
                              ? Image.network('${ApiConfig.baseUrl}/api/users/$memberId/profile-image', width: 64, height: 64, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Text(email.isNotEmpty ? email[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)))
                              : Text(email.isNotEmpty ? email[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24))),
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppThemeColors.divider(context)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isLeft
                                ? AppThemeColors.surfaceBg(context)
                                : ah.avatarColor(email),
                              child: avatar,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(
                                        name.isNotEmpty ? name : email,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: isLeft ? AppThemeColors.mutedText(context) : AppThemeColors.primaryText(context),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isMe) _badge(t('you_label'), AppColors.cyan.withValues(alpha: 0.15), AppColors.cyan),
                                  ]),
                                  if (name.isNotEmpty) ...[
                                    const SizedBox(height: 1),
                                    Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)), overflow: TextOverflow.ellipsis),
                                  ],
                                  const SizedBox(height: 5),
                                  Wrap(spacing: 5, runSpacing: 4, children: [
                                    _statusBadge(isLeft),
                                    if (isGroupCreator) _badge(t('creator_label'), AppColors.cyan.withValues(alpha: 0.12), AppColors.cyan),
                                    if (m['joinedViaInvite'] == true) _badge('Via Invite', AppThemeColors.surfaceBg(context), AppThemeColors.secondaryText(context)),
                                  ]),
                                  if (joinedLabel.isNotEmpty || leftLabel.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      Icon(isLeft ? Icons.logout_rounded : Icons.calendar_today_rounded,
                                        size: 11, color: AppThemeColors.mutedText(context)),
                                      const SizedBox(width: 4),
                                      Text(isLeft ? leftLabel : joinedLabel,
                                        style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                    ]),
                                  ],
                                ],
                              ),
                            ),
                            if (widget.isCreator && !isMe) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: isLeft ? () => _addMember(email) : () => _removeMember(email),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isLeft
                                      ? Colors.green.withValues(alpha: 0.1)
                                      : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(isLeft ? Icons.person_add_rounded : Icons.person_remove_rounded,
                                      color: isLeft ? Colors.green : Colors.red, size: 14),
                                    const SizedBox(width: 4),
                                    Text(isLeft ? t('re_add_label') : t('remove'),
                                      style: TextStyle(
                                        color: isLeft ? Colors.green : Colors.red,
                                        fontSize: 12, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _statCard(String count, String label, IconData icon, Color accent) {
    return Expanded(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: accent, size: 18),
        const SizedBox(height: 2),
        Text(count, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        Text(label, style: TextStyle(fontSize: 10, color: AppThemeColors.mutedText(context), fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 36, color: AppThemeColors.divider(context));

  Widget _badge(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: fg, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusBadge(bool isLeft) {
    final t = AppLocalizations.of(context).t;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLeft
            ? (isDark ? Colors.grey.shade800 : Colors.grey.shade200)
            : (isDark ? Colors.green.shade900 : Colors.green.shade50),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isLeft ? t('left_label') : t('active_label'),
        style: TextStyle(
          fontSize: 11,
          color: isLeft
              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
              : (isDark ? Colors.green.shade300 : Colors.green.shade700),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : AppThemeColors.secondaryText(context),
            fontWeight: FontWeight.w600,
            fontSize: 13)),
      ),
    );
  }
}
