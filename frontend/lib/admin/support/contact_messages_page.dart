import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class ContactMessagesPage extends StatefulWidget {
  const ContactMessagesPage({Key? key}) : super(key: key);

  @override
  State<ContactMessagesPage> createState() => _ContactMessagesPageState();
}

class _ContactMessagesPageState extends State<ContactMessagesPage> {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'all';
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollController = ScrollController();

  static const Map<String, Color> _statusColors = {
    'new': Colors.blue,
    'read': Colors.grey,
    'replied': Colors.green,
    'closed': Colors.red,
  };

  static const Map<String, IconData> _statusIcons = {
    'new': Icons.mark_email_unread_rounded,
    'read': Icons.mark_email_read_rounded,
    'replied': Icons.reply_rounded,
    'closed': Icons.do_not_disturb_rounded,
  };

  @override
  void initState() {
    super.initState();
    _fetchMessages(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore &&
        _hasMore) {
      _fetchMore();
    }
  }

  Future<void> _fetchMessages({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _messages = [];
      });
    }

    try {
      final statusParam =
          _statusFilter == 'all' ? '' : '&status=$_statusFilter';
      final response = await ApiClient.get(
        '/api/admin/contact-messages?page=$_page&limit=20$statusParam',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fetched =
            List<Map<String, dynamic>>.from(data['messages'] ?? []);
        setState(() {
          if (reset) {
            _messages = fetched;
          } else {
            _messages.addAll(fetched);
          }
          _hasMore = fetched.length == 20;
          _isLoading = false;
          _loadingMore = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _error =
              (data['message'] ?? 'Failed to load messages').toString();
          _isLoading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _fetchMore() async {
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _fetchMessages();
  }

  Future<void> _updateStatus(
      String id, String newStatus, String? replyNote) async {
    try {
      final body = <String, dynamic>{'status': newStatus};
      if (replyNote != null && replyNote.isNotEmpty) {
        body['replyNote'] = replyNote;
      }
      final response = await ApiClient.patch(
        '/api/admin/contact-messages/$id/status',
        body: body,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updated = data['message'] as Map<String, dynamic>?;
        if (updated != null) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['_id'] == id);
            if (idx != -1) _messages[idx] = updated;
          });
        }
        if (mounted) {
          showSnack(context, 'Status updated to $newStatus');
        }
      }
    } catch (_) {}
  }

  Future<bool> _sendReply(String id, String replyText) async {
    try {
      final response = await ApiClient.post(
        '/api/admin/contact-messages/$id/reply',
        body: {'replyText': replyText},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final updated = data['message'] as Map<String, dynamic>?;
        if (updated != null) {
          setState(() {
            final idx = _messages.indexWhere((m) => m['_id'] == id);
            if (idx != -1) _messages[idx] = updated;
          });
        }
        return true;
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          showSnack(context, (data['error'] ?? 'Failed to send reply').toString(), isError: true);
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Error: $e', isError: true);
      }
      return false;
    }
  }

  String _cleanIp(String ip) =>
      ip.startsWith('::ffff:') ? ip.substring(7) : ip;

  void _showMessageDetail(Map<String, dynamic> msg) {
    final t = AppLocalizations.of(context).t;
    final replyController = TextEditingController(
        text: (msg['replyNote'] as String?) ?? '');
    final id = msg['_id'] as String;
    String currentStatus = (msg['status'] as String?) ?? 'new';
    bool sendingReply = false;

    // Mark as read automatically if new
    if (currentStatus == 'new') {
      _updateStatus(id, 'read', null);
      currentStatus = 'read';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppThemeColors.divider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sender
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppColors.cyan.withValues(alpha: 0.15),
                            child: Text(
                              (msg['name'] as String? ?? 'U')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.cyan,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg['name'] ?? t('unknown'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppThemeColors.primaryText(context)),
                                ),
                                Text(
                                  msg['email'] ?? '',
                                  style: TextStyle(
                                      fontSize: 13, color: AppThemeColors.secondaryText(context)),
                                ),
                              ],
                            ),
                          ),
                          _buildStatusBadge(currentStatus),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Subject & Category
                      Text(t('subject'),
                          style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.secondaryText(context),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              msg['subject'] ?? t('general_inquiry'),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeColors.primaryText(context)),
                            ),
                          ),
                          if ((msg['category'] as String?) != null &&
                              (msg['category'] as String).isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.cyan
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.cyan
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                msg['category'] as String,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.cyan),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Message
                      Text(t('message'),
                          style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.secondaryText(context),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppThemeColors.surfaceBg(context),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppThemeColors.border(context)),
                        ),
                        child: Text(
                          msg['message'] ?? '',
                          style: TextStyle(
                              fontSize: 14,
                              color: AppThemeColors.primaryText(context),
                              height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Meta
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 13, color: AppThemeColors.mutedText(context)),
                          const SizedBox(width: 4),
                          Text(
                            _formatTime(msg['createdAt'] as String?),
                            style: TextStyle(
                                fontSize: 12, color: AppThemeColors.mutedText(context)),
                          ),
                          if (msg['ipAddress'] != null) ...[
                            const SizedBox(width: 12),
                            Icon(Icons.location_on_outlined,
                                size: 13, color: AppThemeColors.mutedText(context)),
                            const SizedBox(width: 4),
                            Text(
                              _cleanIp(msg['ipAddress'].toString()),
                              style: TextStyle(
                                  fontSize: 12, color: AppThemeColors.mutedText(context)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Reply section — one reply per message
                      if (currentStatus == 'replied' || replyController.text.isNotEmpty) ...[
                        // Already replied — show read-only view
                        Row(
                          children: [
                            Text(t('reply_sent'),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppThemeColors.secondaryText(context),
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded,
                                      size: 11, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(t('sent'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppThemeColors.tinted(context, light: Colors.green.shade50, dark: const Color(0xFF1A2E1F)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.reply_rounded,
                                      size: 14, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${t('admin_replied_to')} ${msg['email'] ?? t('user_label')}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                replyController.text.isNotEmpty
                                    ? replyController.text
                                    : '—',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: AppThemeColors.primaryText(context),
                                    height: 1.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppThemeColors.surfaceBg(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline_rounded,
                                  size: 14, color: AppThemeColors.mutedText(context)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t('reply_already_sent_notice'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppThemeColors.secondaryText(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Not yet replied — show input
                        Text(t('reply_to_user'),
                            style: TextStyle(
                                fontSize: 11,
                                color: AppThemeColors.secondaryText(context),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: replyController,
                          maxLines: 4,
                          style: TextStyle(color: AppThemeColors.primaryText(context)),
                          decoration: InputDecoration(
                            hintText: t('write_reply_hint'),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: AppThemeColors.border(context)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                  color: AppColors.cyan),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: sendingReply
                                ? null
                                : () async {
                                    final text =
                                        replyController.text.trim();
                                    if (text.isEmpty) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            t('write_reply_before_sending')),
                                        backgroundColor: Colors.orange,
                                        behavior: SnackBarBehavior.floating,
                                      ));
                                      return;
                                    }
                                    setModalState(
                                        () => sendingReply = true);
                                    final ok =
                                        await _sendReply(id, text);
                                    if (ok) {
                                      setModalState(() {
                                        sendingReply = false;
                                        currentStatus = 'replied';
                                      });
                                      if (ctx.mounted) {
                                        ScaffoldMessenger.of(ctx)
                                            .showSnackBar(SnackBar(
                                          content: Text(
                                              '${t('reply_sent_to')} ${msg['email']}'),
                                          backgroundColor: Colors.green,
                                          behavior:
                                              SnackBarBehavior.floating,
                                        ));
                                      }
                                    } else {
                                      setModalState(
                                          () => sendingReply = false);
                                    }
                                  },
                            icon: sendingReply
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(
                                                Colors.white)),
                                  )
                                : const Icon(Icons.send_rounded,
                                    size: 18),
                            label: Text(sendingReply
                                ? t('sending')
                                : t('send_reply_via_email')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Status actions
                      Text(t('update_status'),
                          style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.secondaryText(context),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['read', 'replied', 'closed']
                            .map((status) {
                          final color = _statusColors[status] ??
                              Colors.grey;
                          return GestureDetector(
                            onTap: () async {
                              await _updateStatus(
                                  id, status, replyController.text.trim());
                              setModalState(
                                  () => currentStatus = status);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                    color:
                                        color.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_statusIcons[status]!,
                                      color: color, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    status[0].toUpperCase() +
                                        status.substring(1),
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final color = _statusColors[status] ?? Colors.grey;
    final icon = _statusIcons[status] ?? Icons.help_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            status[0].toUpperCase() + status.substring(1),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(Map<String, dynamic> msg) {
    final t = AppLocalizations.of(context).t;
    final status = (msg['status'] as String?) ?? 'new';
    final isNew = status == 'new';
    final category = (msg['category'] as String?) ?? '';

    return GestureDetector(
      onTap: () => _showMessageDetail(msg),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: tricolorBorder(
          radius: 16,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          AppColors.cyan.withValues(alpha: 0.12),
                      child: Text(
                        (msg['name'] as String? ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  msg['name'] ?? t('unknown'),
                                  style: TextStyle(
                                    fontWeight: isNew
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: 14,
                                    color: AppThemeColors.primaryText(context),
                                  ),
                                ),
                              ),
                              _buildStatusBadge(status),
                            ],
                          ),
                          Text(
                            msg['email'] ?? '',
                            style: TextStyle(
                                fontSize: 12, color: AppThemeColors.secondaryText(context)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        msg['subject'] ?? t('general_inquiry'),
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13,
                            color: AppThemeColors.primaryText(context)),
                      ),
                    ),
                    if (category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.cyan
                                  .withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.cyan),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  msg['message'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTime(msg['createdAt'] as String?),
                  style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            t('contact_messages'),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => _fetchMessages(reset: true),
                      ),
                    ],
                  ),
                ),

                // Status filter chips
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: ['all', 'new', 'read', 'replied', 'closed']
                        .map((s) {
                      final isSelected = _statusFilter == s;
                      final color =
                          s == 'all' ? AppColors.cyan : (_statusColors[s] ?? Colors.grey);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _statusFilter = s);
                            _fetchMessages(reset: true);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? color : AppThemeColors.cardBg(context),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isSelected
                                      ? color
                                      : AppThemeColors.border(context)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (s != 'all')
                                  Icon(_statusIcons[s]!,
                                      size: 13,
                                      color: isSelected
                                          ? Colors.white
                                          : color),
                                if (s != 'all') const SizedBox(width: 5),
                                Text(
                                  s[0].toUpperCase() + s.substring(1),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? Colors.white
                                        : AppThemeColors.secondaryText(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Count
                if (!_isLoading && _error == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      '${_messages.length} ${_messages.length == 1 ? t('message_singular') : t('message_plural')}',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppThemeColors.secondaryText(context),
                          fontWeight: FontWeight.w500),
                    ),
                  ),

                const SizedBox(height: 8),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? errorStateWidget(context, _error!, () => _fetchMessages(reset: true))
                          : _messages.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox_rounded,
                                          size: 64,
                                          color: AppThemeColors.mutedText(context)),
                                      const SizedBox(height: 16),
                                      Text(
                                        _statusFilter == 'all'
                                            ? t('no_contact_messages')
                                            : '${t('no_status_messages')} ($_statusFilter)',
                                        style: TextStyle(
                                            fontSize: 17,
                                            color: AppThemeColors.secondaryText(context)),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () => _fetchMessages(reset: true),
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 24),
                                    itemCount: _messages.length +
                                        (_loadingMore ? 1 : 0),
                                    itemBuilder: (_, i) {
                                      if (i == _messages.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator()),
                                        );
                                      }
                                      return _buildMessageCard(
                                          _messages[i]);
                                    },
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
}
