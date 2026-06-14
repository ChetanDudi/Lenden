import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class TrackUserActivityPage extends StatefulWidget {
  @override
  _TrackUserActivityPageState createState() => _TrackUserActivityPageState();
}

class _TrackUserActivityPageState extends State<TrackUserActivityPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _activities = [];
  bool _loading = false;
  String? _error;
  String? _searchedTerm;
  String _selectedCategory = 'all';

  static const Map<String, List<String>> _categoryTypes = {
    'auth': ['login', 'logout'],
    'transactions': [
      'transaction_created',
      'transaction_cleared',
      'partial_payment_made',
      'partial_payment_received'
    ],
    'groups': [
      'group_created',
      'group_joined',
      'group_left',
      'member_added',
      'member_removed'
    ],
    'expenses': [
      'expense_added',
      'expense_edited',
      'expense_deleted',
      'expense_settled'
    ],
    'notes': ['note_created', 'note_edited', 'note_deleted'],
    'profile': ['profile_updated', 'password_changed'],
  };

  static const Map<String, String> _categoryLabels = {
    'all': 'All',
    'auth': 'Auth',
    'transactions': 'Transactions',
    'groups': 'Groups',
    'expenses': 'Expenses',
    'notes': 'Notes',
    'profile': 'Profile',
  };

  static const Map<String, IconData> _categoryIcons = {
    'all': Icons.apps_rounded,
    'auth': Icons.login_rounded,
    'transactions': Icons.swap_horiz_rounded,
    'groups': Icons.group_rounded,
    'expenses': Icons.receipt_rounded,
    'notes': Icons.note_rounded,
    'profile': Icons.person_rounded,
  };

  List<dynamic> get _filteredActivities {
    if (_selectedCategory == 'all') return _activities;
    final types = _categoryTypes[_selectedCategory] ?? [];
    return _activities
        .where((a) => types.contains(a['type'] as String?))
        .toList();
  }

  Future<void> _fetchUserActivity(String searchTerm) async {
    setState(() {
      _loading = true;
      _error = null;
      _searchedTerm = searchTerm;
      _activities = [];
    });

    try {
      final response = await ApiClient.get(
          '/api/admin/user-activity/${Uri.encodeComponent(searchTerm)}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _activities = data['activities'] ?? [];
          _loading = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _error = data['error'] ?? 'Failed to load activities.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred: $e';
        _loading = false;
      });
    }
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
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String dateString, {String? activityType}) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

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

  Widget _triBorder({
    required Widget child,
    double radius = 18,
    EdgeInsets padding = const EdgeInsets.all(2),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredActivities;
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
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Track User Activity',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (_searchedTerm != null && _activities.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                          onPressed: () =>
                              _fetchUserActivity(_searchedTerm!),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Search bar
                _buildSearchBar(),

                // Category filter chips
                if (_searchedTerm != null && _activities.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildCategoryChips(),
                ],

                // Result count
                if (_searchedTerm != null && !_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      '${filtered.length} activit${filtered.length == 1 ? 'y' : 'ies'}'
                      '${_selectedCategory != 'all' ? ' in ${_categoryLabels[_selectedCategory]}' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style:
                                      const TextStyle(color: Colors.red)))
                          : _searchedTerm == null || _activities.isEmpty
                              ? _buildEmptyState()
                              : filtered.isEmpty
                                  ? _buildNoFilterResults()
                                  : ListView.builder(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 16),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final activity = filtered[index];
                                        return _buildActivityCard(activity);
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: _triBorder(
        radius: 25,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey[600], size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _fetchUserActivity(value.trim());
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by Email or Username...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon:
                      Icon(Icons.clear, color: Colors.grey[600], size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _activities = [];
                      _searchedTerm = null;
                      _error = null;
                      _selectedCategory = 'all';
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  final val = _searchController.text.trim();
                  if (val.isNotEmpty) _fetchUserActivity(val);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4D8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Search',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _categoryLabels.keys.map((key) {
          final isSelected = _selectedCategory == key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00B4D8)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF00B4D8)
                        : Colors.grey.shade300,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00B4D8)
                                .withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _categoryIcons[key]!,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : Colors.grey[600],
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _categoryLabels[key]!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final type = activity['type'] as String? ?? 'unknown';
    final title =
        activity['title'] as String? ?? _getActivityTypeDisplayName(type);
    final description =
        activity['description'] as String? ?? 'No description';
    final createdAt = activity['timestamp'] as String? ??
        DateTime.now().toIso8601String();
    final amount = activity['amount'];
    final currency = activity['currency'];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getActivityColor(type).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    _getActivityColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color:
                      _getActivityColor(type).withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                _getActivityIcon(type),
                color: _getActivityColor(type),
                size: 24,
              ),
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
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (amount != null && currency != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.green
                                  .withValues(alpha: 0.3),
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
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDate(createdAt, activityType: type),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.manage_search_rounded,
              size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchedTerm == null
                ? 'Search for a user to view activities'
                : 'No activities found for "$_searchedTerm"',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _searchedTerm == null
                ? 'Enter an email or username in the search bar above'
                : 'Try a different search term or check the spelling',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNoFilterResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.filter_list_off_rounded,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No ${_categoryLabels[_selectedCategory]} activities',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () =>
                setState(() => _selectedCategory = 'all'),
            child: const Text('Show all activities'),
          ),
        ],
      ),
    );
  }
}
