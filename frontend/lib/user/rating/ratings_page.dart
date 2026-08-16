import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import '../../widgets/wave_widget.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../digitise/subscriptions_page.dart';
import '../../api_config.dart';

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  double? avgRating;
  List<dynamic> ratingsGiven = [];
  List<dynamic> ratingsReceived = [];
  bool loading = true;
  String? error;

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _commentController = TextEditingController();
  double _selectedRating = 5;
  String? _submitError;
  bool _submitting = false;
  bool _showSuccess = false;

  final _searchController = TextEditingController();
  String? _searchError;
  double? _searchedAvgRating;
  String? _searchedUserId;
  String? _searchedName;
  String? _searchedUsername;
  String? _searchedEmail;
  int? _searchedTotalRatings;
  Map<String, int>? _searchedDistribution;
  bool _searching = false;

  List<Map<String, dynamic>> _friends = [];
  List<dynamic> ratingActivities = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchRatings();
    fetchRatingActivities();
    _fetchFriends();
    _usernameController.addListener(() {
      if (_showSuccess) setState(() => _showSuccess = false);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _usernameController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> fetchRatings() async {
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiClient.get('/api/ratings/me');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          avgRating = data['avgRating']?.toDouble();
          ratingsGiven = data['ratingsGiven'] ?? [];
          ratingsReceived = data['ratingsReceived'] ?? [];
          loading = false;
        });
      } else {
        setState(() {
          error = AppLocalizations.of(context).t('failed_to_load_ratings');
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        error = AppLocalizations.of(context).t('failed_to_load_ratings');
        loading = false;
      });
    }
  }

  Future<void> fetchRatingActivities() async {
    try {
      final res = await ApiClient.get('/api/activities?type=user_rated,user_rating_received&limit=10');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) setState(() => ratingActivities = data['activities'] ?? []);
      }
    } catch (_) {}
  }

  Future<void> _fetchFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        setState(() => _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> submitRating() async {
    final t = AppLocalizations.of(context).t;
    if (!_formKey.currentState!.validate()) return;
    setState(() { _submitting = true; _submitError = null; _showSuccess = false; });
    final res = await ApiClient.post('/api/ratings', body: {
      'usernameOrEmail': _usernameController.text.trim(),
      'rating': _selectedRating,
      'comment': _commentController.text.trim(),
    });
    if (res.statusCode == 201) {
      setState(() { _showSuccess = true; _usernameController.clear(); _selectedRating = 5; });
      _commentController.clear();
      fetchRatings();
    } else {
      setState(() => _submitError = json.decode(res.body)['error'] ?? t('failed_to_submit_rating'));
    }
    setState(() => _submitting = false);
  }

  Future<void> _searchUserRating() async {
    final t = AppLocalizations.of(context).t;
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      setState(() { _searchError = t('enter_username_or_email_error'); _searchedAvgRating = null; });
      return;
    }
    final session = Provider.of<SessionProvider>(context, listen: false);
    final lower = input.toLowerCase();
    final myEmail = (session.user?['email'] ?? '').toString().toLowerCase();
    final myUsername = (session.user?['username'] ?? '').toString().toLowerCase();
    if (lower == myEmail || (myUsername.isNotEmpty && lower == myUsername)) {
      setState(() { _searchError = t('thats_you_ratings_first_tab'); _searchedAvgRating = null; });
      return;
    }
    setState(() { _searching = true; _searchError = null; _searchedAvgRating = null; _searchedDistribution = null; });
    try {
      final res = await ApiClient.get('/api/ratings/user-avg?usernameOrEmail=$input');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        Map<String, int>? dist;
        if (data['distribution'] != null) {
          dist = (data['distribution'] as Map).map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
        }
        setState(() {
          _searchedAvgRating = (data['avgRating'] ?? 0).toDouble();
          _searchedUserId = data['_id']?.toString() ?? '';
          _searchedName = data['name'] ?? '';
          _searchedUsername = data['username'] ?? '';
          _searchedEmail = data['email'] ?? '';
          _searchedTotalRatings = data['totalRatings'];
          _searchedDistribution = dist;
        });
      } else {
        final err = json.decode(res.body);
        setState(() => _searchError = err['error'] ?? t('user_not_found_label'));
      }
    } catch (_) {
      setState(() => _searchError = t('error_searching_user'));
    }
    setState(() => _searching = false);
  }

  void _showEditRatingSheet(Map<String, dynamic> r) {
    final t = AppLocalizations.of(context).t;
    final ratingId = r['_id']?.toString() ?? '';
    if (ratingId.isEmpty) return;
    final commentCtrl = TextEditingController(text: r['comment'] ?? '');
    double localRating = (r['rating'] ?? 5).toDouble();
    bool isUpdating = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx), borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 16),
                Text(t('edit_rating_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                const SizedBox(height: 4),
                Text('${t('rating_for_label')} ${r['rateeName'] ?? t('user_fallback')}',
                  style: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 13)),
                const SizedBox(height: 20),
                _interactiveStars(ctx, localRating, (val) => setSheet(() => localRating = val), size: 40),
                const SizedBox(height: 6),
                Text(
                  localRating == 5 ? t('excellent_label') : localRating >= 4 ? t('great_label') :
                  localRating >= 3 ? t('good_label') : localRating >= 2 ? t('fair_label') : t('poor_label'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15,
                    color: localRating >= 4 ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: commentCtrl,
                  maxLines: 3,
                  maxLength: 200,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    labelText: t('comment_optional_label'),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(ctx),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                    ),
                    counterStyle: TextStyle(color: AppThemeColors.mutedText(ctx), fontSize: 11),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: isUpdating ? null : () async {
                        setSheet(() => isUpdating = true);
                        final res = await ApiClient.patch('/api/ratings/$ratingId', body: {
                          'rating': localRating,
                          'comment': commentCtrl.text.trim(),
                        });
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (res.statusCode == 200) {
                          fetchRatings();
                          if (mounted) showSnack(context, t('rating_updated_label'));
                        } else {
                          if (mounted) showSnack(context, json.decode(res.body)['error'] ?? t('failed_to_update_label'), isError: true);
                        }
                      },
                      child: Text(t('update_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => commentCtrl.dispose());
  }

  // ─── Section card (profile-style) ──────────────────────────────────────────

  Widget _sectionCard(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 3, height: 13,
                  decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold,
                    letterSpacing: 1.0, color: AppThemeColors.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 12, thickness: 0.5, color: AppThemeColors.divider(context)),
          child,
        ],
      ),
    );
  }

  Widget _buildStatMetric(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
      ],
    );
  }

  // ─── Shared UI helpers ───────────────────────────────────────────────────────

  Widget _starRow(double value, {double size = 24}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < value.floor()) return Icon(Icons.star_rounded, color: Colors.amber, size: size);
        if (i < value) return Icon(Icons.star_half_rounded, color: Colors.amber, size: size);
        return Icon(Icons.star_outline_rounded, color: Colors.amber.withValues(alpha: 0.4), size: size);
      }),
    );
  }

  Widget _distributionBars(Map<String, int> dist, int total) {
    return Column(
      children: List.generate(5, (i) {
        final star = 5 - i;
        final count = dist[star.toString()] ?? 0;
        final pct = total > 0 ? count / total : 0.0;
        final color = star >= 4 ? Colors.green : Colors.orange;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.5),
          child: Row(children: [
            Text('$star', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const SizedBox(width: 2),
            const Icon(Icons.star_rounded, color: Colors.amber, size: 11),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  backgroundColor: AppThemeColors.divider(context),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 7,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              child: Text('$count', style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
            ),
          ]),
        );
      }),
    );
  }

  Widget _interactiveStars(BuildContext context, double value, ValueChanged<double> onChange, {double size = 32}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => GestureDetector(
        onTap: () => onChange((i + 1).toDouble()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            i < value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < value ? Colors.amber : AppThemeColors.divider(context),
            size: size,
          ),
        ),
      )),
    );
  }

  Widget _friendsAvatarList(List<Map<String, dynamic>> friends, {required void Function(String username) onTap}) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: friends.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final f = friends[i];
          final fId = (f['_id'] ?? '').toString();
          final fName = (f['name'] ?? f['username'] ?? '').toString();
          final fUsername = (f['username'] ?? '').toString();
          final initials = fName.isNotEmpty ? fName[0].toUpperCase()
              : (fUsername.isNotEmpty ? fUsername[0].toUpperCase() : '?');
          return GestureDetector(
            onTap: () => onTap(fUsername),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.cyan.withValues(alpha: 0.15)),
                  child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                    Center(child: Text(initials, style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold, fontSize: 16))),
                    if (fId.isNotEmpty)
                      Image.network(
                        '${ApiConfig.baseUrl}/api/users/$fId/profile-image',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                  ])),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 52,
                  child: Text(fUsername,
                    style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context)),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _ratingCard(Map<String, dynamic> r, {required bool isGiven}) {
    final t = AppLocalizations.of(context).t;
    final rating = (r['rating'] ?? 0).toDouble();
    final name = isGiven
        ? (r['rateeName'] ?? r['ratee'] ?? t('user_fallback')).toString()
        : (r['raterName'] ?? r['rater'] ?? t('user_fallback')).toString();
    final prefix = isGiven ? t('to_label') : t('from_label');
    final starColor = rating >= 4 ? Colors.green : Colors.orange;
    final comment = r['comment']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: starColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                rating.toStringAsFixed(1),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: starColor),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$prefix: $name',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                _starRow(rating, size: 16),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('"$comment"',
                    style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12, fontStyle: FontStyle.italic),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (isGiven && r['_id'] != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.cyan),
              onPressed: () => _showEditRatingSheet(r),
              tooltip: t('edit'),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }

  Widget _myRatingHero() {
    final t = AppLocalizations.of(context).t;
    final stars = avgRating ?? 0.0;
    final color = stars >= 4 ? const Color(0xFF2E7D32) : Colors.orange;
    return _sectionCard(
      t('your_rating_label').toUpperCase(),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  avgRating != null ? avgRating!.toStringAsFixed(2) : '—',
                  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _starRow(stars, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      stars == 5 ? t('excellent_label') :
                      stars >= 4 ? t('great_label') :
                      stars >= 3 ? t('good_label') :
                      stars >= 2 ? t('fair_label') : t('poor_label'),
                      style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _buildStatMetric(Icons.arrow_upward, t('given_label'), '${ratingsGiven.length}', Colors.blue)),
                Container(width: 1, height: 44, color: AppThemeColors.divider(context)),
                Expanded(child: _buildStatMetric(Icons.arrow_downward, t('received_label'), '${ratingsReceived.length}', Colors.purple)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Tab: Rate ───────────────────────────────────────────────────────────────

  Widget _buildRateTab() {
    final t = AppLocalizations.of(context).t;
    final ratedIds = ratingsGiven.map((r) => r['ratee']?.toString() ?? '').toSet();
    final unrated = _friends.where((f) {
      final fid = (f['_id'] ?? '').toString();
      return fid.isNotEmpty && !ratedIds.contains(fid);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: _sectionCard(
        t('rate_another_user_title').toUpperCase(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showSuccess)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(t('rating_submitted_successfully'),
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                  ]),
                ),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        labelText: t('username_or_email_label'),
                        prefixIcon: const Icon(Icons.person_search_outlined),
                        filled: true,
                        fillColor: AppThemeColors.surfaceBg(context),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                        ),
                      ),
                      validator: (val) => val == null || val.isEmpty ? t('required') : null,
                    ),
                    if (unrated.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(t('friends_to_rate_label'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppThemeColors.mutedText(context))),
                      const SizedBox(height: 8),
                      _friendsAvatarList(unrated, onTap: (username) {
                        _usernameController.text = username;
                        if (_showSuccess) setState(() => _showSuccess = false);
                      }),
                    ],
                    const SizedBox(height: 20),
                    Text(t('give_rating_as_label'),
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
                    const SizedBox(height: 10),
                    Center(
                      child: Column(
                        children: [
                          StatefulBuilder(
                            builder: (context, _) => _interactiveStars(
                              context, _selectedRating,
                              (val) => setState(() => _selectedRating = val),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedRating == 5 ? t('excellent_label') :
                            _selectedRating >= 4 ? t('great_label') :
                            _selectedRating >= 3 ? t('good_label') :
                            _selectedRating >= 2 ? t('fair_label') : t('poor_label'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16,
                              color: _selectedRating >= 4 ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(t('comment_optional_label'),
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context), fontSize: 13)),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _commentController,
                      maxLines: 3,
                      maxLength: 200,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        hintText: t('share_your_experience_placeholder'),
                        filled: true,
                        fillColor: AppThemeColors.surfaceBg(context),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
                        ),
                        counterStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11),
                      ),
                    ),
                    if (_submitError != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Flexible(child: Text(_submitError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                        ]),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          elevation: 0,
                        ),
                        onPressed: _submitting ? null : submitRating,
                        child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(t('submit_rating_label'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
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

  // ─── Tab: Search ─────────────────────────────────────────────────────────────

  Widget _buildSearchTab() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Consumer<SessionProvider>(
        builder: (context, session, _) {
          if (!session.hasFeature('view_rankings')) {
            return _sectionCard(
              t('premium_feature_label').toUpperCase(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.lock_rounded, size: 36, color: AppColors.cyan),
                  ),
                  const SizedBox(height: 14),
                  Text(t('subscribe_to_search_ratings'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppThemeColors.secondaryText(context))),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.workspace_premium, color: Colors.amber),
                      label: Text(t('subscribe_now_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                    ),
                  ),
                ]),
              ),
            );
          }

          return Column(
            children: [
              _sectionCard(
                t('search').toUpperCase(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      AppSearchBar(
                        controller: _searchController,
                        hintText: t('enter_username_or_email_placeholder'),
                        isLoading: _searching,
                        onSubmit: _searchUserRating,
                        margin: EdgeInsets.zero,
                      ),
                      if (_searchError != null)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline, color: Colors.red, size: 16),
                            const SizedBox(width: 8),
                            Flexible(child: Text(_searchError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              if (_friends.isNotEmpty)
                _sectionCard(
                  t('friends_ratings_header_label').toUpperCase(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: _friendsAvatarList(_friends, onTap: (username) {
                      _searchController.text = username;
                      _searchUserRating();
                    }),
                  ),
                ),
              if (_searchedAvgRating != null)
                _sectionCard(
                  'SEARCH RESULT',
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Column(children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppColors.cyan.withValues(alpha: 0.12),
                        child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                          Center(child: Text(
                            (_searchedName?.isNotEmpty == true
                                ? _searchedName![0]
                                : _searchedUsername?[0] ?? '?').toUpperCase(),
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.cyan),
                          )),
                          if ((_searchedUserId ?? '').isNotEmpty)
                            Image.network(
                              '${ApiConfig.baseUrl}/api/users/$_searchedUserId/profile-image',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                            ),
                        ])),
                      ),
                      const SizedBox(height: 12),
                      if (_searchedName?.isNotEmpty == true)
                        Text(_searchedName!,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                      if (_searchedUsername?.isNotEmpty == true)
                        Text('@$_searchedUsername',
                          style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13)),
                      if (_searchedEmail?.isNotEmpty == true)
                        Text(_searchedEmail!,
                          style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12)),
                      const SizedBox(height: 16),
                      if ((_searchedTotalRatings ?? 0) == 0)
                        const _Marquee(text: 'You are the first one to rate this user! ⭐')
                      else ...[
                        _starRow(_searchedAvgRating!, size: 30),
                        const SizedBox(height: 8),
                        Text(
                          _searchedAvgRating!.toStringAsFixed(2),
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: AppColors.cyan),
                        ),
                      ],
                      if (_searchedTotalRatings != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${t('based_on_label')} $_searchedTotalRatings ${_searchedTotalRatings == 1 ? t('rating_singular_label') : t('ratings_plural_label')}',
                            style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12)),
                        ),
                      if (_searchedDistribution != null && (_searchedTotalRatings ?? 0) > 0) ...[
                        const SizedBox(height: 16),
                        Divider(height: 1, color: AppThemeColors.divider(context)),
                        const SizedBox(height: 14),
                        Text(t('rating_breakdown_label'),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context))),
                        const SizedBox(height: 10),
                        _distributionBars(_searchedDistribution!, _searchedTotalRatings!),
                      ],
                    ]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ─── Tab: History ────────────────────────────────────────────────────────────

  Widget _buildHistoryTab() {
    final t = AppLocalizations.of(context).t;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        children: [
          _sectionCard(
            t('ratings_given_label').toUpperCase(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: ratingsGiven.isEmpty
                ? _emptyState(t('no_ratings_given_yet'), Icons.star_outline)
                : Column(
                    children: ratingsGiven.map((r) =>
                      _ratingCard(Map<String, dynamic>.from(r), isGiven: true)).toList(),
                  ),
            ),
          ),
          _sectionCard(
            t('ratings_received_label').toUpperCase(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: ratingsReceived.isEmpty
                ? _emptyState(t('no_ratings_received_yet'), Icons.star_border)
                : Column(
                    children: ratingsReceived.map((r) =>
                      _ratingCard(Map<String, dynamic>.from(r), isGiven: false)).toList(),
                  ),
            ),
          ),
          if (ratingActivities.isNotEmpty)
            _sectionCard(
              t('recent_activity_label').toUpperCase(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: ratingActivities.map((a) {
                    final isGiven = a['type'] == 'user_rated';
                    final color = isGiven ? Colors.blue : Colors.purple;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(isGiven ? Icons.star : Icons.star_border, color: color, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a['title'] ?? '',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.primaryText(context)),
                            maxLines: 1),
                          Text(a['description'] ?? '',
                            style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11),
                            maxLines: 1),
                        ])),
                        if (a['metadata']?['rating'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                            child: Text('${a['metadata']['rating']} ★',
                              style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                      ]),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          ClipPath(
            clipper: DeepTopWaveClipper(),
            child: Container(
              height: 180,
              color: AppThemeColors.waveSolid(context),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        t('ratings_title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ]),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else
                  _myRatingHero(),
                AppTabBar(
                  controller: _tabController,
                  tabs: [
                    AppTabItem(label: t('rate_tab_label'), icon: Icons.rate_review),
                    AppTabItem(label: t('search'), icon: Icons.search),
                    AppTabItem(label: t('history_label'), icon: Icons.history),
                  ],
                ),
                Expanded(
                  child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : error != null
                        ? errorStateWidget(context, error!, fetchRatings)
                        : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildRateTab(),
                          _buildSearchTab(),
                          _buildHistoryTab(),
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

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: AppThemeColors.divider(context)),
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: AppThemeColors.mutedText(context))),
        ]),
      ),
    );
  }
}

class _Marquee extends StatefulWidget {
  const _Marquee({required this.text});
  final String text;

  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _animation = Tween<double>(begin: 1.0, end: -1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) => FractionalTranslation(
            translation: Offset(_animation.value, 0),
            child: child,
          ),
          child: Text(
            widget.text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.cyan),
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}
