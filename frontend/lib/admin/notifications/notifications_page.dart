import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

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

  final List<_NotificationCategoryChip> _categories = const [
    _NotificationCategoryChip(label: 'All', value: 'all'),
    _NotificationCategoryChip(label: 'Friends', value: 'friend'),
    _NotificationCategoryChip(label: 'Offers', value: 'offer'),
    _NotificationCategoryChip(label: 'Transactions', value: 'transaction'),
    _NotificationCategoryChip(label: 'Groups', value: 'group'),
    _NotificationCategoryChip(label: 'System', value: 'system'),
    _NotificationCategoryChip(label: 'General', value: 'general'),
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

  Color _getNoteColor(int index) {
    const colors = [
      Color(0xFFFFF4E6),
      Color(0xFFE8F5E9),
      Color(0xFFFCE4EC),
      Color(0xFFE3F2FD),
      Color(0xFFFFF9C4),
      Color(0xFFF3E5F5),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _deliveryStatus == 'scheduled'
                    ? 'Notification scheduled successfully.'
                    : _deliveryStatus == 'draft'
                        ? 'Notification draft saved successfully.'
                        : 'Notification sent successfully.',
              ),
            ),
          );
        }
      } else if (mounted) {
        String errorMessage = 'Failed to send notification.';
        try {
          final errorBody = json.decode(response.body);
          if (errorBody['message'] != null) {
            errorMessage = errorBody['message'].toString();
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e')),
        );
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
      setState(() {
        final invalid = List<String>.from(data['invalidRecipients'] ?? const []);
        _audiencePreview =
            '${data['estimatedAudience'] ?? 0} eligible recipients${invalid.isNotEmpty ? ' • Invalid: ${invalid.join(', ')}' : ''}';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification deleted successfully.')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete notification: ${response.body}')),
      );
    }
  }

  Future<void> _editNotification(dynamic notification) async {
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Edit Notification'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: editMessageController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: editRecipientType,
                      decoration: InputDecoration(
                        labelText: 'Audience',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all-users',
                          child: Text('All Users'),
                        ),
                        DropdownMenuItem(
                          value: 'all-admins',
                          child: Text('All Admins'),
                        ),
                        DropdownMenuItem(
                          value: 'specific-users',
                          child: Text('Specific Users'),
                        ),
                        DropdownMenuItem(
                          value: 'specific-admins',
                          child: Text('Specific Admins'),
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
                        decoration: InputDecoration(
                          labelText: 'Recipients (comma-separated)',
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
                  child: const Text('Cancel'),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Notification updated successfully.'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save'),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 132,
                color: const Color(0xFF00B4D8),
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
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Admin Notifications',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildSummaryCard(),
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
                        color: Colors.white.withOpacity(0.96),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: const Color(0xFF00B4D8),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: const Color(0xFF00B4D8),
                        dividerColor: Colors.transparent,
                        overlayColor:
                            WidgetStateProperty.all(Colors.transparent),
                        tabs: const [
                          Tab(text: 'Inbox'),
                          Tab(text: 'Sent'),
                          Tab(text: 'Compose'),
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
                          notifications: _receivedNotifications,
                          loading: _isLoadingReceived,
                          unreadUserId: userId,
                          selectedCategory: _inboxCategory,
                          onCategoryChanged: (value) {
                            setState(() => _inboxCategory = value);
                          },
                          emptyText: 'No received notifications yet.',
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
                          notifications: _sentNotifications,
                          loading: _isLoadingSent,
                          unreadUserId: userId,
                          selectedCategory: _sentCategory,
                          onCategoryChanged: (value) {
                            setState(() => _sentCategory = value);
                          },
                          emptyText: 'No sent notifications yet.',
                          allowViewAll: _sentNotifications.length == 3 && !_viewAllSent,
                          onViewAll: () => _fetchSentNotifications(viewAll: true),
                          canManage: true,
                          showReadState: false,
                        ),
                      ),
                      _buildComposePanel(),
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

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildStatTile(
              title: 'Unread',
              value: '$_unreadCount',
              color: const Color(0xFF00B4D8),
              icon: Icons.mark_email_unread_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: 'Inbox',
              value: '${_receivedNotifications.length}',
              color: Colors.orange,
              icon: Icons.inbox_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: 'Sent',
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
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
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
              color: Colors.grey.shade700,
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
  }) {
    final filtered = _filterByCategory(notifications, selectedCategory);

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((chip) {
              final selected = chip.value == selectedCategory;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(chip.label),
                  selected: selected,
                  onSelected: (_) => onCategoryChanged(chip.value),
                  selectedColor: const Color(0xFF00B4D8),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF00B4D8),
                    fontWeight: FontWeight.w600,
                  ),
                  side: const BorderSide(color: Color(0xFF00B4D8)),
                  backgroundColor: Colors.white,
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
                  const Icon(
                    Icons.notifications_off_outlined,
                    size: 72,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    emptyText,
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ...filtered.asMap().entries.map((entry) {
          final index = entry.key;
          final notification = entry.value;
          return _buildNotificationCard(
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
                  backgroundColor: const Color(0xFF00B4D8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('View All Notifications'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildNotificationCard({
    required dynamic notification,
    required int index,
    required dynamic unreadUserId,
    required bool canManage,
    required bool showReadState,
  }) {
    final category = _categoryForNotification(notification);
    final accent = _accentForCategory(category);
    final isRead = _isNotificationRead(notification, unreadUserId);
    final session = Provider.of<SessionProvider>(context, listen: false);
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
          color: _getNoteColor(index),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
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
                          _labelForCategory(category),
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
                            color: Color(0xFF00B4D8),
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
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _prettifyMessage((notification['message'] ?? '').toString()),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _audienceLabel(notification),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(notification['createdAt']),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
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

  Widget _buildComposePanel() {
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Compose Notification',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Create cleaner alerts for users or admins from here.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Message',
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
                    labelText: 'Audience',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all-users', child: Text('All Users')),
                    DropdownMenuItem(value: 'all-admins', child: Text('All Admins')),
                    DropdownMenuItem(
                      value: 'specific-users',
                      child: Text('Specific Users'),
                    ),
                    DropdownMenuItem(
                      value: 'specific-admins',
                      child: Text('Specific Admins'),
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
                    labelText: 'Delivery',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'sent', child: Text('Send Now')),
                    DropdownMenuItem(value: 'draft', child: Text('Save Draft')),
                    DropdownMenuItem(
                      value: 'scheduled',
                      child: Text('Schedule'),
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
                    decoration: InputDecoration(
                      labelText: 'Recipients (comma-separated)',
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
                    decoration: InputDecoration(
                      labelText: 'Scheduled For',
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
                    color: const Color(0xFFF6FBFE),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _audiencePreview ?? 'Audience preview will appear here.',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                      TextButton(
                        onPressed: _loadAudiencePreview,
                        child: const Text('Preview'),
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
                      backgroundColor: const Color(0xFF00B4D8),
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
                        : const Text('Send Notification'),
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
        return const Color(0xFF00B4D8);
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

  String _labelForCategory(String category) {
    switch (category) {
      case 'friend':
        return 'FRIENDS';
      case 'offer':
        return 'OFFERS';
      case 'transaction':
        return 'TRANSACTIONS';
      case 'group':
        return 'GROUPS';
      case 'system':
        return 'SYSTEM';
      default:
        return 'GENERAL';
    }
  }

  String _prettifyMessage(String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return 'Notification message unavailable.';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _audienceLabel(dynamic notification) {
    final recipientType = (notification['recipientType'] ?? '').toString();
    switch (recipientType) {
      case 'all-users':
        return 'Audience: All users';
      case 'all-admins':
        return 'Audience: All admins';
      case 'specific-users':
        return 'Audience: Selected users';
      case 'specific-admins':
        return 'Audience: Selected admins';
      default:
        return 'Audience: Custom';
    }
  }

  String _formatTime(dynamic rawDate) {
    if (rawDate == null) return 'Recently';
    final createdAt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (createdAt == null) return 'Recently';
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} day ago';
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

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.7,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.4,
      size.width,
      size.height * 0.7,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
