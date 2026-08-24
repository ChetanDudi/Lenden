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

Widget _tricolorBorderBox({
  required Widget child,
  double radius = 18,
  double borderWidth = 2,
  EdgeInsetsGeometry? margin,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      gradient: AppColors.tricolorGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    padding: EdgeInsets.all(borderWidth),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius - borderWidth),
      child: child,
    ),
  );
}

class GroupMembersPage extends StatefulWidget {
  final String groupId;
  final String groupTitle;
  final bool isCreator;
  final String userEmail;
  final String creatorEmail;
  final List<dynamic> initialMembers;
  final bool openAddMember;

  const GroupMembersPage({
    super.key,
    required this.groupId,
    required this.groupTitle,
    required this.isCreator,
    required this.userEmail,
    required this.creatorEmail,
    required this.initialMembers,
    this.openAddMember = false,
  });

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  late List<dynamic> _members;
  bool _loading = false;
  String? _error;
  String _filter = 'active';
  final _addEmailCtrl = TextEditingController();
  List<Map<String, dynamic>> _userCommunities = [];

  @override
  void initState() {
    super.initState();
    _members = List<dynamic>.from(widget.initialMembers);
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
          setState(() =>
              _members = List<dynamic>.from(group['members'] ?? []));
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
      if (!silent) {
        _showSnack(t('member_added_message'), success: true);
        _refresh();
      }
    } else {
      _showError(body['error'] ?? t('failed_to_add_member_message'));
    }
  }

  Future<void> _removeMember(String email) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _tricolorBorderBox(
          radius: 20,
          child: Container(
            color: AppThemeColors.cardBg(context),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeColors.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 0,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: const BoxDecoration(
                gradient: AppColors.tricolorGradient,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: AppColors.tricolorGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.person_add_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Text(t('add_member_label'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
              const SizedBox(height: 16),
              TextField(
                controller: _addEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: t('enter_member_email_hint'),
                  prefixIcon: const Icon(Icons.email_outlined),
                  filled: true,
                  fillColor: AppThemeColors.surfaceBg(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.tricolorGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.person_add_rounded,
                        color: Colors.white),
                    label: Text(t('add_member_label'),
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
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
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCommunityMemberPicker();
                  },
                  icon: const Icon(Icons.hub_rounded, color: AppColors.cyan, size: 18),
                  label: const Text('Add from Communities', style: TextStyle(color: AppColors.cyan, fontSize: 14)),
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
      appBar: AppBar(
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('members_title_label'),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.groupTitle,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)),
              ),
            ),
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: Column(
        children: [
          // Stats bar with tricolor accent
          Container(
            color: const Color(0xFF1565C0),
            padding:
                const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Column(
              children: [
                // Tricolor stripe
                Container(
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(
                    gradient: AppColors.tricolorGradient,
                    borderRadius: BorderRadius.all(Radius.circular(4)),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statPill(t('active_count_label').replaceFirst('{count}', '$activeCount'), Colors.white),
                      const SizedBox(width: 8),
                      _statPill(t('left_count_label').replaceFirst('{count}', '$leftCount'), Colors.white70),
                      const SizedBox(width: 8),
                      _statPill(
                          t('total_count_label').replaceFirst('{count}', '${_members.length}'), Colors.white60),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          Container(
            color: AppThemeColors.cardBg(context),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(t('active_label'), 'active'),
                  const SizedBox(width: 8),
                  _filterChip(t('left_label'), 'left'),
                  const SizedBox(width: 8),
                  _filterChip(t('filter_all_label'), 'all'),
                ],
              ),
            ),
          ),

          // Member list
          Expanded(
            child: _error != null
                ? errorStateWidget(context, _error!, _refresh)
                : filtered.isEmpty
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
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
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

                      return _tricolorBorderBox(
                        margin: const EdgeInsets.only(bottom: 12),
                        radius: 18,
                        borderWidth: 2,
                        child: Container(
                          color: AppThemeColors.cardBg(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                // Avatar
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      decoration: isGroupCreator
                                          ? BoxDecoration(
                                              gradient: AppColors.tricolorGradient,
                                              shape: BoxShape.circle,
                                            )
                                          : null,
                                      padding: isGroupCreator
                                          ? const EdgeInsets.all(2)
                                          : EdgeInsets.zero,
                                      child: CircleAvatar(
                                        radius: 22,
                                        backgroundColor: isLeft
                                            ? Colors.grey[400]
                                            : ah.avatarColor(email),
                                        child: ClipOval(
                                          child: memberId.isNotEmpty
                                              ? Image.network(
                                                  '${ApiConfig.baseUrl}/api/users/$memberId/profile-image',
                                                  width: 44,
                                                  height: 44,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context,
                                                          error,
                                                          stackTrace) =>
                                                      Text(
                                                    email.isNotEmpty
                                                        ? email[0]
                                                            .toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16),
                                                  ),
                                                )
                                              : Text(
                                                  email.isNotEmpty
                                                      ? email[0].toUpperCase()
                                                      : '?',
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16),
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),

                                // Info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Name + badges
                                      Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 4,
                                        children: [
                                          Text(
                                            name.isNotEmpty ? name : email,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                              color: isLeft
                                                  ? Colors.grey
                                                  : AppThemeColors.primaryText(context),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (isGroupCreator)
                                            _badge(t('creator_label'),
                                                AppColors.tricolorOrange,
                                                Colors.white),
                                          if (isMe)
                                            _badge(t('you_label'),
                                                const Color(0xFF1565C0),
                                                Colors.white),
                                        ],
                                      ),
                                      if (name.isNotEmpty)
                                        Text(email,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppThemeColors.secondaryText(context)),
                                            overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 4),
                                      _statusBadge(isLeft),
                                    ],
                                  ),
                                ),

                                // Remove / Re-add button
                                if (widget.isCreator && !isMe)
                                  GestureDetector(
                                    onTap: isLeft
                                        ? () => _addMember(email)
                                        : () => _removeMember(email),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        gradient: isLeft
                                            ? const LinearGradient(
                                                colors: [
                                                  Color(0xFF2E7D32),
                                                  Color(0xFF43A047)
                                                ],
                                              )
                                            : const LinearGradient(
                                                colors: [
                                                  Color(0xFFC62828),
                                                  Color(0xFFEF5350)
                                                ],
                                              ),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isLeft
                                                ? Icons.person_add_rounded
                                                : Icons.person_remove_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isLeft ? t('re_add_label') : t('remove'),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
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
      floatingActionButton: widget.isCreator
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.tricolorGradient,
                borderRadius: BorderRadius.circular(32),
              ),
              padding: const EdgeInsets.all(2),
              child: FloatingActionButton.extended(
                onPressed: _showAddMemberSheet,
                backgroundColor: const Color(0xFF6A1B9A),
                elevation: 0,
                icon: const Icon(Icons.person_add_rounded,
                    color: Colors.white),
                label: Text(t('add_member_label'),
                    style: const TextStyle(color: Colors.white)),
              ),
            )
          : null,
    );
  }

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLeft ? Colors.grey[200] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isLeft ? t('left_label') : t('active_label'),
        style: TextStyle(
          fontSize: 11,
          color: isLeft ? Colors.grey[600] : Colors.green[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statPill(String label, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: selected
          ? Container(
              decoration: BoxDecoration(
                gradient: AppColors.tricolorGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              padding: const EdgeInsets.all(2),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            )
          : Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
    );
  }
}
