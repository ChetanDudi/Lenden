import 'dart:convert';
import '../../../utils/avatar_helpers.dart' as ah;
import 'package:flutter/material.dart';
import '../../../utils/api_client.dart';
import '../../../api_config.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

String _nameOf(dynamic field) {
  if (field == null) return '';
  if (field is Map) return (field['name'] ?? '').toString();
  return '';
}

const _tricolorGradient = LinearGradient(
  colors: [Color(0xFFFF9933), Color(0xFFFFFFFF), Color(0xFF138808)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

Widget _tricolorBorderBox({
  required Widget child,
  double radius = 18,
  double borderWidth = 2,
  EdgeInsetsGeometry? margin,
}) {
  return Container(
    margin: margin,
    decoration: BoxDecoration(
      gradient: _tricolorGradient,
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
  String _filter = 'active';
  final _addEmailCtrl = TextEditingController();

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
    setState(() => _loading = true);
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
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addMember(String email) async {
    final res = await ApiClient.post(
      '/api/group-transactions/${widget.groupId}/add-member',
      body: {'email': email.trim().toLowerCase()},
    );
    if (!mounted) return;
    final t = AppLocalizations.of(context).t;
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 || res.statusCode == 201) {
      _showSnack(t('member_added_message'), success: true);
      _refresh();
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
                gradient: _tricolorGradient,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: _tricolorGradient,
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
                    gradient: _tricolorGradient,
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
                    gradient: _tricolorGradient,
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
            child: filtered.isEmpty
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
                                              gradient: _tricolorGradient,
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
                                                const Color(0xFFFF9933),
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
                gradient: _tricolorGradient,
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
                gradient: _tricolorGradient,
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
