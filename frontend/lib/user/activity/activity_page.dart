import 'package:flutter/material.dart';
import '../../utils/pickers.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../api_config.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'package:intl/intl.dart';
import 'package:elegant_notification/elegant_notification.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';
import '../../widgets/search_tab_bar.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  List<Map<String, dynamic>> activities = [];
  List<Map<String, dynamic>> allActivities =
      []; // Store all activities for search
  Map<String, dynamic> stats = {};
  bool loading = true;
  bool loadingStats = true;
  String? _error;
  String? selectedType;
  DateTime? startDate;
  DateTime? endDate;
  String searchQuery = ''; // For smart search
  bool _showBookmarkedOnly = false;
  bool _showFriendOnly = false;
  int currentPage = 1;
  bool hasNextPage = false;
  bool hasPrevPage = false;
  int totalItems = 0;
  int totalPages = 0;
  int _visibleCount = 5;
  final TextEditingController _searchController = TextEditingController();

  // Activity insights data
  Map<String, int> activityTypeCounts = {};
  Map<String, double> activityTypeAmounts = {};

  final List<String> activityTypes = [
    'transaction_created',
    'transaction_cleared',
    'partial_payment_made',
    'partial_payment_received',
    'group_created',
    'group_joined',
    'group_left',
    'member_added',
    'member_removed',
    'expense_added',
    'expense_edited',
    'expense_deleted',
    'expense_settled',
    'note_created',
    'note_edited',
    'note_deleted',
    'profile_updated',
    'password_changed',
    'login',
    'logout',
    'app_rated',
    'feedback_submitted',
    'user_rated',
    'user_rating_received',
    'receipt_generated',
    'quick_transaction_created',
    'quick_transaction_updated',
    'quick_transaction_deleted',
    'quick_transaction_cleared',
    'quick_transaction_cleared_all',
    'friend_request_sent',
    'friend_request_received',
    'friend_request_accepted',
    'friend_request_declined',
    'friend_request_canceled',
    'friend_removed',
    'user_blocked',
    'user_unblocked',
    'offer_accepted',
  ];

  @override
  void initState() {
    super.initState();
    fetchActivities();
    fetchStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchActivities({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        currentPage = 1;
        loading = true;
        _visibleCount = 5;
        _error = null;
      });
    } else {
      setState(() {
        loading = true;
        _error = null;
      });
    }

    try {
      final baseUrl = ApiConfig.baseUrl;

      // Build query parameters
      final queryParams = <String, String>{
        'page': currentPage.toString(),
        'limit': '50', // Increased limit for better search experience
        'excludeTypes': 'user_rating_received',
      };

      if (selectedType != null) {
        queryParams['type'] = selectedType!;
      }

      if (startDate != null) {
        queryParams['startDate'] = startDate!.toIso8601String();
      }

      if (endDate != null) {
        queryParams['endDate'] = endDate!.toIso8601String();
      }

      if (searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      if (_showBookmarkedOnly) {
        queryParams['bookmarked'] = 'true';
      }

      if (_showFriendOnly) {
        queryParams['friendOnly'] = 'true';
      }

      final uri = Uri.parse('$baseUrl/api/activities')
          .replace(queryParameters: queryParams);
      final response = await ApiClient.get(
          uri.path + (uri.query.isNotEmpty ? '?' + uri.query : ''));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final filteredActivities =
            List<Map<String, dynamic>>.from(data['activities']);
        setState(() {
          if (refresh) {
            activities = filteredActivities;
            allActivities = filteredActivities;
          } else {
            activities.addAll(filteredActivities);
            allActivities.addAll(filteredActivities);
          }
          final pagination = data['pagination'];
          currentPage = pagination['currentPage'];
          totalPages = pagination['totalPages'];
          totalItems = pagination['totalItems'];
          hasNextPage = pagination['hasNext'];
          hasPrevPage = pagination['hasPrev'];
          loading = false;
        });

        // Calculate insights after loading activities
        _calculateActivityInsights();
      } else {
        setState(() {
          loading = false;
          _error = AppLocalizations.of(context).t('failed_to_load_activities');
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        _error = AppLocalizations.of(context)
            .t('unable_to_connect_check_internet_message');
      });
    }
  }

  Future<void> fetchStats() async {
    setState(() => loadingStats = true);

    try {
      final baseUrl = ApiConfig.baseUrl;

      final queryParams = <String, String>{};
      if (startDate != null) {
        queryParams['startDate'] = startDate!.toIso8601String();
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate!.toIso8601String();
      }

      final uri = Uri.parse('$baseUrl/api/activities/stats')
          .replace(queryParameters: queryParams);
      final response = await ApiClient.get(
          uri.path + (uri.query.isNotEmpty ? '?' + uri.query : ''));

      if (response.statusCode == 200) {
        setState(() {
          stats = json.decode(response.body);
          loadingStats = false;
        });
      } else {
        setState(() => loadingStats = false);
      }
    } catch (e) {
      setState(() => loadingStats = false);
    }
  }

  void _showErrorDialog(String message) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(context),
        title: Text(t('error'),
            style: TextStyle(color: AppThemeColors.primaryText(context))),
        content: Text(message,
            style: TextStyle(color: AppThemeColors.primaryText(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('ok')),
          ),
        ],
      ),
    );
  }

  // Calculate activity insights
  void _calculateActivityInsights() {
    if (allActivities.isEmpty) return;

    // Reset insights
    activityTypeCounts.clear();
    activityTypeAmounts.clear();

    // Count activities by type and calculate amounts
    for (final activity in allActivities) {
      final type = activity['type'] as String;
      final amount = activity['amount'] as num?;

      // Count by type
      activityTypeCounts[type] = (activityTypeCounts[type] ?? 0) + 1;

      // Sum amounts
      if (amount != null) {
        activityTypeAmounts[type] =
            (activityTypeAmounts[type] ?? 0) + amount.toDouble();
      }
    }

    setState(() {});
  }

  // Search functionality
  void _performSearch(String query) {
    setState(() {
      searchQuery = query;
      currentPage = 1;
    });
    fetchActivities(refresh: true);
  }

  // Clear search
  void _clearSearch() {
    setState(() {
      searchQuery = '';
      currentPage = 1;
    });
    fetchActivities(refresh: true);
  }

  String _getActivityTypeDisplayName(String type) {
    final t = AppLocalizations.of(context).t;
    switch (type) {
      case 'transaction_created':
        return t('activity_type_transaction_created');
      case 'transaction_cleared':
        return t('activity_type_transaction_cleared');
      case 'partial_payment_made':
        return t('activity_type_partial_payment_made');
      case 'partial_payment_received':
        return t('activity_type_partial_payment_received');
      case 'group_created':
        return t('activity_type_group_created');
      case 'group_joined':
        return t('activity_type_group_joined');
      case 'group_left':
        return t('activity_type_group_left');
      case 'member_added':
        return t('activity_type_member_added');
      case 'member_removed':
        return t('activity_type_member_removed');
      case 'expense_added':
        return t('activity_type_expense_added');
      case 'expense_edited':
        return t('activity_type_expense_edited');
      case 'expense_deleted':
        return t('activity_type_expense_deleted');
      case 'expense_settled':
        return t('activity_type_expense_settled');
      case 'note_created':
        return t('activity_type_note_created');
      case 'note_edited':
        return t('activity_type_note_edited');
      case 'note_deleted':
        return t('activity_type_note_deleted');
      case 'profile_updated':
        return t('activity_type_profile_updated');
      case 'password_changed':
        return t('activity_type_password_changed');
      case 'login':
        return t('activity_type_login');
      case 'logout':
        return t('activity_type_logout');
      case 'app_rated':
        return t('activity_type_app_rated');
      case 'feedback_submitted':
        return t('activity_type_feedback_submitted');
      case 'user_rated':
        return t('activity_type_user_rated');
      case 'user_rating_received':
        return t('activity_type_user_rating_received');
      case 'receipt_generated':
        return t('activity_type_receipt_generated');
      case 'quick_transaction_created':
        return t('activity_type_quick_transaction_created');
      case 'quick_transaction_updated':
        return t('activity_type_quick_transaction_updated');
      case 'quick_transaction_deleted':
        return t('activity_type_quick_transaction_deleted');
      case 'quick_transaction_cleared':
        return t('activity_type_quick_transaction_cleared');
      case 'quick_transaction_cleared_all':
        return t('activity_type_quick_transaction_cleared_all');
      case 'friend_request_sent':
        return t('activity_type_friend_request_sent');
      case 'friend_request_received':
        return t('activity_type_friend_request_received');
      case 'friend_request_accepted':
        return t('activity_type_friend_request_accepted');
      case 'friend_request_declined':
        return t('activity_type_friend_request_declined');
      case 'friend_request_canceled':
        return t('activity_type_friend_request_canceled');
      case 'friend_removed':
        return t('activity_type_friend_removed');
      case 'user_blocked':
        return t('activity_type_user_blocked');
      case 'user_unblocked':
        return t('activity_type_user_unblocked');
      case 'offer_accepted':
        return t('activity_type_offer_accepted');
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'transaction_created':
      case 'transaction_cleared':
        return Icons.swap_horiz;
      case 'partial_payment_made':
      case 'partial_payment_received':
        return Icons.payment;
      case 'group_created':
      case 'group_joined':
      case 'group_left':
        return Icons.group;
      case 'member_added':
      case 'member_removed':
        return Icons.person_add;
      case 'expense_added':
      case 'expense_edited':
      case 'expense_deleted':
      case 'expense_settled':
        return Icons.receipt;
      case 'note_created':
      case 'note_edited':
      case 'note_deleted':
        return Icons.note;
      case 'profile_updated':
        return Icons.person;
      case 'password_changed':
        return Icons.lock;
      case 'login':
      case 'logout':
        return Icons.login;
      case 'app_rated':
        return Icons.star;
      case 'feedback_submitted':
        return Icons.feedback;
      case 'user_rated':
        return Icons.person;
      case 'user_rating_received':
        return Icons.person_outline;
      case 'receipt_generated':
        return Icons.receipt;
      case 'quick_transaction_created':
      case 'quick_transaction_updated':
      case 'quick_transaction_deleted':
      case 'quick_transaction_cleared':
      case 'quick_transaction_cleared_all':
        return Icons.flash_on;
      case 'friend_request_sent':
      case 'friend_request_received':
      case 'friend_request_accepted':
      case 'friend_request_declined':
      case 'friend_request_canceled':
        return Icons.people;
      case 'friend_removed':
        return Icons.person_remove;
      case 'user_blocked':
        return Icons.block;
      case 'user_unblocked':
        return Icons.check_circle;
      case 'offer_accepted':
        return Icons.local_offer;
      default:
        return Icons.info;
    }
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'transaction_created':
      case 'group_created':
      case 'note_created':
      case 'expense_added':
        return Colors.green;
      case 'transaction_cleared':
      case 'expense_settled':
        return Colors.blue;
      case 'partial_payment_made':
      case 'partial_payment_received':
        return Colors.orange;
      case 'expense_deleted':
      case 'note_deleted':
      case 'group_left':
        return Colors.red;
      case 'expense_edited':
      case 'note_edited':
      case 'profile_updated':
        return Colors.purple;
      case 'member_added':
        return Colors.teal;
      case 'member_removed':
        return Colors.red;
      case 'login':
        return Colors.green;
      case 'logout':
        return Colors.grey;
      case 'app_rated':
        return Colors.amber;
      case 'feedback_submitted':
        return Colors.blueAccent;
      case 'user_rated':
        return Colors.green;
      case 'user_rating_received':
        return Colors.teal;
      case 'receipt_generated':
        return Colors.brown;
      case 'quick_transaction_created':
        return Colors.blue;
      case 'quick_transaction_updated':
        return Colors.purple;
      case 'quick_transaction_deleted':
        return Colors.red;
      case 'quick_transaction_cleared':
        return Colors.green;
      case 'quick_transaction_cleared_all':
        return Colors.red;
      case 'friend_request_sent':
        return Colors.blue;
      case 'friend_request_received':
        return Colors.orange;
      case 'friend_request_accepted':
        return Colors.green;
      case 'friend_request_declined':
      case 'friend_request_canceled':
        return Colors.red;
      case 'friend_removed':
        return Colors.red;
      case 'user_blocked':
        return Colors.red;
      case 'user_unblocked':
        return Colors.green;
      case 'offer_accepted':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String dateString, {String? activityType}) {
    final t = AppLocalizations.of(context).t;
    try {
      // The backend stores UTC timestamps (ISO 8601 with a 'Z' suffix) — without
      // toLocal(), DateFormat reads the raw UTC hour/day fields as-is, so the
      // displayed time (and sometimes date, near the UTC day boundary) is off
      // by the device's UTC offset. This was the cause of login/logout times
      // looking wrong; other activity types mostly show a relative "X ago"
      // string instead, which is timezone-independent and so masked the bug.
      final date = DateTime.parse(dateString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(date);

      // For login/logout activities, always show the full local date and time
      if (activityType == 'login' || activityType == 'logout') {
        return DateFormat('MMM dd, yyyy • h:mm a').format(date);
      }

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes} ${t('minutes_ago')}';
        }
        return '${difference.inHours} ${t('hours_ago')}';
      } else if (difference.inDays == 1) {
        return t('yesterday');
      } else if (difference.inDays < 7) {
        return '${difference.inDays} ${t('days_ago')}';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateString;
    }
  }

  String _formatActivityDescription(Map<String, dynamic> activity) {
    final t = AppLocalizations.of(context).t;
    final type = activity['type'] as String;
    final description = activity['description']?.toString() ?? '';
    final metadata = activity['metadata'] ?? {};
    final withUser = metadata['with']?.toString();
    final byUser = metadata['by']?.toString();
    final toUser = metadata['to']?.toString();
    final fromUser = metadata['from']?.toString();

    switch (type) {
      case 'friend_request_sent':
        return toUser != null
            ? '${t('sent_friend_request_to')} $toUser'
            : description;
      case 'friend_request_received':
        return fromUser != null
            ? '${t('received_friend_request_from')} $fromUser'
            : description;
      case 'friend_request_accepted':
        return withUser != null
            ? '${t('friend_request_accepted_with')} $withUser'
            : description;
      case 'friend_request_declined':
        return withUser != null
            ? '${t('friend_request_declined_with')} $withUser'
            : description;
      case 'friend_request_canceled':
        return withUser != null
            ? '${t('friend_request_canceled_with')} $withUser'
            : description;
      case 'friend_removed':
        return withUser != null
            ? '${t('friend_removed_colon')} $withUser'
            : description;
      case 'user_blocked':
        return byUser != null
            ? '${t('blocked_by')} $byUser'
            : t('user_blocked_text');
      case 'user_unblocked':
        return byUser != null
            ? '${t('unblocked_by')} $byUser'
            : t('user_unblocked_text');
      default:
        return description;
    }
  }

  // ── date-grouped flat list ─────────────────────────────────────────────────

  bool get _hasMore => _visibleCount < activities.length || hasNextPage;

  int get _remainingCount =>
      totalItems > _visibleCount ? totalItems - _visibleCount : 0;

  List<dynamic> get _groupedActivities {
    if (activities.isEmpty) return [];
    final visible = activities.take(_visibleCount).toList();
    final result = <dynamic>[];
    String? lastKey;
    for (final a in visible) {
      final key = _getDateGroupKey(a['createdAt'] as String? ?? '');
      if (key != lastKey) {
        result.add(key);
        lastKey = key;
      }
      result.add(a);
    }
    return result;
  }

  String _getDateGroupKey(String dateStr) {
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final d = DateTime(date.year, date.month, date.day);
      if (d == today) return 'Today';
      if (d == yesterday) return 'Yesterday';
      return DateFormat('EEEE, MMM d').format(date);
    } catch (_) {
      return '';
    }
  }

  Widget _buildDateHeader(String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(children: [
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: AppColors.cyan,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: context.sp(10),
            fontWeight: FontWeight.bold,
            color: AppColors.cyan,
            letterSpacing: 1.0,
          ),
        ),
      ]),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final grouped = _groupedActivities;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          t('activity_log_title'),
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              fetchActivities(refresh: true);
              fetchStats();
            },
          ),
        ],
      ),
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
                height: context.sh(160),
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.only(top: context.sh(35)),
              child: RefreshIndicator(
                onRefresh: () async {
                  await fetchActivities(refresh: true);
                  await fetchStats();
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildSearchBar()),
                    if (!loadingStats)
                      SliverToBoxAdapter(child: _buildStatsSection()),
                    if (!loading && allActivities.isNotEmpty)
                      SliverToBoxAdapter(child: _buildActivityInsights()),
                    if (selectedType != null ||
                        startDate != null ||
                        endDate != null ||
                        searchQuery.isNotEmpty)
                      SliverToBoxAdapter(child: _buildFilterChips()),
                    if (loading)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: errorStateWidget(context, _error!,
                            () => fetchActivities(refresh: true)),
                      )
                    else if (activities.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    else
                      SliverList.builder(
                        itemCount: grouped.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == grouped.length)
                            return _buildLoadMoreButton();
                          final item = grouped[index];
                          if (item is String) return _buildDateHeader(item);
                          return _buildActivityCard(
                              item as Map<String, dynamic>);
                        },
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final t = AppLocalizations.of(context).t;
    return AppSearchBar(
      controller: _searchController,
      hintText: t('search activities'),
      isLoading: false,
      onChanged: (value) {
        setState(() => searchQuery = value);
        _performSearch(value);
      },
    );
  }

  Widget _buildStatsSection() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
            child: Row(children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                t('activity_summary_title').toUpperCase(),
                style: TextStyle(
                    fontSize: context.sp(10),
                    fontWeight: FontWeight.bold,
                    color: AppColors.cyan,
                    letterSpacing: 1.0),
              ),
            ]),
          ),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildStatMetric(
                    icon: Icons.timeline,
                    label: t('total_activities_label'),
                    value: '${stats['totalActivities'] ?? 0}',
                    color: AppColors.cyan,
                  ),
                ),
                VerticalDivider(
                    width: 1,
                    color:
                        AppThemeColors.border(context).withValues(alpha: 0.4)),
                Expanded(
                  child: _buildStatMetric(
                    icon: Icons.trending_up,
                    label: t('recent_7_days_label'),
                    value: '${stats['recentActivities'] ?? 0}',
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildStatMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: context.sp(11),
                      color: AppThemeColors.secondaryText(context),
                      letterSpacing: 0.2)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                      fontSize: context.sp(20),
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityInsights() {
    final t = AppLocalizations.of(context).t;
    final top3 = (activityTypeCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .toList();
    if (top3.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
            child: Row(children: [
              Container(
                width: 3,
                height: 13,
                decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                t('activity_insights_title').toUpperCase(),
                style: TextStyle(
                    fontSize: context.sp(10),
                    fontWeight: FontWeight.bold,
                    color: AppColors.cyan,
                    letterSpacing: 1.0),
              ),
            ]),
          ),
          Divider(
              height: 1,
              color: AppThemeColors.border(context).withValues(alpha: 0.4)),
          ...top3.asMap().entries.map((e) => Column(children: [
                if (e.key > 0)
                  Divider(
                      height: 1,
                      indent: 66,
                      color: AppThemeColors.border(context)
                          .withValues(alpha: 0.3)),
                _buildActivityTypeRow(e.value.key, e.value.value),
              ])),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildActivityTypeRow(String type, int count) {
    final color = _getActivityColor(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(_getActivityIcon(type), color: color, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            _getActivityTypeDisplayName(type),
            style: TextStyle(
                fontSize: context.sp(14),
                color: AppThemeColors.primaryText(context)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text('$count',
              style: TextStyle(
                  fontSize: context.sp(12),
                  fontWeight: FontWeight.bold,
                  color: color)),
        ),
      ]),
    );
  }

  Widget _buildFilterChips() {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          if (searchQuery.isNotEmpty)
            Chip(
              label: Text('${t('search')}: "$searchQuery"'),
              onDeleted: _clearSearch,
              backgroundColor: Colors.purple.withValues(alpha: 0.2),
              deleteIcon: const Icon(Icons.clear, size: 18),
            ),
          if (_showBookmarkedOnly)
            Chip(
              label: Text(t('bookmarked_label')),
              onDeleted: () {
                setState(() => _showBookmarkedOnly = false);
                fetchActivities(refresh: true);
              },
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
            ),
          if (selectedType != null)
            Chip(
              label: Text(_getActivityTypeDisplayName(selectedType!)),
              onDeleted: () {
                setState(() => selectedType = null);
                fetchActivities(refresh: true);
              },
              backgroundColor: AppColors.cyan.withValues(alpha: 0.2),
            ),
          if (startDate != null)
            Chip(
              label: Text(
                  '${t('from_colon_label')} ${DateFormat('MMM dd').format(startDate!)}'),
              onDeleted: () {
                setState(() => startDate = null);
                fetchActivities(refresh: true);
              },
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
            ),
          if (endDate != null)
            Chip(
              label: Text(
                  '${t('to_colon_label')} ${DateFormat('MMM dd').format(endDate!)}'),
              onDeleted: () {
                setState(() => endDate = null);
                fetchActivities(refresh: true);
              },
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final t = AppLocalizations.of(context).t;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.timeline,
                size: 40, color: AppColors.cyan.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 20),
          Text(
            t('no_activities_found'),
            style: TextStyle(
              fontSize: context.sp(18),
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('activities_will_appear_here'),
            style: TextStyle(color: AppThemeColors.mutedText(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final t = AppLocalizations.of(context).t;
    final type = activity['type'] as String;
    final title = activity['title'] as String;
    final createdAt = activity['createdAt'] as String;
    final amount = activity['amount'];
    final currency = activity['currency'];
    final metadata = activity['metadata'];
    final displayDescription = _formatActivityDescription(activity);
    final isBookmarked = activity['bookmarked'] ?? false;
    final isRating = type == 'user_rated' || type == 'user_rating_received';
    final ratingValue = metadata != null && metadata['rating'] != null
        ? metadata['rating']
        : null;
    final color = isRating ? Colors.amber : _getActivityColor(type);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isRating ? Icons.star : _getActivityIcon(type),
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: context.sp(14),
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      if (amount != null && currency != null)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Text('$currency$amount',
                              style: TextStyle(
                                  fontSize: context.sp(11),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green)),
                        ),
                      if (isRating && ratingValue != null)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('$ratingValue ★',
                              style: TextStyle(
                                  fontSize: context.sp(11),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber[800])),
                        ),
                    ],
                  ),
                  if (displayDescription.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      displayDescription,
                      style: TextStyle(
                          fontSize: context.sp(12),
                          color: AppThemeColors.secondaryText(context)),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 11, color: AppThemeColors.mutedText(context)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          _formatDate(createdAt, activityType: type),
                          style: TextStyle(
                              fontSize: context.sp(11),
                              color: AppThemeColors.mutedText(context)),
                        ),
                      ),
                      if (isBookmarked)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.bookmark,
                              size: 14, color: Colors.orange),
                        ),
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: Icon(Icons.more_vert,
                              size: 16,
                              color: AppThemeColors.mutedText(context)),
                          onSelected: (value) {
                            if (value == 'details') {
                              _showActivityDetails(activity);
                            } else if (value == 'bookmark') {
                              _bookmarkActivity(activity);
                            } else if (value == 'delete') {
                              _deleteActivity(activity);
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem<String>(
                              value: 'details',
                              child: ListTile(
                                dense: true,
                                leading:
                                    const Icon(Icons.info, color: Colors.blue),
                                title: Text(t('view_details')),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'bookmark',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.bookmark,
                                    color: isBookmarked
                                        ? Colors.red
                                        : Colors.orange),
                                title: Text(isBookmarked
                                    ? t('unbookmark')
                                    : t('bookmark')),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: ListTile(
                                dense: true,
                                leading:
                                    const Icon(Icons.delete, color: Colors.red),
                                title: Text(t('delete')),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildLoadMoreButton() {
    final remaining = _remainingCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: OutlinedButton(
        onPressed: () {
          if (_visibleCount < activities.length) {
            // Reveal next 5 from already-fetched batch
            setState(() => _visibleCount += 5);
          } else if (hasNextPage) {
            // Fetch next server page, then reveal 5 more
            setState(() {
              _visibleCount += 5;
              currentPage++;
            });
            fetchActivities();
          }
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.cyan, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Text(
          remaining > 0 ? 'View More  ($remaining remaining)' : 'View More',
          style: const TextStyle(
              color: AppColors.cyan, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // Swipe Action Methods
  void _showActivityDetails(Map<String, dynamic> activity) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              color: AppThemeColors.tinted(context,
                  light: const Color(0xFFFCE4EC),
                  dark: const Color(0xFF3A1F2A)),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  offset: const Offset(0, 10),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(activity['title'] ?? t('activity_details_title'),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 16),
                Text(
                    '${t('type_label')}: ${_getActivityTypeDisplayName(activity['type'])}',
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 8),
                Text(
                    '${t('description')}: ${_formatActivityDescription(activity)}',
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 8),
                Text(
                    '${t('date_label')}: ${_formatDate(activity['createdAt'], activityType: activity['type'])}',
                    style:
                        TextStyle(color: AppThemeColors.primaryText(context))),
                if (activity['amount'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                      '${t('amount_label')}: ${activity['currency']}${activity['amount']}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context))),
                ],
                if (activity['metadata'] != null) ...[
                  const SizedBox(height: 8),
                  Text('${t('additional_info_label')}: ${activity['metadata']}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context))),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(t('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _bookmarkActivity(Map<String, dynamic> activity) async {
    final t = AppLocalizations.of(context).t;
    final activityId = activity['_id'];
    final isBookmarked = activity['bookmarked'] ?? false;

    ElegantNotification.info(
      title: Text(
          isBookmarked ? t('unbookmarking_label') : t('bookmarking_label')),
      description: Text(t('please_wait_ellipsis')),
    ).show(context);

    setState(() {
      activity['bookmarked'] = !isBookmarked;
    });

    try {
      final response = await ApiClient.patch(
        '/api/activities/$activityId/bookmark',
        body: {'bookmarked': !isBookmarked},
      );

      if (response.statusCode == 200) {
        ElegantNotification.success(
          title: Text(t('success')),
          description: Text(isBookmarked
              ? t('removed_from_bookmarks')
              : t('bookmarked_successfully')),
        ).show(context);
      } else {
        setState(() {
          activity['bookmarked'] = isBookmarked; // Revert on failure
        });
        _showErrorDialog(t('failed_to_update_bookmark_status'));
      }
    } catch (e) {
      setState(() {
        activity['bookmarked'] = isBookmarked; // Revert on failure
      });
      _showErrorDialog(t('unable_to_connect_check_internet_message'));
    }
  }

  void _deleteActivity(Map<String, dynamic> activity) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                offset: const Offset(0, 10),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient background
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.red, Colors.redAccent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.delete_forever,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      t('delete_activity_title'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('action_cannot_be_undone'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Warning Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Activity Title
                    Text(
                      activity['title'] ?? t('unknown_activity_label'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    // Activity Type
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getActivityColor(activity['type'])
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getActivityTypeDisplayName(activity['type']),
                        style: TextStyle(
                          color: _getActivityColor(activity['type']),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirmation Text
                    Text(
                      t('confirm_delete_activity_message'),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppThemeColors.secondaryText(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.cancel, color: Colors.grey),
                        label: Text(
                          t('cancel'),
                          style: const TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.w600),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(context).pop();

                          try {
                            final baseUrl = ApiConfig.baseUrl;

                            final uri = Uri.parse(
                                '$baseUrl/api/activities/${activity['_id']}');
                            final response = await ApiClient.delete(uri.path);

                            if (response.statusCode == 200) {
                              // Remove from local list
                              setState(() {
                                activities.removeWhere(
                                    (a) => a['_id'] == activity['_id']);
                                allActivities.removeWhere(
                                    (a) => a['_id'] == activity['_id']);
                              });
                              _calculateActivityInsights();

                              showSnack(
                                  context, t('activity_deleted_successfully'));
                            } else {
                              final errorData = json.decode(response.body);
                              showSnack(
                                  context,
                                  errorData['error'] ??
                                      t('failed_to_delete_activity'),
                                  isError: true);
                            }
                          } catch (e) {
                            showSnack(context,
                                t('unable_to_connect_check_internet_message'),
                                isError: true);
                          }
                        },
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.white),
                        label: Text(
                          t('delete'),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterDialog() {
    final t = AppLocalizations.of(context).t;
    String? tempSelectedType = selectedType;
    DateTime? tempStartDate = startDate;
    DateTime? tempEndDate = endDate;
    bool tempShowBookmarkedOnly = _showBookmarkedOnly;
    bool tempShowFriendOnly = _showFriendOnly;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenHeight = MediaQuery.of(context).size.height;
            Future<void> showTypeOptions() async {
              final selected = await showModalBottomSheet<String?>(
                context: context,
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (sheetContext) {
                  return SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppThemeColors.tinted(sheetContext,
                                  light: const Color(0xFFF4FBFE),
                                  dark: const Color(0xFF13242A)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.category,
                                    color: AppColors.cyan, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      t('select_activity_type'),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        color: AppThemeColors.primaryText(
                                            sheetContext),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: screenHeight * 0.45,
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                _buildActivityTypeOption(
                                  label: t('all_types'),
                                  value: null,
                                  selectedValue: tempSelectedType,
                                  icon: Icons.all_inclusive,
                                  iconColor: Colors.grey,
                                  onTap: () =>
                                      Navigator.of(sheetContext).pop(null),
                                ),
                                ...activityTypes.map(
                                  (type) => _buildActivityTypeOption(
                                    label: _getActivityTypeDisplayName(type),
                                    value: type,
                                    selectedValue: tempSelectedType,
                                    icon: _getActivityIcon(type),
                                    iconColor: _getActivityColor(type),
                                    onTap: () =>
                                        Navigator.of(sheetContext).pop(type),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
              if (selected != null || tempSelectedType != null) {
                setState(() {
                  tempSelectedType = selected;
                });
              }
            }

            return Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: SizedBox(
                height: screenHeight * 0.80,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        offset: const Offset(0, 10),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      // Header with gradient background
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.cyan, AppColors.cyan],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Column(
                          children: [
                            // Close button at the top right
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const SizedBox(
                                    width: 40), // Spacer to center the content
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.filter_list_alt,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                // Close button
                                GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              t('filter_activities_title'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('customize_activity_view'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Filter Content
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Activity Type Filter with enhanced styling
                                Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Colors.orange,
                                        Colors.white,
                                        Colors.green
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppThemeColors.cardBg(context),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: showTypeOptions,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.radio_button_checked,
                                              color: AppColors.cyan,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppColors.cyan
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.category,
                                                color: AppColors.cyan,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    t('activity_type_label'),
                                                    style: const TextStyle(
                                                      color: AppColors.cyan,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  SingleChildScrollView(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    child: Text(
                                                      tempSelectedType == null
                                                          ? t('all_types')
                                                          : _getActivityTypeDisplayName(
                                                              tempSelectedType!),
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: AppThemeColors
                                                            .primaryText(
                                                                context),
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.chevron_right,
                                                color: Colors.grey),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.grey
                                            .withValues(alpha: 0.18)),
                                  ),
                                  child: Row(
                                    children: [
                                      Switch(
                                        value: tempShowBookmarkedOnly,
                                        onChanged: (value) {
                                          setState(() {
                                            tempShowBookmarkedOnly = value;
                                          });
                                        },
                                        activeColor: AppColors.cyan,
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.bookmark,
                                          color: Colors.orange),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                            t('show_bookmarked_only'),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: AppThemeColors.primaryText(
                                                  context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.grey
                                            .withValues(alpha: 0.18)),
                                  ),
                                  child: Row(
                                    children: [
                                      Switch(
                                        value: tempShowFriendOnly,
                                        onChanged: (value) {
                                          setState(() {
                                            tempShowFriendOnly = value;
                                          });
                                        },
                                        activeColor: AppColors.cyan,
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.people,
                                          color: Colors.teal),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                            t('friends_activity_only'),
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: AppThemeColors.primaryText(
                                                  context),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Date Range Section
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color:
                                            Colors.grey.withValues(alpha: 0.2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withValues(alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.date_range,
                                              color: Colors.orange,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            t('date_range_label'),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: AppThemeColors.primaryText(
                                                  context),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Date Range Buttons
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            _buildDateButton(
                                              context: context,
                                              label: t('start_date'),
                                              date: tempStartDate,
                                              onPressed: () async {
                                                final date =
                                                    await showAppDatePicker(
                                                  context: context,
                                                  initialDate: tempStartDate ??
                                                      DateTime.now(),
                                                  firstDate: DateTime(2020),
                                                  lastDate: DateTime.now(),
                                                );
                                                if (date != null) {
                                                  setState(() =>
                                                      tempStartDate = date);
                                                }
                                              },
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              child: const Icon(
                                                  Icons.arrow_forward,
                                                  color: Colors.grey),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildDateButton(
                                              context: context,
                                              label: t('end_date'),
                                              date: tempEndDate,
                                              onPressed: () async {
                                                final date =
                                                    await showAppDatePicker(
                                                  context: context,
                                                  initialDate: tempEndDate ??
                                                      DateTime.now(),
                                                  firstDate: DateTime(2020),
                                                  lastDate: DateTime.now(),
                                                );
                                                if (date != null) {
                                                  setState(
                                                      () => tempEndDate = date);
                                                }
                                              },
                                            ),
                                          ],
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

                      // Action Buttons
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() {
                                    tempSelectedType = null;
                                    tempStartDate = null;
                                    tempEndDate = null;
                                    tempShowBookmarkedOnly = false;
                                    tempShowFriendOnly = false;
                                  });
                                },
                                icon: const Icon(Icons.clear_all,
                                    color: Colors.red),
                                label: Text(
                                  t('clear_all'),
                                  style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600),
                                ),
                                style: TextButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(color: Colors.red),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  this.setState(() {
                                    selectedType = tempSelectedType;
                                    startDate = tempStartDate;
                                    endDate = tempEndDate;
                                    _showBookmarkedOnly =
                                        tempShowBookmarkedOnly;
                                    _showFriendOnly = tempShowFriendOnly;
                                    currentPage = 1;
                                  });
                                  Navigator.of(context).pop();
                                  fetchActivities(refresh: true);
                                  fetchStats();
                                },
                                icon: const Icon(Icons.check,
                                    color: Colors.white),
                                label: Text(
                                  t('apply_filters'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyan,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDateButton({
    required BuildContext context,
    required String label,
    required DateTime? date,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(150, 44),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              date != null ? DateFormat('MMM dd, yyyy').format(date) : label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: date != null
                    ? AppThemeColors.primaryText(context)
                    : AppThemeColors.secondaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTypeOption({
    required String label,
    required String? value,
    required String? selectedValue,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    final selected = selectedValue == value;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppThemeColors.tinted(context,
                  light: const Color(0xFFE9F8FC), dark: const Color(0xFF13242A))
              : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                selected ? AppColors.cyan : Colors.grey.withValues(alpha: 0.20),
          ),
        ),
        child: Row(
          children: [
            Radio<String?>(
              value: value,
              groupValue: selectedValue,
              activeColor: AppColors.cyan,
              onChanged: (_) => onTap(),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
