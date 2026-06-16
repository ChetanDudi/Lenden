import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../profile/profile_page.dart' hide TopWaveClipper;
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';

class AdminFeedbacksPage extends StatefulWidget {
  const AdminFeedbacksPage({Key? key}) : super(key: key);

  @override
  State<AdminFeedbacksPage> createState() => _AdminFeedbacksPageState();
}

class _AdminFeedbacksPageState extends State<AdminFeedbacksPage> {
  List<Map<String, dynamic>> _feedbacks = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = false;
  String? _error;
  String _search = '';
  String _sortBy = 'newest';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchFeedbacks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFeedbacks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/feedbacks/all');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list =
            List<Map<String, dynamic>>.from(data['feedbacks'] ?? []);
        setState(() {
          _feedbacks = list;
          _isLoading = false;
        });
        _applyFilter();
      } else {
        setState(() {
          _error = 'Failed to load feedbacks';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _search.toLowerCase();
    var result = _feedbacks.where((f) {
      if (q.isEmpty) return true;
      final name = (f['userName'] ?? '').toString().toLowerCase();
      final email = (f['userEmail'] ?? '').toString().toLowerCase();
      final username = (f['username'] ?? '').toString().toLowerCase();
      final text = (f['feedback'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          email.contains(q) ||
          username.contains(q) ||
          text.contains(q);
    }).toList();

    result.sort((a, b) {
      switch (_sortBy) {
        case 'oldest':
          return (a['createdAt'] ?? '')
              .compareTo(b['createdAt'] ?? '');
        case 'rating_high':
          return ((b['avgRating'] as num?) ?? 0)
              .compareTo((a['avgRating'] as num?) ?? 0);
        case 'rating_low':
          return ((a['avgRating'] as num?) ?? 0)
              .compareTo((b['avgRating'] as num?) ?? 0);
        default: // newest
          return (b['createdAt'] ?? '')
              .compareTo(a['createdAt'] ?? '');
      }
    });

    setState(() => _filtered = result);
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            _buildSortTile('newest', 'Newest First',
                Icons.arrow_downward_rounded),
            _buildSortTile('oldest', 'Oldest First',
                Icons.arrow_upward_rounded),
            _buildSortTile('rating_high', 'Highest Rating',
                Icons.star_rounded),
            _buildSortTile('rating_low', 'Lowest Rating',
                Icons.star_border_rounded),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSortTile(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Icon(icon,
          color: isSelected ? AppColors.cyan : Colors.grey),
      title: Text(label,
          style: TextStyle(
            color: isSelected ? AppColors.cyan : Colors.grey[800],
            fontWeight:
                isSelected ? FontWeight.bold : FontWeight.normal,
          )),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.cyan)
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        _applyFilter();
        Navigator.pop(context);
      },
    );
  }

  Widget _buildFeedbackCard(Map<String, dynamic> feedback) {
    final avgRating = (feedback['avgRating'] as num?)?.toDouble() ?? 0.0;
    final isActive = feedback['isActive'] == true;
    final isVerified = feedback['isVerified'] == true;
    final dateStr = _formatDate(feedback['createdAt'] as String?);
    final name = (feedback['userName'] as String?) ?? 'User';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                  child: Text(
                    name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.cyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
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
                              name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                          ),
                          if (avgRating > 0)
                            Row(
                              children: [
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 14),
                                const SizedBox(width: 2),
                                Text(
                                  avgRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (feedback['userEmail'] != null)
                        Text(
                          feedback['userEmail'].toString(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      if (feedback['username'] != null)
                        Text(
                          '@${feedback['username']}',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.cyan),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildBadge(
                            isActive ? 'Active' : 'Inactive',
                            isActive ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          if (isVerified)
                            _buildBadge('Verified', Colors.blue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded,
                      size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (feedback['feedback'] as String?) ?? '',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time_rounded,
                    size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    dateStr,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
                if (feedback['userEmail'] != null)
                  TextButton.icon(
                    icon: const Icon(Icons.person_outline, size: 14),
                    label: const Text('Profile'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.cyan,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfilePage(
                            email: feedback['userEmail'].toString()),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
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
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                  ),
                ),
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
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'User Feedbacks',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.sort_rounded),
                        tooltip: 'Sort',
                        onPressed: _showSortSheet,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh',
                        onPressed: _fetchFeedbacks,
                      ),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      gradient: const LinearGradient(
                        colors: [
                          Colors.orange,
                          Colors.white,
                          Colors.green
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search,
                              color: Colors.grey[500], size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onChanged: (v) {
                                setState(() => _search = v);
                                _applyFilter();
                              },
                              decoration: InputDecoration(
                                hintText:
                                    'Search by name, email, or text...',
                                hintStyle:
                                    TextStyle(color: Colors.grey[400]),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 4),
                              ),
                            ),
                          ),
                          if (_search.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _search = '');
                                _applyFilter();
                              },
                              child: Icon(Icons.clear,
                                  color: Colors.grey[400], size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Count
                if (!_isLoading && _error == null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      '${_filtered.length} feedback${_filtered.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                    ),
                  ),

                const SizedBox(height: 4),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48,
                                      color: Colors.red[300]),
                                  const SizedBox(height: 12),
                                  Text(_error!,
                                      style: const TextStyle(
                                          color: Colors.red)),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _fetchFeedbacks,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.feedback_outlined,
                                          size: 64,
                                          color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text(
                                        _search.isEmpty
                                            ? 'No feedbacks yet'
                                            : 'No results for "$_search"',
                                        style: TextStyle(
                                            fontSize: 17,
                                            color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 24),
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) =>
                                      _buildFeedbackCard(_filtered[i]),
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
