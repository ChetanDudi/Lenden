import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'dart:convert';
import '../../profile/profile_page.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

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
          _error = AppLocalizations.of(context).t('failed_to_load_ratings');
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '${AppLocalizations.of(context).t('error')}: $e';
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
    final t = AppLocalizations.of(context).t;
    final dist = _starDistribution;
    final avg = _avgRating;
    final total = _ratings.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
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
                '$total ${total == 1 ? t('rating') : t('ratings')}',
                style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)),
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
                              fontSize: 11, color: AppThemeColors.secondaryText(context))),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, size: 11, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: AppThemeColors.divider(context),
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
                              fontSize: 11, color: AppThemeColors.secondaryText(context)),
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
    final t = AppLocalizations.of(context).t;
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
                              : AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.cyan
                                : AppThemeColors.border(context),
                          ),
                        ),
                        child: star == 0
                            ? Text(
                                t('all'),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : AppThemeColors.primaryText(context),
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
                                          : AppThemeColors.primaryText(context),
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
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppThemeColors.border(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded,
                      size: 16, color: AppThemeColors.secondaryText(context)),
                  const SizedBox(width: 4),
                  Text(
                    _sortBy == 'newest'
                        ? t('newest')
                        : _sortBy == 'highest'
                            ? t('highest')
                            : t('lowest'),
                    style: TextStyle(
                        fontSize: 13, color: AppThemeColors.secondaryText(context)),
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
      builder: (sheetContext) {
        final t = AppLocalizations.of(sheetContext).t;
        return Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColors.divider(sheetContext),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('sort_by'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(sheetContext))),
              ),
            ),
            _buildSortTile('newest', t('newest_first'), Icons.access_time),
            _buildSortTile(
                'highest', t('highest_rating'), Icons.arrow_upward),
            _buildSortTile(
                'lowest', t('lowest_rating'), Icons.arrow_downward),
            const SizedBox(height: 24),
          ],
        ),
      );
      },
    );
  }

  Widget _buildSortTile(String value, String label, IconData icon) {
    final isSelected = _sortBy == value;
    return ListTile(
      leading: Icon(icon,
          color: isSelected ? AppColors.cyan : AppThemeColors.secondaryText(context)),
      title: Text(label,
          style: TextStyle(
            color: isSelected
                ? AppColors.cyan
                : AppThemeColors.primaryText(context),
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
    final t = AppLocalizations.of(context).t;
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
        color: AppThemeColors.cardBg(context),
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
                      Text(rating['userName'] ?? t('username'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppThemeColors.primaryText(context))),
                      if (rating['userEmail'] != null)
                        Text(rating['userEmail'],
                            style: TextStyle(
                                fontSize: 12, color: AppThemeColors.secondaryText(context))),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (formattedDate != null)
                      Text(formattedDate,
                          style: TextStyle(
                              fontSize: 11, color: AppThemeColors.secondaryText(context))),
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
                  color: AppThemeColors.surfaceBg(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppThemeColors.border(context)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded,
                        size: 16, color: AppThemeColors.mutedText(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        review,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppThemeColors.secondaryText(context),
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
              label: Text(t('view_profile')),
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
    final t = AppLocalizations.of(context).t;
    final filtered = _filteredRatings;
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
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(
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
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            t('user_ratings'),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, color: AppThemeColors.primaryText(context)),
                        tooltip: t('refresh'),
                        onPressed: _fetchRatings,
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? errorStateWidget(context, _error!, _fetchRatings)
                          : _ratings.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.star_border_rounded,
                                          size: 72,
                                          color: AppThemeColors.mutedText(context)),
                                      const SizedBox(height: 16),
                                      Text(t('no_ratings_yet'),
                                          style: TextStyle(
                                              fontSize: 18,
                                              color: AppThemeColors.mutedText(context))),
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
                                          '${filtered.length} ${filtered.length == 1 ? t('rating') : t('ratings')}'
                                          '${_starFilter > 0 ? ' — $_starFilter★ ${t('only')}' : ''}',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppThemeColors.secondaryText(context),
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
                                                      color: AppThemeColors
                                                          .mutedText(context)),
                                                  const SizedBox(
                                                      height: 12),
                                                  Text(
                                                    '${t('no')} $_starFilter-${t('star_ratings')}',
                                                    style: TextStyle(
                                                        color: AppThemeColors
                                                            .mutedText(context)),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        setState(() =>
                                                            _starFilter =
                                                                0),
                                                    child: Text(
                                                        t('show_all')),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : RefreshIndicator(
                                              onRefresh: _fetchRatings,
                                              child: ListView.builder(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                        16, 0, 16, 24),
                                                itemCount: filtered.length,
                                                itemBuilder: (_, idx) =>
                                                    _buildRatingCard(
                                                        filtered[idx]),
                                              ),
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
