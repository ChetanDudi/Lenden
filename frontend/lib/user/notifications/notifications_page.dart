import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../connections/friends_page.dart';
import '../digitise/offers_page.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';

class UserNotificationsPage extends StatefulWidget {
  const UserNotificationsPage({Key? key}) : super(key: key);

  @override
  State<UserNotificationsPage> createState() => _UserNotificationsPageState();
}

class _UserNotificationsPageState extends State<UserNotificationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<dynamic> _notifications = [];
  List<Map<String, dynamic>> _incomingRequests = [];
  final Set<String> _removingRequestIds = {};
  bool _isLoading = true;
  bool _isShowingAll = false;
  int _unreadCount = 0;

  static const List<String> _tabCategories = [
    'all', 'friend', 'offer', 'transaction', 'group', 'general',
  ];

  String t(String key) => AppLocalizations.of(context).t(key);

  String _tabLabel(String category) {
    switch (category) {
      case 'friend':
        return t('requests_tab_label');
      case 'offer':
        return t('offers');
      case 'transaction':
        return t('transactions');
      case 'group':
        return t('groups');
      case 'general':
        return t('general_label');
      default:
        return t('all');
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCategories.length, vsync: this);
    _fetchNotifications();
    _fetchFriendRequests();
    _markNotificationsAsRead();
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    _unreadCount = _notifications
        .where((notification) => !_isNotificationRead(notification, userId))
        .length;
  }

  Future<void> _fetchNotifications({bool viewAll = false}) async {
    final url =
        viewAll ? '/api/notifications?viewAll=true' : '/api/notifications';
    final response = await ApiClient.get(url);

    if (response.statusCode == 200) {
      setState(() {
        _notifications = json.decode(response.body);
        _isLoading = false;
        if (viewAll) _isShowingAll = true;
        _calculateUnreadCount();
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchFriendRequests() async {
    final res = await ApiClient.get('/api/friends/requests');
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        _incomingRequests = List<Map<String, dynamic>>.from(data['incoming'] ?? []);
      });
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    setState(() => _removingRequestIds.add(requestId));
    final res = await ApiClient.post('/api/friends/requests/$requestId/accept');
    if (res.statusCode == 200) {
      await Future.delayed(const Duration(milliseconds: 250));
      setState(() {
        _incomingRequests.removeWhere((r) => r['_id'] == requestId);
        _removingRequestIds.remove(requestId);
      });
    }
  }

  Future<void> _declineRequest(String requestId) async {
    setState(() => _removingRequestIds.add(requestId));
    final res = await ApiClient.post('/api/friends/requests/$requestId/decline');
    if (res.statusCode == 200) {
      await Future.delayed(const Duration(milliseconds: 250));
      setState(() {
        _incomingRequests.removeWhere((r) => r['_id'] == requestId);
        _removingRequestIds.remove(requestId);
      });
    }
  }

  Future<void> _markNotificationsAsRead() async {
    await ApiClient.post('/api/notifications/mark-as-read');
    if (!mounted) return;
    await _fetchNotifications(viewAll: _isShowingAll);
  }

  bool _isNotificationRead(dynamic notification, dynamic userId) {
    final targetId = userId.toString();
    final readBy = (notification['readBy'] as List<dynamic>? ?? const []);

    return readBy.any((entry) {
      if (entry is Map<String, dynamic>) {
        final entryId = entry['_id'] ?? entry['id'];
        return entryId?.toString() == targetId;
      }
      return entry.toString() == targetId;
    });
  }

  String _categoryForNotification(dynamic notification) {
    final explicit = (notification['category'] ?? '').toString().toLowerCase();
    if (explicit.isNotEmpty) return explicit;

    final message = (notification['message'] ?? '').toString().toLowerCase();
    if (message.contains('friend')) return 'friend';
    if (message.contains('offer')) return 'offer';
    if (message.contains('group') || message.contains('split')) return 'group';
    if (message.contains('transaction') ||
        message.contains('payment') ||
        message.contains('borrow') ||
        message.contains('lend') ||
        message.contains('due')) {
      return 'transaction';
    }
    return 'general';
  }

  List<dynamic> _notificationsForCategory(String category) {
    if (category == 'all') return _notifications;
    return _notifications
        .where((notification) => _categoryForNotification(notification) == category)
        .toList();
  }

  void _openNotificationTarget(dynamic notification) {
    final category = _categoryForNotification(notification);
    if (category == 'friend') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FriendsPage()),
      );
      return;
    }
    if (category == 'offer') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UserOffersPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final userId = session.user!['_id'];

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
                height: context.sh(170),
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
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.iconOnWave(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('notifications'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.iconOnWave(context),
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
                  child: tricolorBorder(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context).withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: AppColors.cyan,
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.cyan,
                        dividerColor: Colors.transparent,
                        overlayColor:
                            WidgetStateProperty.all(Colors.transparent),
                        tabs: _tabCategories
                            .map((cat) => Tab(text: _tabLabel(cat)))
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.cyan,
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: _tabCategories
                              .map(
                                (cat) => RefreshIndicator(
                                  onRefresh: () async {
                                    await _fetchNotifications(
                                      viewAll: _isShowingAll,
                                    );
                                    await _fetchFriendRequests();
                                  },
                                  child: _buildNotificationList(
                                    userId: userId,
                                    category: cat,
                                  ),
                                ),
                              )
                              .toList(growable: false),
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
              title: t('unread_label'),
              value: '$_unreadCount',
              color: AppColors.cyan,
              icon: Icons.mark_email_unread_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: t('requests_tab_label'),
              value: '${_incomingRequests.length}',
              color: Colors.orange,
              icon: Icons.person_add_alt_1_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatTile(
              title: t('alerts_label'),
              value: '${_notifications.length}',
              color: Colors.green,
              icon: Icons.notifications_active_outlined,
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

  Widget _buildNotificationList({
    required dynamic userId,
    required String category,
  }) {
    final items = _notificationsForCategory(category);
    final showRequests = category == 'all' || category == 'friend';

    if (items.isEmpty && (!showRequests || _incomingRequests.isEmpty)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  size: 72,
                  color: AppThemeColors.divider(context),
                ),
                const SizedBox(height: 14),
                Text(
                  t('no_notifications_in_tab'),
                  style: TextStyle(fontSize: 16, color: AppThemeColors.secondaryText(context)),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (showRequests && _incomingRequests.isNotEmpty)
          _buildFriendRequestsCard(),
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final notification = entry.value;
          final isRead = _isNotificationRead(notification, userId);
          return _buildNotificationCard(
            notification: notification,
            isRead: isRead,
            index: index,
          );
        }),
        if (category == 'all' && _notifications.length == 3 && !_isShowingAll)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: ElevatedButton(
                onPressed: () => _fetchNotifications(viewAll: true),
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

  Widget _buildFriendRequestsCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: tricolorBorder(
        child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.tinted(context, light: const Color(0xFFFFF4E6), dark: const Color(0xFF2A2113)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_alt_outlined, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(
                  t('friend_requests_title'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._incomingRequests.map((request) {
              final from = request['from'] ?? {};
              final isRemoving = _removingRequestIds.contains(request['_id']);
              final title =
                  (from['name'] ?? from['username'] ?? t('new_request_label')).toString();
              final subtitle = (from['email'] ?? '').toString();
              return AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: isRemoving ? 0.4 : 1,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context).withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: AppThemeColors.secondaryText(context)),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isRemoving
                                  ? null
                                  : () => _declineRequest(request['_id']),
                              child: Text(t('decline')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isRemoving
                                  ? null
                                  : () => _acceptRequest(request['_id']),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(t('accept')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildNotificationCard({
    required dynamic notification,
    required bool isRead,
    required int index,
  }) {
    final category = _categoryForNotification(notification);
    final accent = _accentForCategory(category);
    final icon = _iconForCategory(category);
    final message = _prettifyMessage((notification['message'] ?? '').toString());

    return InkWell(
      onTap: () => _openNotificationTarget(notification),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: tricolorBorder(
          child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColors.isDark(context) ? AppThemeColors.surfaceBg(context) : _getNoteColor(index),
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
                child: Icon(icon, color: accent),
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
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppColors.cyan,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _formatTime(notification['createdAt']),
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
        ),
      ),
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
      default:
        return Icons.notifications_active_outlined;
    }
  }

  String _labelForCategory(String category) {
    switch (category) {
      case 'friend':
        return t('friends_category_label');
      case 'offer':
        return t('offers_category_label');
      case 'transaction':
        return t('transactions_category_label');
      case 'group':
        return t('groups_category_label');
      default:
        return t('general_category_label');
    }
  }

  String _prettifyMessage(String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return t('new_notification_default_msg');
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _formatTime(dynamic rawDate) {
    if (rawDate == null) return t('recently_label');
    final createdAt = DateTime.tryParse(rawDate.toString())?.toLocal();
    if (createdAt == null) return t('recently_label');

    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return t('just_now_label');
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${t('min_ago_suffix')}';
    if (diff.inHours < 24) return '${diff.inHours} ${t('hr_ago_suffix')}';
    if (diff.inDays < 7) return '${diff.inDays} ${t('day_ago_suffix')}';
    return '${createdAt.day}/${createdAt.month}/${createdAt.year}';
  }
}

