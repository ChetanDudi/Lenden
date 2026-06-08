import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import 'group_members_page.dart';
import 'group_expenses_page.dart';

const _kCardColors = [
  Color(0xFFFFF4E6), Color(0xFFE8F5E9), Color(0xFFFCE4EC),
  Color(0xFFE3F2FD), Color(0xFFFFF9C4), Color(0xFFF3E5F5),
];

String _fmtDt(dynamic dt) {
  if (dt == null) return '';
  try {
    final d = dt is String ? DateTime.parse(dt).toLocal() : dt as DateTime;
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year}  $h:$m $period';
  } catch (_) {
    return '';
  }
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

String _emailOf(dynamic field) {
  if (field == null) return '-';
  if (field is Map) return (field['email'] ?? '-').toString();
  return field.toString();
}

class GroupDetailPage extends StatefulWidget {
  final String groupId;
  final Map<String, dynamic> initialGroup;

  const GroupDetailPage({
    super.key,
    required this.groupId,
    required this.initialGroup,
  });

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  late Map<String, dynamic> _group;
  bool _loading = false;
  String? _userEmail;
  bool _isCreator = false;

  @override
  void initState() {
    super.initState();
    _group = widget.initialGroup;
    final session = Provider.of<SessionProvider>(context, listen: false);
    _userEmail = session.user?['email'] ?? '';
    final creatorEmail = _emailOf(_group['creator']).toLowerCase();
    _isCreator = creatorEmail == _userEmail!.toLowerCase();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/group-transactions/user-groups');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final groups =
            List<Map<String, dynamic>>.from(data['groups'] ?? []);
        final updated = groups.firstWhere(
          (g) => g['_id'].toString() == widget.groupId,
          orElse: () => _group,
        );
        if (mounted) setState(() => _group = updated);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _resolveEmail(dynamic userField) {
    final direct = _emailOf(userField);
    if (direct.contains('@')) return direct;
    for (final m in List<dynamic>.from(_group['members'] ?? [])) {
      // Primary: member sub-doc _id IS the user ObjectId
      final memberId = (m['_id'] ?? '').toString();
      if (memberId.isNotEmpty && memberId == direct) {
        final email = (m['email'] ?? '').toString();
        if (email.contains('@')) return email;
      }
      // Fallback: member has a separate user field
      final mUser = m['user'];
      final mId = mUser is Map
          ? (mUser['_id'] ?? mUser['id'] ?? '').toString()
          : (mUser ?? '').toString();
      if (mId.isNotEmpty && mId == direct) {
        final email = (m['email'] ?? _emailOf(mUser)).toString();
        if (email.contains('@')) return email;
      }
    }
    return direct;
  }

  Color get _groupColor {
    if (_group['color'] != null) {
      try {
        return Color(int.parse(
            _group['color'].toString().replaceFirst('#', '0xff')));
      } catch (_) {}
    }
    return const Color(0xFF00B4D8);
  }

  Future<void> _updateColor() async {
    Color picked = _groupColor;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Group Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final hexColor =
                  '#${picked.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              await ApiClient.post(
                '/api/group-transactions/${widget.groupId}/color',
                body: {'color': hexColor},
              );
              _refresh();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_rounded, color: Colors.red),
          const SizedBox(width: 8),
          const Text('Delete Group', style: TextStyle(color: Colors.red)),
        ]),
        content: Text(
          'Delete "${_group['title']}"? This cannot be undone.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    final res =
        await ApiClient.delete('/api/group-transactions/${widget.groupId}');
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      Navigator.pop(context, 'deleted');
    } else {
      _showError(jsonDecode(res.body)['error'] ?? 'Failed to delete');
    }
  }

  Future<void> _confirmLeave() async {
    // Check pending expenses
    final expenses = List<dynamic>.from(_group['expenses'] ?? []);
    double pendingAmount = 0;
    for (final exp in expenses) {
      for (final split in (exp['split'] ?? [])) {
        if (_emailOf(split['user']).toLowerCase() ==
            _userEmail!.toLowerCase()) {
          if (split['settled'] != true) {
            pendingAmount += ((split['amount'] ?? 0) as num).toDouble();
          }
        }
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: _tricolorBorderBox(
          radius: 22,
          child: Container(
            decoration: const BoxDecoration(color: Colors.white),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header band
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.exit_to_app_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'Leave "${_group['title']}"?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info items
                      _leaveInfoRow(
                        Icons.people_outline_rounded,
                        'You will be marked as "Left" in the group.',
                        Colors.blueGrey,
                      ),
                      const SizedBox(height: 8),
                      _leaveInfoRow(
                        Icons.receipt_long_rounded,
                        'Your balance across all expenses will be auto-settled.',
                        Colors.green[700]!,
                      ),
                      const SizedBox(height: 8),
                      _leaveInfoRow(
                        Icons.person_add_rounded,
                        'The creator can re-add you later — your history is preserved.',
                        Colors.purple[700]!,
                      ),
                      if (pendingAmount > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.orange[300]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_rounded,
                                  color: Colors.orange[700],
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'You have ₹${pendingAmount.toStringAsFixed(2)} in pending expenses. They will be auto-settled when you leave.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[800]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: _tricolorGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[700],
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10),
                              ),
                              icon: const Icon(
                                  Icons.exit_to_app_rounded,
                                  color: Colors.white,
                                  size: 18),
                              label: const Text('Leave',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              onPressed: () =>
                                  Navigator.pop(context, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
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
        '/api/group-transactions/${widget.groupId}/leave');
    if (!mounted) return;
    setState(() => _loading = false);
    if (res.statusCode == 200) {
      _showSnack('You have left the group.', success: true);
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context, 'left');
    } else {
      final body = jsonDecode(res.body);
      if (res.statusCode == 400 &&
          (body['error'] ?? '').toString().contains('pending')) {
        await ApiClient.post(
            '/api/group-transactions/${widget.groupId}/send-leave-request');
        _showSnack('Leave request sent to group members.', success: true);
      } else {
        _showError(body['error'] ?? 'Failed to leave group');
      }
    }
  }

  Widget _leaveInfoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: Colors.grey[800])),
        ),
      ],
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
        duration: const Duration(seconds: 5),
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
        backgroundColor:
            success ? const Color(0xFF2E7D32) : Colors.blue[700],
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(14),
        elevation: 6,
      ),
    );
  }

  // ─── Service bar items ───────────────────────────────────────────
  Widget _serviceChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Stat card ───────────────────────────────────────────────────
  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members =
        List<dynamic>.from(_group['members'] ?? []);
    final activeMembers =
        members.where((m) => m['leftAt'] == null).length;
    final expenses =
        List<dynamic>.from(_group['expenses'] ?? []);
    final title = _group['title'] ?? 'Group';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      body: Stack(
        children: [
          // Header wave
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: _WaveClipper(),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_groupColor, _groupColor.withValues(alpha: 0.6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)),
                        ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        onPressed: _refresh,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),

                // Group header card
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: _groupColor.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: _groupColor,
                          child: Text(
                            title.isNotEmpty
                                ? title[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 24,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                'by ${_emailOf(_group['creator'])}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600]),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (_isCreator)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _groupColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('You are the creator',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _groupColor,
                                          fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Horizontal Scrollable Service Bar ──────────────
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _serviceChip(
                        icon: Icons.people_alt_rounded,
                        label: 'Members',
                        color: const Color(0xFF1565C0),
                        badge: activeMembers,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupMembersPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                creatorEmail: _emailOf(_group['creator']),
                                initialMembers: members,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.receipt_long_rounded,
                        label: 'Expenses',
                        color: const Color(0xFF2E7D32),
                        badge: expenses.length,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.add_circle_rounded,
                        label: 'Add Expense',
                        color: const Color(0xFF00838F),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                                openAddExpense: true,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      _serviceChip(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Add Member',
                        color: const Color(0xFF6A1B9A),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupMembersPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                creatorEmail: _emailOf(_group['creator']),
                                initialMembers: members,
                                openAddMember: true,
                              ),
                            ),
                          );
                          _refresh();
                        },
                      ),
                      if (_isCreator)
                        _serviceChip(
                          icon: Icons.color_lens_rounded,
                          label: 'Color',
                          color: _groupColor,
                          onTap: _updateColor,
                        ),
                      if (!_isCreator)
                        _serviceChip(
                          icon: Icons.exit_to_app_rounded,
                          label: 'Leave',
                          color: Colors.orange.shade700,
                          onTap: _confirmLeave,
                        ),
                      if (_isCreator)
                        _serviceChip(
                          icon: Icons.delete_rounded,
                          label: 'Delete',
                          color: const Color(0xFFD32F2F),
                          onTap: _confirmDeleteGroup,
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Horizontal Stats Row ─────────────────────────────
                SizedBox(
                  height: 140,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _statCard(
                          '$activeMembers', 'Members',
                          Icons.people_rounded,
                          const Color(0xFF1565C0)),
                      _statCard(
                          '${expenses.length}', 'Expenses',
                          Icons.receipt_rounded,
                          const Color(0xFF2E7D32)),
                      _statCard(
                          '${members.where((m) => m['leftAt'] != null).length}',
                          'Left',
                          Icons.person_off_rounded,
                          Colors.orange),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Recent Expenses Preview ──────────────────────────
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('Recent Expenses',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupExpensesPage(
                                groupId: widget.groupId,
                                groupTitle: title,
                                isCreator: _isCreator,
                                userEmail: _userEmail ?? '',
                                initialExpenses: expenses,
                                initialMembers: members,
                              ),
                            ),
                          );
                          _refresh();
                        },
                        child: const Text('See all →',
                            style:
                                TextStyle(color: Color(0xFF00B4D8))),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: expenses.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long,
                                  color: Colors.grey[300], size: 64),
                              const SizedBox(height: 8),
                              Text('No expenses yet',
                                  style:
                                      TextStyle(color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16),
                          itemCount: expenses.length > 5
                              ? 5
                              : expenses.length,
                          itemBuilder: (_, i) {
                            final e = expenses[i]
                                as Map<String, dynamic>;
                            final amount =
                                (e['amount'] ?? 0).toString();
                            final currency =
                                e['currency'] ?? 'INR';
                            final currencySymbol =
                                currency == 'INR'
                                    ? '₹'
                                    : currency == 'USD'
                                        ? '\$'
                                        : currency == 'EUR'
                                            ? '€'
                                            : currency == 'GBP'
                                                ? '£'
                                                : currency;
                            return _tricolorBorderBox(
                              margin: const EdgeInsets.only(bottom: 10),
                              radius: 16,
                              child: Container(
                              color: _kCardColors[i % _kCardColors.length],
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32)
                                          .withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.receipt_outlined,
                                        color: Color(0xFF2E7D32),
                                        size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e['description'] ?? '-',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w600,
                                              fontSize: 14),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          'by ${_resolveEmail(e['addedBy'])}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[500]),
                                          overflow:
                                              TextOverflow.ellipsis,
                                        ),
                                        if ((e['createdAt'] ?? e['date']) != null) ...[
                                          const SizedBox(height: 2),
                                          Row(children: [
                                            Icon(Icons.access_time_rounded,
                                                size: 11,
                                                color: Colors.grey[400]),
                                            const SizedBox(width: 3),
                                            Flexible(
                                              child: Text(
                                                _fmtDt(e['createdAt'] ?? e['date']),
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[400]),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '$currencySymbol$amount',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF2E7D32)),
                                  ),
                                ],
                              ),
                            ),
                          );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.85,
        size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.55,
        size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}
