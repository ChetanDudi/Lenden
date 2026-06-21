import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../api_config.dart';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import 'package:intl/intl.dart';
import 'package:elegant_notification/elegant_notification.dart';
import '../../utils/responsive.dart';

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

  Future<void> fetchActivities({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        currentPage = 1;
        loading = true;
      });
    } else {
      setState(() => loading = true);
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
        setState(() => loading = false);
        _showErrorDialog('Failed to load activities');
      }
    } catch (e) {
      setState(() => loading = false);
      _showErrorDialog('Error: $e');
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
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
    switch (type) {
      case 'transaction_created':
        return 'Transaction Created';
      case 'transaction_cleared':
        return 'Transaction Cleared';
      case 'partial_payment_made':
        return 'Partial Payment Made';
      case 'partial_payment_received':
        return 'Partial Payment Received';
      case 'group_created':
        return 'Group Created';
      case 'group_joined':
        return 'Joined Group';
      case 'group_left':
        return 'Left Group';
      case 'member_added':
        return 'Member Added';
      case 'member_removed':
        return 'Member Removed';
      case 'expense_added':
        return 'Expense Added';
      case 'expense_edited':
        return 'Expense Edited';
      case 'expense_deleted':
        return 'Expense Deleted';
      case 'expense_settled':
        return 'Expense Settled';
      case 'note_created':
        return 'Note Created';
      case 'note_edited':
        return 'Note Edited';
      case 'note_deleted':
        return 'Note Deleted';
      case 'profile_updated':
        return 'Profile Updated';
      case 'password_changed':
        return 'Password Changed';
      case 'login':
        return 'Login';
      case 'logout':
        return 'Logout';
      case 'app_rated':
        return 'App Rated';
      case 'feedback_submitted':
        return 'Feedback Submitted';
      case 'user_rated':
        return 'User Rated';
      case 'user_rating_received':
        return 'User Rating Received';
      case 'receipt_generated':
        return 'Receipt Generated';
      case 'quick_transaction_created':
        return 'Quick Transaction Created';
      case 'quick_transaction_updated':
        return 'Quick Transaction Updated';
      case 'quick_transaction_deleted':
        return 'Quick Transaction Deleted';
      case 'quick_transaction_cleared':
        return 'Quick Transaction Cleared';
      case 'quick_transaction_cleared_all':
        return 'All Quick Transactions Cleared';
      case 'friend_request_sent':
        return 'Friend Request Sent';
      case 'friend_request_received':
        return 'Friend Request Received';
      case 'friend_request_accepted':
        return 'Friend Request Accepted';
      case 'friend_request_declined':
        return 'Friend Request Declined';
      case 'friend_request_canceled':
        return 'Friend Request Canceled';
      case 'friend_removed':
        return 'Friend Removed';
      case 'user_blocked':
        return 'User Blocked';
      case 'user_unblocked':
        return 'User Unblocked';
      case 'offer_accepted':
        return 'Offer Accepted';
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
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      // For login activities, always show full date and time
      if (activityType == 'login') {
        return DateFormat('MMM dd, yyyy • h:mm a').format(date);
      }

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes} minutes ago';
        }
        return '${difference.inHours} hours ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return DateFormat('MMM dd, yyyy').format(date);
      }
    } catch (e) {
      return dateString;
    }
  }

  String _formatActivityDescription(Map<String, dynamic> activity) {
    final type = activity['type'] as String;
    final description = activity['description']?.toString() ?? '';
    final metadata = activity['metadata'] ?? {};
    final withUser = metadata['with']?.toString();
    final byUser = metadata['by']?.toString();
    final toUser = metadata['to']?.toString();
    final fromUser = metadata['from']?.toString();

    switch (type) {
      case 'friend_request_sent':
        return toUser != null ? 'Sent friend request to $toUser' : description;
      case 'friend_request_received':
        return fromUser != null
            ? 'Received friend request from $fromUser'
            : description;
      case 'friend_request_accepted':
        return withUser != null
            ? 'Friend request accepted with $withUser'
            : description;
      case 'friend_request_declined':
        return withUser != null
            ? 'Friend request declined with $withUser'
            : description;
      case 'friend_request_canceled':
        return withUser != null
            ? 'Friend request canceled with $withUser'
            : description;
      case 'friend_removed':
        return withUser != null ? 'Friend removed: $withUser' : description;
      case 'user_blocked':
        return byUser != null ? 'Blocked by $byUser' : 'User blocked';
      case 'user_unblocked':
        return byUser != null ? 'Unblocked by $byUser' : 'User unblocked';
      default:
        return description;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        title: const Text('Activity Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              fetchActivities(refresh: true);
              fetchStats();
            },
          ),
        ],
      ),
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
                height: context.sh(156),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
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
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: const Center(child: CircularProgressIndicator()),
                      )
                    else if (activities.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyState(),
                      )
                    else
                      SliverList.builder(
                        itemCount: activities.length + (hasNextPage ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == activities.length) {
                            return _buildLoadMoreButton();
                          }
                          return _buildActivityListItem(activities[index]);
                        },
                      ),
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
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(2), // This creates the border width
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27), // Outer radius
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25), // Inner radius
        ),
        child: Row(
          children: [
            Icon(
              Icons.search,
              color: Colors.grey[600],
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                onChanged: _performSearch,
                decoration: InputDecoration(
                  hintText: 'Search activities...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (searchQuery.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear, color: Colors.grey[600], size: 20),
                onPressed: _clearSearch,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Activity Summary',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.cyan,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Activities',
                  '${stats['totalActivities'] ?? 0}',
                  Icons.timeline,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Recent (7 days)',
                  '${stats['recentActivities'] ?? 0}',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActivityInsights() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cyan,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.insights,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Activity Insights',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Insights Grid

          // Top Activity Types
          if (activityTypeCounts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Top Activity Types',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...activityTypeCounts.entries
                .take(3)
                .map((entry) => _buildActivityTypeRow(entry.key, entry.value)),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityTypeRow(String type, int count) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(
            _getActivityIcon(type),
            color: Colors.black,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getActivityTypeDisplayName(type),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        children: [
          if (searchQuery.isNotEmpty)
            Chip(
              label: Text('Search: "$searchQuery"'),
              onDeleted: _clearSearch,
              backgroundColor: Colors.purple.withValues(alpha: 0.2),
              deleteIcon: const Icon(Icons.clear, size: 18),
            ),
          if (_showBookmarkedOnly)
            Chip(
              label: const Text('Bookmarked'),
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
              label: Text('From: ${DateFormat('MMM dd').format(startDate!)}'),
              onDeleted: () {
                setState(() => startDate = null);
                fetchActivities(refresh: true);
              },
              backgroundColor: Colors.orange.withValues(alpha: 0.2),
            ),
          if (endDate != null)
            Chip(
              label: Text('To: ${DateFormat('MMM dd').format(endDate!)}'),
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timeline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No activities found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your activities will appear here',
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityListItem(Map<String, dynamic> activity) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _buildActivityCard(activity),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final type = activity['type'] as String;
    final title = activity['title'] as String;
    final createdAt = activity['createdAt'] as String;
    final amount = activity['amount'];
    final currency = activity['currency'];
    final metadata = activity['metadata'];
    final displayDescription = _formatActivityDescription(activity);

    // Custom highlight for rating activities
    final isRating = type == 'user_rated' || type == 'user_rating_received';
    final ratingValue = metadata != null && metadata['rating'] != null
        ? metadata['rating']
        : null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isRating
              ? Colors.amber.withValues(alpha: 0.7)
              : _getActivityColor(type).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Activity Icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isRating
                    ? Colors.amber.withValues(alpha: 0.15)
                    : _getActivityColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isRating
                      ? Colors.amber.withValues(alpha: 0.3)
                      : _getActivityColor(type).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                isRating ? Icons.star : _getActivityIcon(type),
                color: isRating ? Colors.amber : _getActivityColor(type),
                size: 28,
              ),
            ),
            const SizedBox(width: 12),

            // Activity Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isRating ? Colors.amber[900] : Colors.black,
                          ),
                        ),
                      ),
                      if (amount != null && currency != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '$currency$amount',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                      if (isRating && ratingValue != null)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$ratingValue ★',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayDescription,
                    style: TextStyle(
                      color: isRating ? Colors.amber[800] : Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(createdAt, activityType: type),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ),
                      // Delete Button
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'details') {
                            _showActivityDetails(activity);
                          } else if (value == 'bookmark') {
                            _bookmarkActivity(activity);
                          } else if (value == 'delete') {
                            _deleteActivity(activity);
                          }
                        },
                        itemBuilder: (BuildContext context) {
                          final isBookmarked = activity['bookmarked'] ?? false;
                          return <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'details',
                              child: ListTile(
                                leading: Icon(Icons.info, color: Colors.blue),
                                title: Text('View Details'),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'bookmark',
                              child: ListTile(
                                leading: Icon(Icons.bookmark,
                                    color: isBookmarked
                                        ? Colors.red
                                        : Colors.orange),
                                title: Text(
                                    isBookmarked ? 'Unbookmark' : 'Bookmark'),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: ListTile(
                                leading: Icon(Icons.delete, color: Colors.red),
                                title: Text('Delete'),
                              ),
                            ),
                          ];
                        },
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Center(
        child: ElevatedButton(
          onPressed: () {
            setState(() => currentPage++);
            fetchActivities();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.cyan,
            foregroundColor: Colors.white,
          ),
          child: const Text('Load More'),
        ),
      ),
    );
  }

  // Swipe Action Methods
  void _showActivityDetails(Map<String, dynamic> activity) {
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
              color: const Color(0xFFFCE4EC), // Light pink
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
                Text(activity['title'] ?? 'Activity Details',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text('Type: ${_getActivityTypeDisplayName(activity['type'])}'),
                const SizedBox(height: 8),
                Text('Description: ${_formatActivityDescription(activity)}'),
                const SizedBox(height: 8),
                Text(
                    'Date: ${_formatDate(activity['createdAt'], activityType: activity['type'])}'),
                if (activity['amount'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Amount: ${activity['currency']}${activity['amount']}'),
                ],
                if (activity['metadata'] != null) ...[
                  const SizedBox(height: 8),
                  Text('Additional Info: ${activity['metadata']}'),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
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
    final activityId = activity['_id'];
    final isBookmarked = activity['bookmarked'] ?? false;

    ElegantNotification.info(
      title: Text(isBookmarked ? "Unbookmarking" : "Bookmarking"),
      description: const Text("Please wait..."),
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
          title: const Text("Success"),
          description: Text(isBookmarked
              ? "Removed from bookmarks"
              : "Bookmarked successfully"),
        ).show(context);
      } else {
        setState(() {
          activity['bookmarked'] = isBookmarked; // Revert on failure
        });
        _showErrorDialog('Failed to update bookmark status');
      }
    } catch (e) {
      setState(() {
        activity['bookmarked'] = isBookmarked; // Revert on failure
      });
      _showErrorDialog('Error: $e');
    }
  }

  void _deleteActivity(Map<String, dynamic> activity) {
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
            color: Colors.white,
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
                    const Text(
                      'Delete Activity',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This action cannot be undone',
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
                      activity['title'] ?? 'Unknown Activity',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
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
                      'Are you sure you want to delete this activity? This action cannot be undone.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
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
                        label: const Text(
                          'Cancel',
                          style: TextStyle(
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

                              showSnack(context, 'Activity deleted successfully');
                            } else {
                              final errorData = json.decode(response.body);
                              showSnack(context, errorData['error'] ?? 'Failed to delete activity', isError: true);
                            }
                          } catch (e) {
                            showSnack(context, 'Error: $e', isError: true);
                          }
                        },
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.white),
                        label: const Text(
                          'Delete',
                          style: TextStyle(
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
    print('Filter dialog opened'); // Debug print
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
                              color: const Color(0xFFF4FBFE),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.category,
                                    color: AppColors.cyan, size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      'Select Activity Type',
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
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
                                  label: 'All Types',
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
                    color: Colors.white,
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
                                    color: Colors.white.withValues(alpha: 0.2),
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
                          const Text(
                            'Filter Activities',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Customize your activity view',
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
                                  color: Colors.white,
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
                                              const Text(
                                                'Activity Type',
                                                style: TextStyle(
                                                  color: AppColors.cyan,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: Text(
                                                  tempSelectedType == null
                                                      ? 'All Types'
                                                      : _getActivityTypeDisplayName(
                                                          tempSelectedType!),
                                                  maxLines: 1,
                                                  softWrap: false,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.black87,
                                                    fontWeight: FontWeight.w500,
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.18)),
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
                                      child: const Text(
                                        'Show Bookmarked Only',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
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
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.18)),
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
                                  const Icon(Icons.people, color: Colors.teal),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: const Text(
                                        'Friends Activity Only',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
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
                                    color: Colors.grey.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
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
                                      const Text(
                                        'Date Range',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
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
                                        label: 'Start Date',
                                        date: tempStartDate,
                                        onPressed: () async {
                                          final date = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                tempStartDate ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now(),
                                            builder: (context, child) {
                                              return Theme(
                                                data: Theme.of(context)
                                                    .copyWith(
                                                  colorScheme:
                                                      const ColorScheme.light(
                                                    primary:
                                                        AppColors.cyan,
                                                    onPrimary: Colors.white,
                                                    surface: Colors.white,
                                                    onSurface: Colors.black,
                                                  ),
                                                ),
                                                child: child!,
                                              );
                                            },
                                          );
                                          if (date != null) {
                                            setState(
                                                () => tempStartDate = date);
                                          }
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        child: const Icon(Icons.arrow_forward,
                                            color: Colors.grey),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildDateButton(
                                        context: context,
                                        label: 'End Date',
                                        date: tempEndDate,
                                        onPressed: () async {
                                          final date = await showDatePicker(
                                            context: context,
                                            initialDate:
                                                tempEndDate ?? DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now(),
                                            builder: (context, child) {
                                              return Theme(
                                                data: Theme.of(context)
                                                    .copyWith(
                                                  colorScheme:
                                                      const ColorScheme.light(
                                                    primary:
                                                        AppColors.cyan,
                                                    onPrimary: Colors.white,
                                                    surface: Colors.white,
                                                    onSurface: Colors.black,
                                                  ),
                                                ),
                                                child: child!,
                                              );
                                            },
                                          );
                                          if (date != null) {
                                            setState(() => tempEndDate = date);
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
                              label: const Text(
                                'Clear All',
                                style: TextStyle(
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
                              icon:
                                  const Icon(Icons.check, color: Colors.white),
                              label: const Text(
                                'Apply Filters',
                                style: TextStyle(
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
                color: date != null ? Colors.black87 : Colors.grey[600],
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
          color: selected ? const Color(0xFFE9F8FC) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.cyan
                : Colors.grey.withValues(alpha: 0.20),
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
                    color: Colors.black87,
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

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
