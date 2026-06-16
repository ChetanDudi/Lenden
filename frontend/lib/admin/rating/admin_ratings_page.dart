import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../profile/profile_page.dart' hide TopWaveClipper, BottomWaveClipper;
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class AdminRatingsPage extends StatefulWidget {
  const AdminRatingsPage({Key? key}) : super(key: key);

  @override
  State<AdminRatingsPage> createState() => _AdminRatingsPageState();
}

class _AdminRatingsPageState extends State<AdminRatingsPage> {
  List<Map<String, dynamic>> _ratings = [];
  bool _isLoading = false;
  String? _error;
  int _starFilter = 0; // 0 = all, 1-5 = specific star count
  String _sortBy = 'newest'; // newest, highest, lowest

  @override
  void initState() {
    super.initState();
    _fetchRatings();
  }

  Future<void> _fetchRatings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await ApiClient.get('/api/rating/all');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _ratings =
              List<Map<String, dynamic>>.from(data['ratings'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load ratings';
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

  List<Map<String, dynamic>> get _filteredRatings {
    var result = _starFilter == 0
        ? List<Map<String, dynamic>>.from(_ratings)
        : _ratings
            .where((r) => (r['rating'] as num?)?.toInt() == _starFilter)
            .toList();

    switch (_sortBy) {
      case 'highest':
        result.sort((a, b) =>
            ((b['rating'] as num?)?.toInt() ?? 0)
                .compareTo((a['rating'] as num?)?.toInt() ?? 0));
        break;
      case 'lowest':
        result.sort((a, b) =>
            ((a['rating'] as num?)?.toInt() ?? 0)
                .compareTo((b['rating'] as num?)?.toInt() ?? 0));
        break;
      default:
        result.sort((a, b) =>
            (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? ''));
    }
    return result;
  }

  double get _avgRating {
    if (_ratings.isEmpty) return 0.0;
    final total = _ratings.fold<int>(
        0, (sum, r) => sum + ((r['rating'] as num?)?.toInt() ?? 0));
    return total / _ratings.length;
  }

  Map<int, int> get _starDistribution {
    final dist = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _ratings) {
      final star = (r['rating'] as num?)?.toInt() ?? 0;
      if (star >= 1 && star <= 5) dist[star] = dist[star]! + 1;
    }
    return dist;
  }

  Widget _buildStatsSection() {
    final dist = _starDistribution;
    final avg = _avgRating;
    final total = _ratings.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Average rating big display
          Column(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan,
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < avg.round() ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$total rating${total == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Star distribution bars
          Expanded(
            child: Column(
              children: [5, 4, 3, 2, 1].map((star) {
                final count = dist[star] ?? 0;
                final ratio = total == 0 ? 0.0 : count / total;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600])),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, size: 11, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: Colors.grey[200],
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.amber),
                            minHeight: 7,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 20,
                        child: Text(
                          '$count',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey[600]),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [0, 5, 4, 3, 2, 1].map((star) {
                  final isSelected = _starFilter == star;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _starFilter = star),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.cyan
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.cyan
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: star == 0
                            ? Text(
                                'All',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey[700],
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$star',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(Icons.star,
                                      size: 13,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.amber),
                                ],
                              ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // Sort button
          GestureDetector(
            onTap: _showSortSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded,
                      size: 16, color: Colors.grey[700]),
                  const SizedBox(width: 4),
                  Text(
                    _sortBy == 'newest'
                        ? 'Newest'
                        : _sortBy == 'highest'
                            ? 'Highest'
                            : 'Lowest',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
            _buildSortTile('newest', 'Newest First', Icons.access_time),
            _buildSortTile(
                'highest', 'Highest Rating', Icons.arrow_upward),
            _buildSortTile(
                'lowest', 'Lowest Rating', Icons.arrow_downward),
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
            color: isSelected
                ? AppColors.cyan
                : Colors.grey[800],
            fontWeight:
                isSelected ? FontWeight.bold : FontWeight.normal,
          )),
      trailing: isSelected
          ? const Icon(Icons.check_circle,
              color: AppColors.cyan)
          : null,
      onTap: () {
        setState(() => _sortBy = value);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildRatingCard(Map<String, dynamic> rating) {
    final stars = (rating['rating'] as num?)?.toInt() ?? 0;
    final review = rating['review'] as String?;
    final dateStr = rating['createdAt']?.toString();
    String? formattedDate;
    if (dateStr != null && dateStr.length >= 10) {
      formattedDate = dateStr.substring(0, 10);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.cyan,
                  radius: 20,
                  child: Text(
                    (rating['userName'] as String? ?? 'U')
                        .substring(0, 1)
                        .toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rating['userName'] ?? 'User',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      if (rating['userEmail'] != null)
                        Text(rating['userEmail'],
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (formattedDate != null)
                      Text(formattedDate,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(
                        5,
                        (i) => Icon(
                          i < stars ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (review != null && review.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
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
                        review,
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.person_outline, size: 16),
              label: const Text('View Profile'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.cyan,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfilePage(email: rating['userEmail']),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRatings;
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
                            'User Ratings',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Refresh',
                        onPressed: _fetchRatings,
                      ),
                    ],
                  ),
                ),

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
                                    onPressed: _fetchRatings,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _ratings.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star_border_rounded,
                                          size: 72,
                                          color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text('No ratings yet',
                                          style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.grey[500])),
                                    ],
                                  ),
                                )
                              : Column(
                                  children: [
                                    _buildStatsSection(),
                                    _buildFilterBar(),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 10, 20, 4),
                                      child: Align(
                                        alignment:
                                            Alignment.centerLeft,
                                        child: Text(
                                          '${filtered.length} rating${filtered.length == 1 ? '' : 's'}'
                                          '${_starFilter > 0 ? ' — $_starFilter★ only' : ''}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                              fontWeight:
                                                  FontWeight.w500),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: filtered.isEmpty
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .center,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .filter_list_off_rounded,
                                                      size: 48,
                                                      color: Colors
                                                          .grey[300]),
                                                  const SizedBox(
                                                      height: 12),
                                                  Text(
                                                    'No $_starFilter-star ratings',
                                                    style: TextStyle(
                                                        color: Colors
                                                            .grey[500]),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        setState(() =>
                                                            _starFilter =
                                                                0),
                                                    child: const Text(
                                                        'Show all'),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : ListView.builder(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      16, 0, 16, 24),
                                              itemCount: filtered.length,
                                              itemBuilder: (_, idx) =>
                                                  _buildRatingCard(
                                                      filtered[idx]),
                                            ),
                                    ),
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
}
