import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({Key? key}) : super(key: key);

  @override
  State<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<dynamic> _receivedNotifications = [];
  List<dynamic> _sentNotifications = [];
  bool _isLoadingReceived = true;
  bool _isLoadingSent = true;
  bool _viewAllReceived = false;
  bool _viewAllSent = false;
  bool _isSending = false;
  int _unreadCount = 0;
  String _recipientType = 'all-users';
  String _inboxCategory = 'all';
  String _sentCategory = 'all';
  String _deliveryStatus = 'sent';
  String? _audiencePreview;

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _recipientsController = TextEditingController();
  final _scheduledForController = TextEditingController();

  List<_NotificationCategoryChip> _categories(String Function(String) t) => [
        _NotificationCategoryChip(label: t('all'), value: 'all'),
        _NotificationCategoryChip(label: t('friends'), value: 'friend'),
        _NotificationCategoryChip(label: t('offers'), value: 'offer'),
        _NotificationCategoryChip(label: t('transactions'), value: 'transaction'),
        _NotificationCategoryChip(label: t('groups'), value: 'group'),
        _NotificationCategoryChip(label: t('system'), value: 'system'),
        _NotificationCategoryChip(label: t('general'), value: 'general'),
      ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchReceivedNotifications();
    _fetchSentNotifications();
    _markNotificationsAsRead();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    _recipientsController.dispose();
    _scheduledForController.dispose();
    super.dispose();
  }

  Color _getNoteColor(BuildContext context, int index) {
    final colors = [
      AppThemeColors.tinted(context,
          light: const Color(0xFFFFF4E6), dark: const Color(0xFF3A2E1A)),
      AppThemeColors.tinted(context,
          light: const Color(0xFFE8F5E9), dark: const Color(0xFF1E3320)),
      AppThemeColors.tinted(context,
          light: const Color(0xFFFCE4EC), dark: const Color(0xFF3A2230)),
      AppThemeColors.tinted(context,
          light: const Color(0xFFE3F2FD), dark: const Color(0xFF1B3A57)),
      AppThemeColors.tinted(context,
          light: const Color(0xFFFFF9C4), dark: const Color(0xFF3A3618)),
      AppThemeColors.tinted(context,
          light: const Color(0xFFF3E5F5), dark: const Color(0xFF332139)),
    ];
    return colors[index % colors.length];
  }

  void _calculateUnreadCount() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final userId = session.user!['_id'];
    _unreadCount = _receivedNotifications
        .where((notification) => !_isNotificationRead(notification, userId))
        .length;
  }

  Future<void> _markNotificationsAsRead() async {
    await ApiClient.post('/api/notifications/mark-as-read');
    if (!mounted) return;
    await _fetchReceivedNotifications(viewAll: _viewAllReceived);
  }

  bool _isNotificationRead(dynamic notification, dynamic userId) {
    final targetId = userId.toString();
    final senderId = notification['sender']?.toString();
    if (senderId == targetId) {
      return true;
    }
    final readBy = (notification['readBy'] as List<dynamic>? ?? const []);

    return readBy.any((entry) {
      if (entry is Map) {
        final entryId = entry['_id'] ?? entry['id'];
        return entryId?.toString() == targetId;
      }
      return entry.toString() == targetId;
    });
  }

  bool _canCurrentAdminManageNotification(dynamic notification) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentAdmin = session.user ?? const <String, dynamic>{};
    if (currentAdmin['isSuperAdmin'] == true) return true;
    final currentAdminId = currentAdmin['_id']?.toString();
    return notification['sender']?.toString() == currentAdminId;
  }

  Future<void> _fetchReceivedNotifications({bool viewAll = false}) async {
    setState(() => _isLoadingReceived = true);
    final url =
        viewAll ? '/api/notifications?viewAll=true' : '/api/notifications';
    final response = await ApiClient.get(url);

    if (response.statusCode == 200) {
      setState(() {
        _receivedNotifications = json.decode(response.body);
        _isLoadingReceived = false;
        if (viewAll) _viewAllReceived = true;
        _calculateUnreadCount();
      });
    } else {
      setState(() => _isLoadingReceived = false);
    }
  }

  Future<void> _fetchSentNotifications({bool viewAll = false}) async {
    setState(() => _isLoadingSent = true);
    final url = viewAll
        ? '/api/notifications/sent?viewAll=true'
        : '/api/notifications/sent';
    final response = await ApiClient.get(url);

    if (response.statusCode == 200) {
      setState(() {
        _sentNotifications = json.decode(response.body);
        _isLoadingSent = false;
        if (viewAll) _viewAllSent = true;
      });
    } else {
      setState(() => _isLoadingSent = false);
    }
  }

  String _categoryForNotification(dynamic notification) {
    final explicit = (notification['category'] ?? '').toString().toLowerCase();
    if (explicit.isNotEmpty) return explicit;

    final message = (notification['message'] ?? '').toString().toLowerCase();
    final recipientType =
        (notification['recipientType'] ?? '').toString().toLowerCase();
    final text = '$message $recipientType';

    if (text.contains('friend')) return 'friend';
    if (text.contains('offer')) return 'offer';
    if (text.contains('group') || text.contains('split')) return 'group';
    if (text.contains('transaction') ||
        text.contains('payment') ||
        text.contains('borrow') ||
        text.contains('lend') ||
        text.contains('due')) {
      return 'transaction';
    }
    if (text.contains('admin') ||
        text.contains('system') ||
        text.contains('alert') ||
        text.contains('security') ||
        text.contains('maintenance')) {
      return 'system';
    }
    return 'general';
  }

  List<dynamic> _filterByCategory(List<dynamic> notifications, String category) {
    if (category == 'all') return notifications;
    return notifications
        .where((notification) => _categoryForNotification(notification) == category)
        .toList();
  }

  Future<void> _sendNotification() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final recipients = _recipientsController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      final response = await ApiClient.post('/api/notifications', body: {
        'title': _titleController.text.trim(),
        'message': _messageController.text,
        'recipientType': _recipientType,
        'recipients': recipients,
        'category': _categoryFromComposer(),
        'deliveryStatus': _deliveryStatus,
        'scheduledFor': _scheduledForController.text.trim(),
      });

      if (response.statusCode == 201) {
        _titleController.clear();
        _messageController.clear();
        _recipientsController.clear();
        _scheduledForController.clear();
        _audiencePreview = null;
        await _fetchReceivedNotifications();
        await _fetchSentNotifications();
        if (mounted) {
          final t = AppLocalizations.of(context).t;
          showSnack(context, _deliveryStatus == 'scheduled'
              ? t('notification_scheduled_successfully')
              : _deliveryStatus == 'draft'
                  ? t('notification_draft_saved_successfully')
                  : t('notification_sent_successfully'));
        }
      } else if (mounted) {
        final t = AppLocalizations.of(context).t;
        String errorMessage = t('failed_to_send_notification');
        try {
          final errorBody = json.decode(response.body);
          if (errorBody['message'] != null) {
            errorMessage = errorBody['message'].toString();
          }
        } catch (_) {}
        showSnack(context, errorMessage, isError: true);
      }
    } catch (e) {
      if (mounted) {
        showSnack(context,
            '${AppLocalizations.of(context).t('unexpected_error_occurred')}: $e',
            isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _loadAudiencePreview() async {
    final recipients = _recipientsController.text.trim();
    final response = await ApiClient.get(
      '/api/notifications/audience-preview?recipientType=${Uri.encodeQueryComponent(_recipientType)}&recipients=${Uri.encodeQueryComponent(recipients)}',
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final t = AppLocalizations.of(context).t;
      setState(() {
        final invalid = List<String>.from(data['invalidRecipients'] ?? const []);
        _audiencePreview =
            '${data['estimatedAudience'] ?? 0} ${t('eligible_recipients')}${invalid.isNotEmpty ? ' • ${t('invalid_label')}: ${invalid.join(', ')}' : ''}';
      });
    }
  }

  Future<void> _pickScheduledDateTime() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null) return;
    final scheduled = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _scheduledForController.text = scheduled.toIso8601String();
    });
  }

  Future<void> _deleteNotification(String notificationId) async {
    final response = await ApiClient.delete('/api/notifications/$notificationId');
    if (response.statusCode == 200) {
      await _fetchReceivedNotifications();
      await _fetchSentNotifications();
      if (mounted) {
        showSnack(context,
            AppLocalizations.of(context).t('notification_deleted_successfully'));
      }
    } else if (mounted) {
      showSnack(context,
          '${AppLocalizations.of(context).t('failed_to_delete_notification')}: ${response.body}',
          isError: true);
    }
  }

  Future<void> _editNotification(dynamic notification) async {
    final t = AppLocalizations.of(context).t;
    final editMessageController =
        TextEditingController(text: notification['message'] ?? '');
    final editRecipientsController = TextEditingController(
      text: ((notification['recipients'] ?? []) as List<dynamic>)
          .map((r) => (r['email'] ?? r['username'] ?? '').toString())
          .where((text) => text.isNotEmpty)
          .join(', '),
    );
    String editRecipientType =
        (notification['recipientType'] ?? 'all-users').toString();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppThemeColors.cardBg(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(t('edit_notification'),
                  style: TextStyle(color: AppThemeColors.primaryText(context))),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: editMessageController,
                      maxLines: 4,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        labelText: t('message'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: editRecipientType,
                      decoration: InputDecoration(
                        labelText: t('audience'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'all-users',
                          child: Text(t('all_users')),
                        ),
                        DropdownMenuItem(
                          value: 'all-admins',
                          child: Text(t('all_admins')),
                        ),
                        DropdownMenuItem(
                          value: 'specific-users',
                          child: Text(t('specific_users')),
                        ),
                        DropdownMenuItem(
                          value: 'specific-admins',
                          child: Text(t('specific_admins')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => editRecipientType = value);
                        }
                      },
                    ),
                    if (editRecipientType == 'specific-users' ||
                        editRecipientType == 'specific-admins') ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: editRecipientsController,
                        style: TextStyle(color: AppThemeColors.primaryText(context)),
                        decoration: InputDecoration(
                          labelText: t('recipients_comma_separated'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(t('cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final recipients = editRecipientsController.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    final response = await ApiClient.put(
                      '/api/notifications/${notification['_id']}',
                      body: {
                        'message': editMessageController.text,
                        'recipientType': editRecipientType,
                        'recipients': recipients,
                      },
                    );
                    if (response.statusCode == 200) {
                      await _fetchReceivedNotifications();
                      await _fetchSentNotifications();
                      if (mounted) {
                        Navigator.pop(dialogContext);
                        showSnack(context, t('notification_updated_successfully'));
                      }
                    }
                  },
                  child: Text(t('save')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _categoryFromComposer() {
    final text = _messageController.text.toLowerCase();
    if (text.contains('friend')) return 'friend';
    if (text.contains('offer')) return 'offer';
    if (text.contains('group') || text.contains('split')) return 'group';
    if (text.contains('transaction') ||
        text.contains('payment') ||
        text.contains('due')) {
      return 'transaction';
    }
    if (text.contains('system') ||
        text.contains('admin') ||
        text.contains('alert') ||
        text.contains('security')) {
      return 'system';
    }
    return 'general';
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final userId = session.user!['_id'];
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
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: context.sh(156),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('admin_notifications'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildSummaryCard(context),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context).withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: AppColors.cyan,
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.cyan,
                        dividerColor: Colors.transparent,
                        overlayColor:
                            WidgetStateProperty.all(Colors.transparent),
                        tabs: [
                          Tab(text: t('inbox')),
                          Tab(text: t('sent')),
                          Tab(text: t('compose')),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      RefreshIndicator(
                        onRefresh: () => _fetchReceivedNotifications(
                          viewAll: _viewAllReceived,
                        ),
                        child: _buildNotificationsPanel(
                          context: context,
                          notifications: _receivedNotifications,
                          loading: _isLoadingReceived,
                          unreadUserId: userId,
                          selectedCategory: _inboxCategory,
                          onCategoryChanged: (value) {
                            setState(() => _inboxCategory = value);
                          },
                          emptyText: t('no_received_notifications_yet'),
                          allowViewAll:
                              _receivedNotifications.length == 3 && !_viewAllReceived,
                          onViewAll: () => _fetchReceivedNotifications(viewAll: true),
                          canManage: true,
                          showReadState: true,
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: () => _fetchSentNotifications(
                          viewAll: _viewAllSent,
                        ),
                        child: _buildNotificationsPanel(
                          context: context,
                          notifications: _sentNotifications,
                          loading: _isLoadingSent,
                          unreadUserId: userId,
                          selectedCategory: _sentCategory,
                          onCategoryChanged: (value) {
                            setState(() => _sentCategory = value);
                          },
                          emptyText: t('no_sent_notifications_yet'),
                          allowViewAll: _sentNotifications.length == 3 && !_viewAllSent,
                          onViewAll: () => _fetchSentNotifications(viewAll: true),
                          canManage: true,
                          showReadState: false,
                        ),
                      ),
                      _buildComposePanel(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatTile(
              context: context,
              title: t('unread'),
              value: '$_unreadCount',
              color: AppColors.cyan,
              icon: Icons.mark_email_unread_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              context: context,
              title: t('inbox'),
              value: '${_receivedNotifications.length}',
              color: Colors.orange,
              icon: Icons.inbox_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              context: context,
              title: t('sent'),
              value: '${_sentNotifications.length}',
              color: Colors.green,
              icon: Icons.send_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required BuildContext context,
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: AppThemeColors.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsPanel({
    required List<dynamic> notifications,
    required bool loading,
    required dynamic unreadUserId,
    required String selectedCategory,
    required ValueChanged<String> onCategoryChanged,
    required String emptyText,
    required bool allowViewAll,
    required VoidCallback onViewAll,
    required bool canManage,
    required bool showReadState,
    required BuildContext context,
  }) {
    final t = AppLocalizations.of(context).t;
    final filtered = _filterByCategory(notifications, selectedCategory);

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.cyan),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories(t).map((chip) {
              final selected = chip.value == selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(chip.label),
                  selected: selected,
                  onSelected: (_) => onCategoryChanged(chip.value),
                  selectedColor: AppColors.cyan,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.cyan,
                    fontWeight: FontWeight.w600,
                  ),
                  side: const BorderSide(color: AppColors.cyan),
                  backgroundColor: AppThemeColors.cardBg(context),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 72,
                    color: AppThemeColors.secondaryText(context),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    emptyText,
                    style: TextStyle(
                        fontSize: 16, color: AppThemeColors.secondaryText(context)),
                  ),
                ],
              ),
            ),
          ),
        ...filtered.asMap().entries.map((entry) {
          final index = entry.key;
          final notification = entry.value;
          return _buildNotificationCard(
            context: context,
            notification: notification,
            index: index,
            unreadUserId: unreadUserId,
            canManage: canManage,
            showReadState: showReadState,
          );
        }),
        if (allowViewAll)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ElevatedButton(
                onPressed: onViewAll,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(t('view_all_notifications')),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNotificationCard({
    required BuildContext context,
    required dynamic notification,
    required int index,
    required dynamic unreadUserId,
    required bool canManage,
    required bool showReadState,
  }) {
    final t = AppLocalizations.of(context).t;
    final category = _categoryForNotification(notification);
    final accent = _accentForCategory(category);
    final isRead = _isNotificationRead(notification, unreadUserId);
    final canEditThis = _canCurrentAdminManageNotification(notification);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _getNoteColor(context, index),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(_iconForCategory(category), color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _labelForCategory(t, category),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ),
                      if (showReadState && !isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.cyan,
                            shape: BoxShape.circle,
                          ),
                        ),
                      if (canManage && canEditThis)
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editNotification(notification);
                            } else if (value == 'delete') {
                              _deleteNotification(notification['_id']);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'edit', child: Text(t('edit'))),
                            PopupMenuItem(value: 'delete', child: Text(t('delete'))),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _prettifyMessage(
                        t, (notification['message'] ?? '').toString()),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _audienceLabel(t, notification),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.secondaryText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(t, notification['createdAt']),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposePanel(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('compose_notification'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('compose_notification_desc'),
                  style: TextStyle(color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: t('title'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    labelText: t('message'),
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _recipientType,
                  decoration: InputDecoration(
                    labelText: t('audience'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: 'all-users', child: Text(t('all_users'))),
                    DropdownMenuItem(value: 'all-admins', child: Text(t('all_admins'))),
                    DropdownMenuItem(
                      value: 'specific-users',
                      child: Text(t('specific_users')),
                    ),
                    DropdownMenuItem(
                      value: 'specific-admins',
                      child: Text(t('specific_admins')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _recipientType = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _deliveryStatus,
                  decoration: InputDecoration(
                    labelText: t('delivery'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: 'sent', child: Text(t('send_now'))),
                    DropdownMenuItem(value: 'draft', child: Text(t('save_draft'))),
                    DropdownMenuItem(
                      value: 'scheduled',
                      child: Text(t('schedule')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _deliveryStatus = value);
                    }
                  },
                ),
                if (_recipientType == 'specific-users' ||
                    _recipientType == 'specific-admins') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _recipientsController,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      labelText: t('recipients_comma_separated'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
                if (_deliveryStatus == 'scheduled') ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _scheduledForController,
                    readOnly: true,
                    onTap: _pickScheduledDateTime,
                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                    decoration: InputDecoration(
                      labelText: t('scheduled_for'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      suffixIcon: const Icon(Icons.schedule_rounded),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: const Color(0xFFF6FBFE),
                        dark: const Color(0xFF1B3A57)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _audiencePreview ?? t('audience_preview_placeholder'),
                          style: TextStyle(color: AppThemeColors.secondaryText(context)),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadAudiencePreview,
                        child: Text(t('preview')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _sendNotification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(t('send_notification')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _accentForCategory(String category) {
    switch (category) {
      case 'friend':
        return Colors.orange;
      case 'offer':
        return Colors.purple;
      case 'transaction':
        return Colors.teal;
      case 'group':
        return Colors.deepPurple;
      case 'system':
        return Colors.redAccent;
      default:
        return AppColors.cyan;
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'friend':
        return Icons.people_alt_outlined;
      case 'offer':
        return Icons.local_offer_outlined;
      case 'transaction':
        return Icons.receipt_long_outlined;
      case 'group':
        return Icons.groups_2_outlined;
      case 'system':
        return Icons.admin_panel_settings_outlined;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  String _labelForCategory(String Function(String) t, String category) {
    switch (category) {
      case 'friend':
        return t('friends').toUpperCase();
      case 'offer':
        return t('offers').toUpperCase();
      case 'transaction':
        return t('transactions').toUpperCase();
      case 'group':
        return t('groups').toUpperCase();
      case 'system':
        return t('system').toUpperCase();
      default:
        return t('general').toUpperCase();
    }
  }

  String _prettifyMessage(String Function(String) t, String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return t('notification_message_unavailable');
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _audienceLabel(String Function(String) t, dynamic notification) {
    final recipientType = (notification['recipientType'] ?? '').toString();
    switch (recipientType) {
      case 'all-users':
        return t('audience_all_users');
      case 'all-admins':
        return t('audience_all_admins');
      case 'specific-users':
        return t('audience_selected_users');
      case 'specific-admins':
        return t('audience_selected_admins');
      default:
        return t('audience_custom');
    }
  }

  String _formatTime(String Function(String) t, dynamic rawDate) {
    if (rawDate == null) return t('recently');
    final createdAt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (createdAt == null) return t('recently');
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return t('just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${t('min_ago')}';
    if (diff.inHours < 24) return '${diff.inHours} ${t('hr_ago')}';
    if (diff.inDays < 7) return '${diff.inDays} ${t('day_ago')}';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

class _NotificationCategoryChip {
  final String label;
  final String value;

  const _NotificationCategoryChip({
    required this.label,
    required this.value,
  });
}

