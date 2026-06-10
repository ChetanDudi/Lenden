import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../widgets/subscription_prompt.dart';

class RatingsPage extends StatefulWidget {
  const RatingsPage({super.key});

  @override
  State<RatingsPage> createState() => _RatingsPageState();
}

class _RatingsPageState extends State<RatingsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // My ratings data
  double? avgRating;
  List<dynamic> ratingsGiven = [];
  List<dynamic> ratingsReceived = [];
  bool loading = true;
  String? error;

  // Rate someone
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  double _selectedRating = 5;
  String? _submitError;
  bool _submitting = false;
  bool _showSuccess = false;

  // Search user rating
  final _searchController = TextEditingController();
  String? _searchError;
  double? _searchedAvgRating;
  String? _searchedName;
  String? _searchedUsername;
  String? _searchedEmail;
  int? _searchedTotalRatings;
  bool _searching = false;

  // Rating activities
  List<dynamic> ratingActivities = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    fetchRatings();
    fetchRatingActivities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> fetchRatings() async {
    setState(() { loading = true; error = null; });
    final res = await ApiClient.get('/api/ratings/me');
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() {
        avgRating = data['avgRating']?.toDouble();
        ratingsGiven = data['ratingsGiven'] ?? [];
        ratingsReceived = data['ratingsReceived'] ?? [];
        loading = false;
      });
    } else {
      setState(() { error = 'Failed to load ratings.'; loading = false; });
    }
  }

  Future<void> fetchRatingActivities() async {
    final res = await ApiClient.get('/api/activities?type=user_rated,user_rating_received&limit=10');
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      setState(() => ratingActivities = data['activities'] ?? []);
    }
  }

  Future<void> submitRating() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _submitting = true; _submitError = null; _showSuccess = false; });
    final res = await ApiClient.post('/api/ratings', body: {
      'usernameOrEmail': _usernameController.text.trim(),
      'rating': _selectedRating,
    });
    if (res.statusCode == 201) {
      setState(() { _showSuccess = true; _usernameController.clear(); _selectedRating = 5; });
      fetchRatings();
    } else {
      setState(() => _submitError = json.decode(res.body)['error'] ?? 'Failed to submit rating.');
    }
    setState(() => _submitting = false);
  }

  Future<void> _searchUserRating() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) {
      setState(() { _searchError = 'Enter a username or email.'; _searchedAvgRating = null; });
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    final lower = input.toLowerCase();
    final myEmail = (session.user?['email'] ?? '').toString().toLowerCase();
    final myUsername = (session.user?['username'] ?? '').toString().toLowerCase();
    if (lower == myEmail || (myUsername.isNotEmpty && lower == myUsername)) {
      setState(() {
        _searchError = "That's you! Your ratings are shown in the first tab above.";
        _searchedAvgRating = null;
      });
      return;
    }

    setState(() { _searching = true; _searchError = null; _searchedAvgRating = null; });
    try {
      final res = await ApiClient.get('/api/ratings/user-avg?usernameOrEmail=$input');
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          _searchedAvgRating = (data['avgRating'] ?? 0).toDouble();
          _searchedName = data['name'] ?? '';
          _searchedUsername = data['username'] ?? '';
          _searchedEmail = data['email'] ?? '';
          _searchedTotalRatings = data['totalRatings'];
        });
      } else {
        final err = json.decode(res.body);
        setState(() => _searchError = err['error'] ?? 'User not found.');
      }
    } catch (_) {
      setState(() => _searchError = 'Error searching user.');
    }
    setState(() => _searching = false);
  }

  // ─── UI helpers ─────────────────────────────────────────────────────────────

  Widget _starRow(double value, {double size = 24}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < value.floor()) {
          return Icon(Icons.star_rounded, color: Colors.amber, size: size);
        } else if (i < value) {
          return Icon(Icons.star_half_rounded, color: Colors.amber, size: size);
        }
        return Icon(Icons.star_outline_rounded, color: Colors.amber.withValues(alpha: 0.4), size: size);
      }),
    );
  }

  Widget _interactiveStars(double value, ValueChanged<double> onChange, {double size = 32}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => GestureDetector(
        onTap: () => onChange((i + 1).toDouble()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(
            i < value ? Icons.star_rounded : Icons.star_outline_rounded,
            color: i < value ? Colors.amber : Colors.grey[300],
            size: size,
          ),
        ),
      )),
    );
  }

  Widget _tricolorBorder({required Widget child, double radius = 20}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _ratingCard(Map<String, dynamic> r, {required bool isGiven}) {
    final rating = (r['rating'] ?? 0).toDouble();
    final name = isGiven
        ? (r['rateeName'] ?? r['ratee'] ?? 'User').toString()
        : (r['raterName'] ?? r['rater'] ?? 'User').toString();
    final prefix = isGiven ? 'To' : 'From';
    final starColor = rating >= 4 ? Colors.green : rating >= 3 ? Colors.orange : Colors.red;

    return _tricolorBorder(
      radius: 16,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: starColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
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
                  Text('$prefix: $name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  _starRow(rating, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myRatingHero() {
    final stars = avgRating ?? 0.0;
    final color = stars >= 4 ? const Color(0xFF2E7D32) : stars >= 3 ? Colors.orange : const Color(0xFFD32F2F);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.18), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 8),
            const Text('Your Rating', style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 12),
          Text(
            avgRating != null ? avgRating!.toStringAsFixed(2) : '—',
            style: TextStyle(fontSize: 52, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 8),
          _starRow(stars, size: 28),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statPill('Given', '${ratingsGiven.length}', Colors.blue),
              const SizedBox(width: 12),
              _statPill('Received', '${ratingsReceived.length}', Colors.purple),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            TextSpan(text: ' $label', style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 180,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
                    const Expanded(child: Text('Ratings', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))),
                    const SizedBox(width: 48),
                  ]),
                ),

                // Hero rating card
                if (!loading) _myRatingHero()
                else const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(color: Colors.white),
                ),

                // Tab bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicator: BoxDecoration(color: const Color(0xFF00B4D8), borderRadius: BorderRadius.circular(12)),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.grey[600],
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    tabs: const [
                      Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.rate_review, size: 15), SizedBox(width: 4), Text('Rate')])),
                      Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.search, size: 15), SizedBox(width: 4), Text('Search')])),
                      Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.history, size: 15), SizedBox(width: 4), Text('History')])),
                    ],
                  ),
                ),

                Expanded(
                  child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          // ── Tab 1: Rate someone ────────────────────────────
                          SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            child: Column(
                              children: [
                                _tricolorBorder(
                                  child: Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), shape: BoxShape.circle),
                                            child: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text('Rate Another User', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                        ]),
                                        const SizedBox(height: 16),
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
                                              const Text('Rating submitted successfully!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                                            ]),
                                          ),
                                        Form(
                                          key: _formKey,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              TextFormField(
                                                controller: _usernameController,
                                                decoration: InputDecoration(
                                                  labelText: 'Username or Email',
                                                  prefixIcon: const Icon(Icons.person_search_outlined),
                                                  filled: true,
                                                  fillColor: const Color(0xFFF5F7FA),
                                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                                  focusedBorder: OutlineInputBorder(
                                                    borderRadius: BorderRadius.circular(14),
                                                    borderSide: const BorderSide(color: Color(0xFF00B4D8), width: 1.5),
                                                  ),
                                                ),
                                                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                                              ),
                                              const SizedBox(height: 20),
                                              const Text('Your Rating', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
                                              const SizedBox(height: 10),
                                              Center(
                                                child: Column(
                                                  children: [
                                                    StatefulBuilder(
                                                      builder: (context, setStar) => _interactiveStars(
                                                        _selectedRating,
                                                        (val) => setState(() => _selectedRating = val),
                                                        size: 40,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      _selectedRating == 5 ? 'Excellent!' :
                                                      _selectedRating >= 4 ? 'Great!' :
                                                      _selectedRating >= 3 ? 'Good' :
                                                      _selectedRating >= 2 ? 'Fair' : 'Poor',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold, fontSize: 16,
                                                        color: _selectedRating >= 4 ? Colors.green : _selectedRating >= 3 ? Colors.orange : Colors.red,
                                                      ),
                                                    ),
                                                  ],
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
                                                    backgroundColor: const Color(0xFF00B4D8),
                                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                    elevation: 0,
                                                  ),
                                                  onPressed: _submitting ? null : submitRating,
                                                  child: _submitting
                                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                    : const Text('Submit Rating', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── Tab 2: Search user rating ──────────────────────
                          SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            child: Consumer<SessionProvider>(
                              builder: (context, session, _) {
                                if (!session.isSubscribed) {
                                  return _tricolorBorder(
                                    child: Container(
                                      padding: const EdgeInsets.all(22),
                                      decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(18)),
                                      child: Column(children: [
                                        const Icon(Icons.lock_rounded, size: 48, color: Color(0xFF00B4D8)),
                                        const SizedBox(height: 14),
                                        const Text('Premium Feature', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0096C7))),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Subscribe to search and view other users\' ratings.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey[700]),
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF00B4D8),
                                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                          icon: const Icon(Icons.workspace_premium, color: Colors.amber),
                                          label: const Text('Subscribe Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                          onPressed: () => showSubscriptionPrompt(context),
                                        ),
                                      ]),
                                    ),
                                  );
                                }
                                return Column(
                                  children: [
                                    _tricolorBorder(
                                      child: Container(
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                        child: Column(
                                          children: [
                                            Row(children: [
                                              Expanded(
                                                child: TextField(
                                                  controller: _searchController,
                                                  decoration: InputDecoration(
                                                    hintText: 'Enter username or email',
                                                    prefixIcon: const Icon(Icons.person_search),
                                                    filled: true,
                                                    fillColor: const Color(0xFFF5F7FA),
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                                  ),
                                                  onSubmitted: (_) => _searchUserRating(),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              GestureDetector(
                                                onTap: _searching ? null : _searchUserRating,
                                                child: Container(
                                                  width: 48, height: 48,
                                                  decoration: const BoxDecoration(color: Color(0xFF00B4D8), shape: BoxShape.circle),
                                                  child: _searching
                                                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                    : const Icon(Icons.search, color: Colors.white),
                                                ),
                                              ),
                                            ]),
                                            if (_searchError != null)
                                              Container(
                                                margin: const EdgeInsets.only(top: 12),
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
                                    if (_searchedAvgRating != null) ...[
                                      const SizedBox(height: 16),
                                      _tricolorBorder(
                                        child: Container(
                                          padding: const EdgeInsets.all(22),
                                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                                          child: Column(children: [
                                            CircleAvatar(
                                              radius: 32,
                                              backgroundColor: const Color(0xFF00B4D8).withValues(alpha: 0.12),
                                              child: Text(
                                                (_searchedName?.isNotEmpty == true ? _searchedName![0] : _searchedUsername?[0] ?? '?').toUpperCase(),
                                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF00B4D8)),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            if (_searchedName?.isNotEmpty == true)
                                              Text(_searchedName!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            if (_searchedUsername?.isNotEmpty == true)
                                              Text('@$_searchedUsername', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                            if (_searchedEmail?.isNotEmpty == true)
                                              Text(_searchedEmail!, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                            const SizedBox(height: 16),
                                            _starRow(_searchedAvgRating!, size: 30),
                                            const SizedBox(height: 8),
                                            Text(
                                              _searchedAvgRating!.toStringAsFixed(2),
                                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF0096C7)),
                                            ),
                                            if (_searchedTotalRatings != null)
                                              Text('Based on $_searchedTotalRatings rating${_searchedTotalRatings == 1 ? '' : 's'}',
                                                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                          ]),
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ),

                          // ── Tab 3: History ─────────────────────────────────
                          ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              // Given
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  const Icon(Icons.arrow_upward, color: Colors.blue, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('Ratings Given', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00B4D8))),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Text('${ratingsGiven.length}', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              if (ratingsGiven.isEmpty)
                                _emptyState('No ratings given yet', Icons.star_outline)
                              else
                                ...ratingsGiven.map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _ratingCard(Map<String, dynamic>.from(r), isGiven: true),
                                )),
                              const SizedBox(height: 20),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(children: [
                                  const Icon(Icons.arrow_downward, color: Colors.purple, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('Ratings Received', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF6A1B9A))),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                    child: Text('${ratingsReceived.length}', style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 10),
                              if (ratingsReceived.isEmpty)
                                _emptyState('No ratings received yet', Icons.star_border)
                              else
                                ...ratingsReceived.map((r) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _ratingCard(Map<String, dynamic>.from(r), isGiven: false),
                                )),
                              if (ratingActivities.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                const Row(children: [
                                  Icon(Icons.timeline, color: Colors.teal, size: 18),
                                  SizedBox(width: 6),
                                  Text('Recent Activity', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                                ]),
                                const SizedBox(height: 10),
                                ...ratingActivities.map((a) {
                                  final isGiven = a['type'] == 'user_rated';
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
                                    ),
                                    child: Row(children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(
                                          color: (isGiven ? Colors.blue : Colors.purple).withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(isGiven ? Icons.star : Icons.star_border, color: isGiven ? Colors.blue : Colors.purple, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(a['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1),
                                        Text(a['description'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 11), maxLines: 1),
                                      ])),
                                      if (a['metadata']?['rating'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                          child: Text('${a['metadata']['rating']} ★', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                        ),
                                    ]),
                                  );
                                }),
                              ],
                            ],
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

  Widget _emptyState(String msg, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(msg, style: TextStyle(color: Colors.grey[400])),
        ]),
      ),
    );
  }
}
