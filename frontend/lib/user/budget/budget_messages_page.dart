import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';

class BudgetMessagesPage extends StatefulWidget {
  const BudgetMessagesPage({super.key});

  @override
  State<BudgetMessagesPage> createState() => _BudgetMessagesPageState();
}

class _BudgetMessagesPageState extends State<BudgetMessagesPage> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/budget/messages');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = json.decode(res.body) as Map<String, dynamic>;
        setState(() {
          _messages = List<Map<String, dynamic>>.from(body['messages'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _error = 'Failed to load messages'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Connection error'; _loading = false; });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await ApiClient.put('/api/budget/messages/$id/read', body: {});
      setState(() {
        final idx = _messages.indexWhere((m) => m['_id'] == id);
        if (idx != -1) _messages[idx] = {..._messages[idx], 'isRead': true};
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.put('/api/budget/messages/read-all', body: {});
      setState(() {
        _messages = _messages.map((m) => {...m, 'isRead': true}).toList();
      });
    } catch (_) {}
  }

  Future<void> _clearRead() async {
    try {
      await ApiClient.delete('/api/budget/messages');
      setState(() => _messages.removeWhere((m) => m['isRead'] == true));
    } catch (_) {}
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Clear all messages?', style: TextStyle(fontSize: context.sp(15), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
        content: Text('This will remove all budget limit messages.', style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear All', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.delete('/api/budget/messages?all=true');
      setState(() => _messages.clear());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _messages.where((m) => m['isRead'] != true).length;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: AppThemeColors.cardBg(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          color: AppThemeColors.primaryText(context),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Text('Budget Messages', style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text('$unreadCount', style: TextStyle(fontSize: context.sp(10), color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        actions: [
          if (_messages.isNotEmpty)
            PopupMenuButton<String>(
              color: AppThemeColors.cardBg(context),
              icon: Icon(Icons.more_vert, color: AppThemeColors.primaryText(context)),
              onSelected: (v) {
                if (v == 'read_all') _markAllRead();
                if (v == 'clear_read') _clearRead();
                if (v == 'clear_all') _clearAll();
              },
              itemBuilder: (_) => [
                if (unreadCount > 0)
                  PopupMenuItem(value: 'read_all', child: Text('Mark all as read', style: TextStyle(color: AppThemeColors.primaryText(context)))),
                PopupMenuItem(value: 'clear_read', child: Text('Clear read messages', style: TextStyle(color: AppThemeColors.primaryText(context)))),
                const PopupMenuItem(value: 'clear_all', child: Text('Clear all', style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : _error != null
              ? errorStateWidget(context, _error!, _fetch)
              : _messages.isEmpty
                  ? _buildEmpty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                      itemCount: _messages.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildMessageCard(context, _messages[i]),
                    ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: const Icon(Icons.check_circle_outline_rounded, size: 56, color: Colors.teal),
      ),
      const SizedBox(height: 16),
      Text('All budgets on track!', style: TextStyle(fontSize: context.sp(17), fontWeight: FontWeight.bold, color: Colors.teal)),
      const SizedBox(height: 6),
      Text('No budget limits have been exceeded this month.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: context.sp(12), color: AppThemeColors.secondaryText(context))),
    ]),
  );

  Widget _buildMessageCard(BuildContext context, Map<String, dynamic> msg) {
    final isRead   = msg['isRead'] == true;
    final type     = msg['type'] as String? ?? '';
    final spent    = (msg['amountSpent'] as num?)?.toDouble() ?? 0;
    final limit    = (msg['limit'] as num?)?.toDouble() ?? 0;
    final message  = msg['message'] as String? ?? '';
    final over     = spent - limit;
    final createdAt = msg['createdAt'] as String?;
    final date     = createdAt != null ? DateTime.tryParse(createdAt) : null;
    final dateStr  = date != null
        ? '${date.day}/${date.month}/${date.year}'
        : '';

    final (icon, color) = _iconColor(type);

    return GestureDetector(
      onTap: isRead ? null : () => _markRead(msg['_id'] as String),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead
              ? AppThemeColors.cardBg(context)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? AppThemeColors.border(context) : color.withValues(alpha: 0.35),
            width: isRead ? 1 : 1.5,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(message,
                  style: TextStyle(fontSize: context.sp(12), fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                      color: AppThemeColors.primaryText(context)))),
              if (!isRead)
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _pill(context, 'Spent: ₹${spent.toStringAsFixed(0)}', color),
              const SizedBox(width: 6),
              _pill(context, 'Limit: ₹${limit.toStringAsFixed(0)}', AppThemeColors.secondaryText(context)),
              const SizedBox(width: 6),
              _pill(context, '+₹${over.toStringAsFixed(0)} over', Colors.red),
            ]),
            if (dateStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(dateStr, style: TextStyle(fontSize: context.sp(10), color: AppThemeColors.secondaryText(context))),
            ],
            if (!isRead) ...[
              const SizedBox(height: 6),
              Text('Tap to mark as read', style: TextStyle(fontSize: context.sp(10), color: AppColors.cyan)),
            ],
          ])),
        ]),
      ),
    );
  }

  Widget _pill(BuildContext context, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: context.sp(9), color: color, fontWeight: FontWeight.w600)),
  );

  (IconData, Color) _iconColor(String type) {
    if (type == 'quick') return (Icons.flash_on_outlined, Colors.amber.shade700);
    if (type == 'secure') return (Icons.shield_outlined, Colors.teal);
    if (type == 'group' || type == 'group_specific') return (Icons.group_outlined, Colors.deepPurple);
    if (type == 'overall') return (Icons.account_balance_wallet_outlined, AppColors.cyan);
    if (type.startsWith('cat_')) return (Icons.category_outlined, Colors.orange);
    return (Icons.warning_amber_rounded, Colors.red);
  }
}
