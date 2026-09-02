import 'package:flutter/material.dart';
import '../../chats/group_chat_page.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/community_helpers.dart';
import 'group_detail_page.dart';

Widget _groupPlaceholder(Color color, String title) => Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [color, Color.lerp(color, Colors.black, 0.4)!],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  child: Center(
    child: Text(
      title.isNotEmpty ? title[0].toUpperCase() : 'G',
      style: const TextStyle(
        fontSize: 72,
        fontWeight: FontWeight.w900,
        color: Colors.white38,
        height: 1,
      ),
    ),
  ),
);

class GroupOverviewPage extends StatelessWidget {
  final Map<String, dynamic> group;
  final double userPendingBalance;
  final String Function(double) formatAmount;
  final double Function(Map<String, dynamic>) expenseAmountInInr;
  final double Function(Map<String, dynamic>) splitAmountInInr;
  final String currentUserEmail;
  final int unreadMessageCount;
  final VoidCallback onGenerateReceipt;
  final VoidCallback onAddExpense;
  final VoidCallback onShareInvite;
  final VoidCallback onShareAsNote;
  final VoidCallback onShareAsPdf;

  const GroupOverviewPage({
    super.key,
    required this.group,
    required this.userPendingBalance,
    required this.formatAmount,
    required this.expenseAmountInInr,
    required this.splitAmountInInr,
    required this.currentUserEmail,
    required this.unreadMessageCount,
    required this.onGenerateReceipt,
    required this.onAddExpense,
    required this.onShareInvite,
    required this.onShareAsNote,
    required this.onShareAsPdf,
  });

  // Safe avatar: shows profile pic with fallback letter on error
  Widget _avatar(String? picUrl, String label, double radius) {
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    final size = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.cyan.withValues(alpha: 0.18),
      child: ClipOval(
        child: (picUrl != null && picUrl.isNotEmpty)
            ? Image.network(
                picUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _initialText(initial, radius),
              )
            : _initialText(initial, radius),
      ),
    );
  }

  Widget _initialText(String initial, double radius) => Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.85,
            color: AppColors.cyan,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final title = group['title']?.toString() ?? 'Group';
    final members = group['members'] is List ? (group['members'] as List) : [];
    final expenses = group['expenses'] is List ? (group['expenses'] as List) : [];
    final creator = group['creator'];
    final creatorMap = creator is Map ? creator : null;
    final cPic = (creatorMap?['profileImage'] ?? creatorMap?['profilePicture'] ?? '').toString();
    final cName = (creatorMap?['name'] ?? creatorMap?['email'] ?? 'Unknown').toString();
    final cEmail = (creatorMap?['email'] ?? '').toString();

    final groupColor = group['color'] != null && group['color'].toString().isNotEmpty
        ? Color(int.parse(group['color'].toString().replaceFirst('#', '0xff')))
        : AppColors.cyan;
    final imgUrl = (group['groupImageUrl']?.toString() ?? '').isNotEmpty
        ? group['groupImageUrl'].toString()
        : defaultGroupImageUrl(title);

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: CustomScrollView(
        slivers: [
          // ── Header ──
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: groupColor,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              // Chat button with green unread dot
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_rounded, color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupChatPage(
                          groupTransactionId: group['_id']?.toString() ?? '',
                          groupTitle: title,
                          members: members,
                          groupImageUrl: group['groupImageUrl']?.toString(),
                        ),
                      ),
                    ),
                  ),
                  if (unreadMessageCount > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: Colors.green.shade500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (imgUrl.isNotEmpty)
                    Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _groupPlaceholder(groupColor, title),
                    )
                  else
                    _groupPlaceholder(groupColor, title),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0x22000000), Color(0xBB000000)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Summary card ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFC62828), Color(0xFF7B0000)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFFC62828).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('YOUR SHARE',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(formatAmount(userPendingBalance),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                        Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.3)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('BALANCE',
                                  style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.75),
                                      fontSize: 10,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Row(children: [
                                Icon(Icons.account_balance_wallet_outlined,
                                    color: Colors.white.withValues(alpha: 0.85), size: 14),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(formatAmount(userPendingBalance),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Action buttons ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      Row(children: [
                        _actionBtn(
                          context: context,
                          icon: Icons.receipt_long_rounded,
                          label: 'Generate Receipt',
                          color: const Color(0xFF2E7D32),
                          onTap: onGenerateReceipt,
                        ),
                        const SizedBox(width: 10),
                        _actionBtn(
                          context: context,
                          icon: Icons.add_circle_outline_rounded,
                          label: 'Add Expense',
                          color: const Color(0xFF0077B6),
                          onTap: onAddExpense,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _actionBtn(
                          context: context,
                          icon: Icons.person_add_rounded,
                          label: 'Invite',
                          color: const Color(0xFF00838F),
                          onTap: onShareInvite,
                        ),
                        const SizedBox(width: 10),
                        _actionBtn(
                          context: context,
                          icon: Icons.note_add_rounded,
                          label: 'Share as Note',
                          color: const Color(0xFF558B2F),
                          onTap: onShareAsNote,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        _actionBtn(
                          context: context,
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'Share as PDF',
                          color: const Color(0xFFC62828),
                          onTap: onShareAsPdf,
                        ),
                      ]),
                    ],
                  ),
                ),

                _divider(context),

                // ── Creator ──
                _sectionLabel(context, 'CREATOR'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      _avatar(cPic.isNotEmpty ? cPic : null, cName, 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(cName,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeColors.primaryText(context))),
                          if (cEmail.isNotEmpty && cEmail != cName)
                            Text(cEmail,
                                style: TextStyle(
                                    fontSize: 12, color: AppThemeColors.mutedText(context))),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Creator',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),

                _divider(context),

                // ── Members ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Text('MEMBERS',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppThemeColors.mutedText(context),
                              letterSpacing: 0.8)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${members.length}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                      ),
                      if (unreadMessageCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade500.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                                width: 7, height: 7,
                                decoration: BoxDecoration(
                                    color: Colors.green.shade500, shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text('$unreadMessageCount new',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ...members.map<Widget>((member) {
                  // getUserGroups returns flat members {_id, email, name, role, profileImage}
                  // getGroupById returns nested {_id, user: {_id, email, name}, role}
                  // Handle both shapes:
                  final u = member is Map
                      ? ((member['user'] is Map) ? member['user'] as Map : member)
                      : member;
                  final pic = (u is Map
                      ? (u['profileImage'] ?? u['profilePicture'] ?? '')
                      : '').toString();
                  final name =
                      (u is Map ? (u['name'] ?? u['email'] ?? 'Member') : 'Member').toString();
                  final email = (u is Map ? (u['email'] ?? '') : '').toString();
                  final role = (member is Map ? (member['role'] ?? '') : '').toString();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        _avatar(pic.isNotEmpty ? pic : null, name, 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppThemeColors.primaryText(context))),
                            if (email.isNotEmpty && email != name)
                              Text(email,
                                  style: TextStyle(
                                      fontSize: 12, color: AppThemeColors.mutedText(context))),
                          ]),
                        ),
                        if (role.isNotEmpty)
                          Text(role.toLowerCase(),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppThemeColors.mutedText(context),
                                  fontStyle: FontStyle.italic)),
                      ],
                    ),
                  );
                }),

                if (expenses.isNotEmpty) ...[
                  _divider(context),

                  // ── Recent Expenses ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                    child: Row(
                      children: [
                        Text('RECENT EXPENSES',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppThemeColors.mutedText(context),
                                letterSpacing: 0.8)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GroupDetailPage(
                                groupId: group['_id']?.toString() ?? '',
                                initialGroup: group,
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [Color(0xFF00B4D8), Color(0xFF0077B6)]),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                expenses.length > 3
                                    ? 'View All (${expenses.length})'
                                    : 'View Details',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.arrow_forward_ios_rounded,
                                  color: Colors.white, size: 10),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Column(
                      children: expenses.take(3).map<Widget>((expense) {
                        final expMap = expense is Map<String, dynamic>
                            ? expense
                            : Map<String, dynamic>.from(expense as Map);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppThemeColors.surfaceBg(context),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppThemeColors.border(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.receipt, color: AppColors.cyan, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    expMap['description']?.toString() ?? 'Expense',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  flex: 0,
                                  child: Text(
                                    formatAmount(expenseAmountInInr(expMap)),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green[700]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              _expenseAddedBy(context, expMap),
                              if (expMap['createdAt'] != null || expMap['date'] != null)
                                Row(children: [
                                  Icon(Icons.access_time,
                                      color: AppThemeColors.mutedText(context), size: 12),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _formatDt(expMap['createdAt'] ?? expMap['date']),
                                      style: TextStyle(
                                          color: AppThemeColors.mutedText(context),
                                          fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ]),
                              // Split details
                              if (expMap['split'] != null &&
                                  (expMap['split'] as List).isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.cyan.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: AppColors.cyan.withValues(alpha: 0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        const Icon(Icons.people_outline,
                                            color: AppColors.cyan, size: 14),
                                        const SizedBox(width: 4),
                                        const Text('Split Details',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.cyan)),
                                      ]),
                                      const SizedBox(height: 4),
                                      ...(expMap['split'] as List).map<Widget>((splitItem) {
                                        final si = splitItem is Map<String, dynamic>
                                            ? splitItem
                                            : Map<String, dynamic>.from(splitItem as Map);
                                        final memberEmail = _splitEmail(si, members);
                                        final isMe = memberEmail == currentUserEmail;
                                        final isSettled = si['settled'] == true;
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 2),
                                          child: Row(children: [
                                            Expanded(
                                              child: Text('• $memberEmail',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppThemeColors.secondaryText(
                                                          context),
                                                      fontWeight: isMe
                                                          ? FontWeight.bold
                                                          : FontWeight.normal),
                                                  overflow: TextOverflow.ellipsis),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              formatAmount(splitAmountInInr(si)),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isSettled
                                                    ? Colors.grey[500]
                                                    : (isMe
                                                        ? AppColors.cyan
                                                        : Colors.green[700]),
                                                decoration: isSettled
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                            ),
                                            if (isMe)
                                              const Text(' (you)',
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      color: AppColors.cyan,
                                                      fontStyle: FontStyle.italic)),
                                            if (isSettled)
                                              Text(' ✓',
                                                  style: TextStyle(
                                                      fontSize: 10, color: Colors.grey[500])),
                                          ]),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // ── View Full Details ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailPage(
                            groupId: group['_id']?.toString() ?? '',
                            initialGroup: group,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View Full Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.cyan,
                        side: BorderSide(color: AppColors.cyan.withValues(alpha: 0.45)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle:
                            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
      Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),
              decoration: BoxDecoration(
                color: AppThemeColors.surfaceBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _sectionLabel(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.mutedText(context),
                letterSpacing: 0.8)),
      );

  Widget _divider(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Divider(height: 1, color: AppThemeColors.divider(context)),
      );

  Widget _expenseAddedBy(BuildContext context, Map<String, dynamic> expense) {
    final addedBy = expense['addedBy'];
    String byText;
    if (addedBy is Map) {
      byText = (addedBy['name'] ?? addedBy['email'] ?? '').toString();
    } else {
      byText = addedBy?.toString() ?? '';
    }
    if (byText.isEmpty) return const SizedBox.shrink();
    return Text('Added by: $byText',
        style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 1);
  }

  String _splitEmail(Map<String, dynamic> splitItem, List members) {
    final userId = splitItem['user']?.toString();
    if (userId == null) return 'Unknown';
    final member = members.firstWhere(
      (m) {
        if (m is! Map) return false;
        final u = m['user'];
        final uId = (u is Map ? u['_id'] : u)?.toString();
        return uId == userId || m['_id']?.toString() == userId;
      },
      orElse: () => null,
    );
    if (member == null) return 'Unknown';
    final u = member is Map ? (member['user'] ?? member) : member;
    return (u is Map ? (u['email'] ?? u['name'] ?? 'Unknown') : 'Unknown').toString();
  }

  String _formatDt(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = raw is DateTime ? raw : DateTime.parse(raw.toString()).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '${dt.day}/${dt.month}/${dt.year} $h:$m $ampm';
    } catch (_) {
      return raw.toString();
    }
  }
}
