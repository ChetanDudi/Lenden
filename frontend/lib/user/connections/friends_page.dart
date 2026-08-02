import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../../api_config.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/secure_transactions/create_secure_transaction_page.dart';
import '../transaction/group_transactions/create_group_page.dart';
import '../../widgets/stylish_dialog.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/premium_gate.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({Key? key}) : super(key: key);

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  Timer? _friendsDebounceTimer;
  bool _loading = true;
  bool _searching = false;
  String? _searchError;
  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _incoming = [];
  List<Map<String, dynamic>> _outgoing = [];
  List<Map<String, dynamic>> _blocked = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _topRatedUsers = [];
  List<Map<String, dynamic>> _birthdayFriends = [];
  final Set<String> _wishedFriendIds = {};
  final Map<String, int> _giftedCoins = {};
  bool _suggestionsLoading = true;
  final Set<String> _pendingOutgoingIds = {};
  final Set<String> _selectedForGroup = {};
  String _friendsQuery = '';
  int _friendsVisibleCount = 10;
  String _blockedQuery = '';
  int _blockedVisibleCount = 10;
  List<Map<String, dynamic>> _friendBalances = [];
  bool _loadingBalances = true;

  // Friends tab filter/sort
  String? _filterGender;   // null = All, 'Male', 'Female', 'Other'
  String _sortFriends = 'name_az'; // name_az | name_za | friend_since | member_since | rating
  Map<String, int> _mutualCounts = {};
  Map<String, int> _interactionCounts = {};
  late TabController _tabController;

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchFriends();
    _fetchFriendBalances();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _friendsDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF0077B6), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFD32F2F), Color(0xFF00838F), Color(0xFFE65100),
      Color(0xFF1565C0), Color(0xFF558B2F),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String username) {
    final n = name.trim();
    if (n.isNotEmpty) {
      final parts = n.split(' ');
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return n[0].toUpperCase();
    }
    if (username.trim().isNotEmpty) return username[0].toUpperCase();
    return '?';
  }

  Future<void> _fetchFriends() async {
    setState(() => _loading = true);
    try {
      final params = StringBuffer('/api/friends');
      final qp = <String>[];
      if (_friendsQuery.isNotEmpty) qp.add('search=${Uri.encodeComponent(_friendsQuery)}');
      if (_filterGender != null) qp.add('gender=${Uri.encodeComponent(_filterGender!)}');
      if (_sortFriends.isNotEmpty) qp.add('sortBy=${Uri.encodeComponent(_sortFriends)}');
      if (qp.isNotEmpty) params.write('?${qp.join('&')}');

      // Run both API calls in parallel — cuts wait time in half
      final results = await Future.wait([
        ApiClient.get(params.toString()),
        ApiClient.get('/api/friends/requests'),
      ]).timeout(const Duration(seconds: 15));
      final res = results[0];
      final reqRes = results[1];
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        _blocked = List<Map<String, dynamic>>.from(data['blockedUsers'] ?? []);
        _friendsVisibleCount = 10;
        _blockedVisibleCount = 10;
        _interactionCounts = {};
      }
      if (reqRes.statusCode == 200) {
        final data = jsonDecode(reqRes.body);
        _incoming = List<Map<String, dynamic>>.from(data['incoming'] ?? []);
        _outgoing = List<Map<String, dynamic>>.from(data['outgoing'] ?? []);
        _pendingOutgoingIds.clear();
      }
      // Fire non-critical calls in parallel without blocking the UI
      _loadInteractionCounts();
      _loadMutualCounts();
      _loadSuggestions();
      _loadTopRated();
      _loadBirthdayFriends();
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchFriendBalances() async {
    setState(() => _loadingBalances = true);
    try {
      final res = await ApiClient.get('/api/quick-transactions/friend-balances');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _friendBalances = List<Map<String, dynamic>>.from(data['balances'] ?? []));
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingBalances = false);
    }
  }

  Future<void> _loadTopRated() async {
    try {
      final res = await ApiClient.get('/api/ratings/top?limit=10');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _topRatedUsers = List<Map<String, dynamic>>.from(data['topRated'] ?? []));
      }
    } catch (_) {}
  }

  Future<void> _loadSuggestions() async {
    setState(() => _suggestionsLoading = true);
    try {
      final res = await ApiClient.get('/api/friends/suggestions?limit=10');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = List<Map<String, dynamic>>.from(data['suggestions'] ?? data['users'] ?? []);
        final friendIds = _friends.map((f) => f['_id']?.toString()).toSet();
        final outgoingIds = _outgoing.map((r) {
          final to = r['to'];
          return (to is Map ? to['_id'] : to)?.toString();
        }).toSet();
        final blockedIds = _blocked.map((b) => b['_id']?.toString()).toSet();
        setState(() {
          _suggestions = raw.where((u) {
            final id = u['_id']?.toString();
            return id != null &&
                !friendIds.contains(id) &&
                !outgoingIds.contains(id) &&
                !blockedIds.contains(id);
          }).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _suggestionsLoading = false);
    }
  }

  Future<void> _loadBirthdayFriends() async {
    try {
      final res = await ApiClient.get('/api/friends/birthdays?days=7');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['birthdays'] ?? []);
        final alreadyWished = list
            .where((f) => f['hasWished'] == true)
            .map((f) => f['_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        final gifted = <String, int>{};
        for (final f in list) {
          if ((f['giftedAmount'] as num? ?? 0) > 0) {
            gifted[f['_id']?.toString() ?? ''] = (f['giftedAmount'] as num).toInt();
          }
        }
        setState(() {
          _birthdayFriends = list;
          _wishedFriendIds.addAll(alreadyWished);
          _giftedCoins.addAll(gifted);
        });
      }
    } catch (_) {}
  }

  void _showBirthdayWishDialog(Map<String, dynamic> friend) {
    final name = (friend['name'] ?? friend['username'] ?? 'your friend').toString();
    final friendId = friend['_id']?.toString() ?? '';

    final templates = [
      'Happy Birthday $name! Wishing you a wonderful day filled with joy and happiness!',
      'Many happy returns of the day, $name! May this year bring you health, wealth, and success!',
      'Wishing you a very Happy Birthday, $name! Hope your day is as amazing as you are!',
      'Happy Birthday $name! Sending you warmest wishes and lots of love on your special day!',
    ];
    final controller = TextEditingController(text: templates[0]);
    int selectedTemplate = 0;
    int selectedGift = 0; // 0 = no gift
    const giftAmounts = [5, 10, 25, 50];
    bool _sending = false;

    // Refresh coins in background so dialog always shows current balance
    Provider.of<SessionProvider>(context, listen: false).loadFreebieCounts();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final session = Provider.of<SessionProvider>(ctx, listen: false);
          final myCoins = session.lenDenCoins ??
              (session.user?['lenDenCoins'] as num?)?.toInt() ?? 0;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFF8C00), Color(0xFFFF6B6B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(ctx),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Center(
                        child: Column(children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.cake_rounded, size: 36, color: Colors.amber),
                          ),
                          const SizedBox(height: 12),
                          Text("Happy Birthday, $name!",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(ctx))),
                          const SizedBox(height: 4),
                          Text("Today is their special day",
                            style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx))),
                        ]),
                      ),
                      const SizedBox(height: 20),

                      // Quick templates
                      Text('Quick message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppThemeColors.secondaryText(ctx))),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(templates.length, (i) {
                            final labels = ['Cheerful', 'Inspiring', 'Warm', 'Classic'];
                            final selected = selectedTemplate == i;
                            return GestureDetector(
                              onTap: () => setS(() {
                                selectedTemplate = i;
                                controller.text = templates[i];
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: selected ? Colors.amber : Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: selected ? Colors.amber : Colors.amber.withValues(alpha: 0.4)),
                                ),
                                child: Text(labels[i],
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                      color: selected ? Colors.white : const Color(0xFF7B4F00))),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Message text field
                      Container(
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(ctx,
                              light: const Color(0xFFFFFBF0), dark: const Color(0xFF2A2416)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                        ),
                        child: TextField(
                          controller: controller,
                          maxLines: 3,
                          onChanged: (_) => setS(() => selectedTemplate = -1),
                          style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(ctx)),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(12),
                            hintText: 'Write your wish...',
                            hintStyle: TextStyle(color: AppThemeColors.mutedText(ctx)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Gift coins section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(ctx,
                              light: const Color(0xFFFFF8E1), dark: const Color(0xFF252010)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFFCC00).withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.redeem_rounded, size: 16, color: Color(0xFFFF8C00)),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text('Send Coin Gift (optional)',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                      color: Color(0xFF7B4F00)),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Text('· $myCoins coins',
                                style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx))),
                            ]),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  // "None" option
                                  GestureDetector(
                                    onTap: () => setS(() => selectedGift = 0),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: selectedGift == 0
                                            ? AppThemeColors.secondaryText(ctx).withValues(alpha: 0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: selectedGift == 0
                                                ? AppThemeColors.secondaryText(ctx)
                                                : AppThemeColors.divider(ctx)),
                                      ),
                                      child: Text('None',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                            color: AppThemeColors.secondaryText(ctx))),
                                    ),
                                  ),
                                  ...giftAmounts.map((amt) {
                                    final sel = selectedGift == amt;
                                    final canAfford = myCoins >= amt;
                                    return GestureDetector(
                                      onTap: canAfford ? () => setS(() => selectedGift = amt) : null,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: sel ? const Color(0xFFFFB300) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                              color: sel ? const Color(0xFFFFB300)
                                                  : canAfford ? Colors.amber.withValues(alpha: 0.5)
                                                  : AppThemeColors.divider(ctx)),
                                        ),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.monetization_on_rounded, size: 13,
                                            color: sel ? Colors.white
                                                : canAfford ? Colors.amber
                                                : AppThemeColors.mutedText(ctx)),
                                          const SizedBox(width: 3),
                                          Text('$amt',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                                color: sel ? Colors.white
                                                    : canAfford ? const Color(0xFF7B4F00)
                                                    : AppThemeColors.mutedText(ctx))),
                                        ]),
                                      ),
                                    );
                                  }),
                                  // Surprise button
                                  GestureDetector(
                                    onTap: () {
                                      final affordable = giftAmounts.where((a) => myCoins >= a).toList();
                                      if (affordable.isEmpty) return;
                                      final pick = affordable[Random().nextInt(affordable.length)];
                                      setS(() => selectedGift = pick);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      margin: const EdgeInsets.only(left: 4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.5)),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Text('🎲', style: TextStyle(fontSize: 13)),
                                        const SizedBox(width: 3),
                                        Text('Surprise',
                                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                              color: Colors.deepPurple.shade400)),
                                      ]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (selectedGift > 0) ...[
                              const SizedBox(height: 8),
                              Text('$selectedGift coins will be deducted from your balance',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF997000))),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Action buttons
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppThemeColors.divider(ctx)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(t('cancel'),
                                style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _sending ? null : () async {
                              setS(() => _sending = true);
                              final wishRes = await ApiClient.post(
                                '/api/friends/$friendId/wish',
                                body: {'message': controller.text.trim()},
                              );
                              bool giftOk = true;
                              if (wishRes.statusCode == 201 && selectedGift > 0) {
                                final giftRes = await ApiClient.post(
                                  '/api/friends/$friendId/gift',
                                  body: {'coins': selectedGift},
                                );
                                giftOk = giftRes.statusCode == 201;
                                if (giftOk) {
                                  final giftData = jsonDecode(giftRes.body);
                                  final remaining = (giftData['remainingCoins'] as num?)?.toInt();
                                  if (remaining != null && ctx.mounted) {
                                    Provider.of<SessionProvider>(ctx, listen: false).updateUserCoins(remaining);
                                  }
                                }
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (wishRes.statusCode == 201) {
                                if (mounted) setState(() {
                                  _wishedFriendIds.add(friendId);
                                  if (selectedGift > 0 && giftOk) _giftedCoins[friendId] = selectedGift;
                                });
                                final msg = selectedGift > 0 && giftOk
                                    ? 'Wish sent + $selectedGift coins gifted!'
                                    : 'Birthday wish sent!';
                                showSnack(context, msg);
                              } else {
                                setS(() => _sending = false);
                                showSnack(context, 'Failed to send wish.', isError: true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _sending
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(
                                    selectedGift > 0 ? 'Send Wish + Gift 🎁' : 'Send Wish',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) => controller.dispose());
  }

  Future<void> _loadInteractionCounts() async {
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final myEmail = session.user?['email'];
      if (myEmail == null || _friends.isEmpty) return;
      final emails = _friends
          .map((f) => (f['email'] ?? '').toString().toLowerCase().trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (emails.isEmpty) return;
      final res = await ApiClient.post('/api/counterparties/stats-batch', body: {
        'email': myEmail,
        'counterparties': emails,
      });
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final counts = Map<String, dynamic>.from(data['counts'] ?? {});
        setState(() {
          _interactionCounts = counts.map(
            (k, v) => MapEntry(k.toString().toLowerCase().trim(),
                (v as num?)?.toInt() ?? 0),
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    final session = Provider.of<SessionProvider>(context, listen: false);
    final lowerQuery = query.toLowerCase();
    final myEmail = (session.user?['email'] ?? '').toString().toLowerCase();
    final myUsername = (session.user?['username'] ?? '').toString().toLowerCase();
    if (lowerQuery == myEmail || (myUsername.isNotEmpty && lowerQuery == myUsername)) {
      setState(() {
        _searchResults = [];
        _searchError = t('cannot_add_self_friend');
      });
      return;
    }

    setState(() { _searching = true; _searchError = null; });
    try {
      final res = await ApiClient.get('/api/friends/search?q=${Uri.encodeComponent(query)}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final myId = session.user?['_id']?.toString() ?? '';
        final results = List<Map<String, dynamic>>.from(data['users'] ?? [])
            .where((u) => u['_id']?.toString() != myId)
            .toList();
        final lowerQuery = query.toLowerCase();
        final matchingFriends = _friends.where((f) {
          final email = (f['email'] ?? '').toString().toLowerCase();
          final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
          return email.contains(lowerQuery) || name.contains(lowerQuery);
        }).toList();
        final matchingBlocked = _blocked.where((u) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          final name = (u['name'] ?? u['username'] ?? '').toString().toLowerCase();
          return email.contains(lowerQuery) || name.contains(lowerQuery);
        }).toList();
        setState(() {
          _searchResults = results;
          if (results.isEmpty && matchingFriends.isNotEmpty) {
            _searchError = t('user_already_in_friends_list');
          } else if (results.isEmpty && matchingBlocked.isNotEmpty) {
            _searchError = t('user_blocked_unblock_to_add');
          } else {
            _searchError = results.isEmpty ? '${t('no_users_found_for')} "$query".' : null;
          }
        });
      } else {
        setState(() { _searchResults = []; _searchError = t('failed_to_search_try_again'); });
      }
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _addFriend(Map<String, dynamic> user) async {
    final uid = user['_id']?.toString() ?? '';
    setState(() => _pendingOutgoingIds.add(uid));
    final res = await ApiClient.post('/api/friends/request', body: {'userId': uid});
    if (res.statusCode == 201) {
      await _fetchFriends();
      if (!mounted) return;
      _showSuccessDialog(t('request_sent_title'), t('friend_request_sent_success'), Icons.check_circle, Colors.green);
    } else if (res.statusCode == 200) {
      // Already pending from a prior send — refresh to sync state
      await _fetchFriends();
    } else {
      setState(() => _pendingOutgoingIds.remove(uid));
      showSnack(context, t('failed_to_send_request'), isError: true);
    }
  }

  void _showSuccessDialog(String title, String msg, IconData icon, Color color) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _tricolorBorder(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 52),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
              const SizedBox(height: 8),
              Text(msg, textAlign: TextAlign.center, style: TextStyle(color: AppThemeColors.secondaryText(context))),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: color),
                onPressed: () => Navigator.pop(context),
                child: Text(t('ok'), style: const TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _acceptRequest(String requestId) async {
    final res = await ApiClient.post('/api/friends/requests/$requestId/accept');
    if (res.statusCode == 200) {
      await _fetchFriends();
      showSnack(context, t('friend_request_accepted'));
    }
  }

  Future<void> _declineRequest(String requestId) async {
    final res = await ApiClient.post('/api/friends/requests/$requestId/decline');
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _cancelRequest(String requestId) async {
    final res = await ApiClient.post('/api/friends/requests/$requestId/cancel');
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _removeFriend(String friendId) async {
    final ok = await _confirmAction(title: t('confirm_remove_friend_title'), message: t('confirm_remove_friend_message'), icon: Icons.person_remove, color: Colors.red);
    if (!ok) return;
    final res = await ApiClient.delete('/api/friends/$friendId');
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _blockUser(String userId) async {
    final ok = await _confirmAction(title: t('confirm_block_user_title'), message: t('confirm_block_user_message'), icon: Icons.block, color: Colors.orange);
    if (!ok) return;
    final res = await ApiClient.post('/api/friends/block', body: {'userId': userId});
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _unblockUser(String userId) async {
    final ok = await _confirmAction(title: t('confirm_unblock_user_title'), message: t('confirm_unblock_user_message'), icon: Icons.lock_open, color: Colors.teal);
    if (!ok) return;
    final res = await ApiClient.post('/api/friends/unblock', body: {'userId': userId});
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<bool> _confirmAction({required String title, required String message, required IconData icon, required Color color}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _tricolorBorder(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(height: 14),
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: AppThemeColors.secondaryText(context))),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(t('cancel')))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t('confirm'), style: const TextStyle(color: Colors.white)),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    return result == true;
  }

  void _openQuickTransaction(String email) {
    if (_isBlockedEmail(email)) { showBlockedUserDialog(context); return; }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => QuickTransactionsPage(prefillCounterpartyEmail: email, openCreateOnLoad: true),
    ));
  }

  Future<void> _openUserTransaction(String email) async {
    if (_isBlockedEmail(email)) { showBlockedUserDialog(context); return; }
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('secure_transactions')) {
      int? dailyRemaining;
      await Future.wait([
        session.loadFreebieCounts(),
        ApiClient.get('/api/limits/daily').then((res) {
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            dailyRemaining = data['limits']?['userTransactions']?['remaining'];
          }
        }),
      ]);
      if (!mounted) return;
      if (dailyRemaining != null && dailyRemaining! <= 0) {
        showDailyLimitDialog(context,
            message:
                'You\'ve reached today\'s limit of 2 secure transactions. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
        return;
      }
      final freeRemaining = session.freeUserTransactionsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: 'secure transaction', coinCost: session.secureTransactionCoinCost, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => TransactionPage(prefillCounterpartyEmail: email, useCoins: true),
        ));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TransactionPage(prefillCounterpartyEmail: email),
    ));
  }

  Future<void> _openGroupWithSelected() async {
    if (_selectedForGroup.isEmpty) return;
    if (_selectedForGroup.any(_isBlockedEmail)) { showBlockedUserDialog(context); return; }
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('group_creation')) {
      int? dailyRemaining;
      await Future.wait([
        session.loadFreebieCounts(),
        ApiClient.get('/api/limits/daily').then((res) {
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            dailyRemaining = data['limits']?['groups']?['remaining'];
          }
        }),
      ]);
      if (!mounted) return;
      if (dailyRemaining != null && dailyRemaining! <= 0) {
        showDailyLimitDialog(context,
            message:
                'You\'ve reached today\'s limit of 1 group creation. Free attempts are also paused until tomorrow.\n\nSubscribe for unlimited access.');
        return;
      }
      final freeRemaining = session.freeGroupsRemaining ?? 0;
      if (freeRemaining <= 0) {
        final coins = session.lenDenCoins ?? 0;
        final useCoins = await showFreeAttemptsExhaustedDialog(context,
            featureName: 'group creation', coinCost: session.groupCreationCoinCost, currentCoins: coins);
        if (!mounted) return;
        if (useCoins != true) return;
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreateGroupPage(
              prefillMemberEmails: _selectedForGroup.toList(), useCoins: true),
        ));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CreateGroupPage(prefillMemberEmails: _selectedForGroup.toList()),
    ));
  }

  bool _isBlockedEmail(String email) {
    final target = email.toLowerCase().trim();
    return _blocked.any((u) => (u['email'] ?? '').toString().toLowerCase().trim() == target);
  }

  Future<void> _loadMutualCounts() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final now = DateTime.now();
    final lastFetched = session.mutualCountsLastFetched;
    if (session.mutualFriendCounts != null && lastFetched != null &&
        now.difference(lastFetched).inMinutes < 10) {
      setState(() => _mutualCounts = session.mutualFriendCounts!);
      return;
    }
    final ids = _friends.map((f) => f['_id']?.toString()).whereType<String>().toList();
    if (ids.isEmpty) return;
    try {
      final res = await ApiClient.post('/api/friends/mutual-counts', body: {'userIds': ids});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final counts = Map<String, dynamic>.from(data['counts'] ?? {});
        if (mounted) {
          setState(() {
            _mutualCounts = counts.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
          });
          session.setMutualFriendCounts(_mutualCounts);
        }
      }
    } catch (_) {}
  }

  // ─── UI Widgets ─────────────────────────────────────────────────────────────

  void _showMutualFriendsSheet(String userId, String displayName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MutualFriendsSheet(
        userId: userId,
        displayName: displayName,
        avatarColor: _avatarColor(displayName),
        initials: _initials(displayName, ''),
      ),
    );
  }

  Widget _tricolorBorder({required Widget child, double radius = 20, bool glow = false}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4)),
          if (glow) BoxShadow(color: Colors.amber.withValues(alpha: 0.55), blurRadius: 22, spreadRadius: 2),
        ],
      ),
      child: child,
    );
  }

  Widget _profileAvatar(String userId, String displayName, String username, {double radius = 24}) {
    final color = _avatarColor(displayName.isNotEmpty ? displayName : username);
    final size = radius * 2;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                _initials(displayName, username),
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.65),
              ),
            ),
            if (userId.isNotEmpty)
              Image.network(
                '${ApiConfig.baseUrl}/api/users/$userId/profile-image',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend, int index) {
    final email = (friend['email'] ?? '').toString();
    final name = (friend['name'] ?? '').toString();
    final username = (friend['username'] ?? '').toString();
    final friendId = (friend['_id'] ?? '').toString();
    final isBlocked = _blocked.any((u) => u['_id'] == friendId);
    final isBlockedByThem = friend['blockedByThem'] == true;
    final selected = _selectedForGroup.contains(email);
    final interactions = _interactionCounts[email.toLowerCase().trim()] ?? 0;
    final mutualCount = _mutualCounts[friendId] ?? 0;
    final displayName = name.isNotEmpty ? name : username;
    final color = _avatarColor(displayName);
    final avgRating = friend['avgRating'] as num?;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final canSeeRatings = session.hasFeature('view_rankings') && !session.subscriptionAdminDeactivated;
    final isBirthdayToday = _birthdayFriends.any(
        (b) => b['_id']?.toString() == friendId && (b['daysUntil'] ?? 99) == 0);

    return _tricolorBorder(
      glow: isBirthdayToday,
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeColors.tinted(context, light: const Color(0xFFFAF9F6), dark: const Color(0xFF1E1E1E)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            // Card header with avatar and name
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _profileAvatar(friendId, displayName, username, radius: 26),
                      if (isBirthdayToday)
                        Positioned(
                          right: -4, top: -4,
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Center(child: Text('🎂', style: TextStyle(fontSize: 10))),
                          ),
                        ),
                      if (selected)
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            width: 18, height: 18,
                            decoration: BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                            child: const Icon(Icons.check, color: Colors.white, size: 11),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        if (username.isNotEmpty && username != name)
                          Text('@$username', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)), maxLines: 1),
                        Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // Group checkbox
                  GestureDetector(
                    onTap: () {
                      if (!selected && isBlockedByThem) { showBlockedUserDialog(context, message: t('blocked_you_cannot_add')); return; }
                      if (!selected && isBlocked) { showBlockedUserDialog(context); return; }
                      setState(() {
                        if (selected) _selectedForGroup.remove(email);
                        else _selectedForGroup.add(email);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.cyan.withValues(alpha: 0.12) : AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? AppColors.cyan : AppThemeColors.divider(context)),
                      ),
                      child: Icon(
                        selected ? Icons.group_add : Icons.group_add_outlined,
                        size: 18,
                        color: selected ? AppColors.cyan : AppThemeColors.mutedText(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chips row — horizontal scroll, single line
            Builder(builder: (_) {
                final bInfo = _birthdayFriends.where((b) => b['_id']?.toString() == friendId).firstOrNull;
                if (bInfo != null) {
                  final isToday = bInfo['daysUntil'] == 0;
                  final daysUntil = bInfo['daysUntil'] as int? ?? 0;
                  final hasWished = _wishedFriendIds.contains(friendId);
                  final giftedAmt = _giftedCoins[friendId] ?? 0;
                  final hasGifted = giftedAmt > 0;
                  // Already wished or gifted — show green badge
                  if (isToday && (hasWished || hasGifted)) {
                    return Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.green.shade500,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_outline, size: 14, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(
                          hasGifted ? 'Wished + $giftedAmt coins gifted' : 'You wished ✓',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ]),
                    );
                  }
                  return GestureDetector(
                    onTap: isToday ? () => _showBirthdayWishDialog(bInfo) : null,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isToday
                              ? [const Color(0xFFFFE082), const Color(0xFFFFB300)]
                              : [const Color(0xFFFFF9E6), const Color(0xFFFFF3CD)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.cake_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text(
                          isToday ? 'Birthday today! Wish + Gift 🎁' : 'Birthday in $daysUntil day${daysUntil == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: isToday ? const Color(0xFF7B4F00) : const Color(0xFF997A00),
                          ),
                        ),
                      ]),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            if (mutualCount > 0 || interactions > 0 || isBlocked || isBlockedByThem || (canSeeRatings && avgRating != null && avgRating > 0))
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (canSeeRatings && avgRating != null && avgRating > 0) ...[
                        _ratingChip(avgRating),
                        const SizedBox(width: 6),
                      ],
                      if (mutualCount > 0) ...[
                        GestureDetector(
                          onTap: () => _showMutualFriendsSheet(friendId, displayName),
                          child: _chip('$mutualCount ${t('mutual_suffix')} 👥', Colors.teal.shade600, Colors.teal.withValues(alpha: 0.1)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (interactions > 0) ...[_chip('$interactions ${t('transactions_suffix')}', Colors.blue.shade600, Colors.blue.withValues(alpha: 0.1)), const SizedBox(width: 6)],
                      if (isBlockedByThem) ...[_chip(t('blocked_you_label'), Colors.red.shade700, Colors.red.withValues(alpha: 0.1)), const SizedBox(width: 6)],
                      if (isBlocked) _chip(t('you_blocked_label'), Colors.orange.shade700, Colors.orange.withValues(alpha: 0.1)),
                    ],
                  ),
                ),
              ),

            // Action buttons — horizontal scroll prevents overflow on small screens
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _actionBtn(Icons.flash_on, t('quick_label'), const Color(0xFF0077B6), () {
                      if (isBlockedByThem || isBlocked) { showBlockedUserDialog(context); return; }
                      _openQuickTransaction(email);
                    }),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.receipt_long, t('secure_label'), const Color(0xFF2E7D32), () {
                      if (isBlockedByThem || isBlocked) { showBlockedUserDialog(context); return; }
                      _openUserTransaction(email);
                    }),
                    const SizedBox(width: 12),
                    _iconActionBtn(isBlocked ? Icons.lock_open : Icons.block, isBlocked ? Colors.teal : Colors.orange,
                      () => isBlocked ? _unblockUser(friendId) : _blockUser(friendId),
                      tooltip: isBlocked ? t('unblock_label') : t('block_label'),
                    ),
                    const SizedBox(width: 6),
                    _iconActionBtn(Icons.person_remove, Colors.red,
                      () => _removeFriend(friendId),
                      tooltip: t('remove_friend_tooltip'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color textColor, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor)),
    );
  }

  Widget _ratingChip(num avg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
        const SizedBox(width: 3),
        Text(avg.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      ),
    );
  }

  Widget _iconActionBtn(IconData icon, Color color, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String? value, String? current, void Function(String?) onTap, {IconData? icon}) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(selected ? null : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.cyan : AppThemeColors.divider(context)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: selected ? Colors.white : AppThemeColors.secondaryText(context)),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppThemeColors.secondaryText(context))),
        ]),
      ),
    );
  }

  Widget _sortChipF(String label, String value) {
    final selected = _sortFriends == value;
    return GestureDetector(
      onTap: () {
        if (_sortFriends != value) {
          setState(() { _sortFriends = value; _friendsVisibleCount = 10; });
          _fetchFriends();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.deepPurple : AppThemeColors.divider(context)),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppThemeColors.secondaryText(context))),
      ),
    );
  }

  Widget _sectionHeader(String title, int count, {Color? badgeColor}) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
            color: AppThemeColors.tinted(context, light: const Color(0xFF023E8A), dark: const Color(0xFF64B5F6)))),
        const SizedBox(width: 8),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: (badgeColor ?? AppColors.cyan).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor ?? AppColors.cyan)),
          ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> person, String label, Widget trailing, int index) {
    final name = (person['name'] ?? person['username'] ?? 'Unknown').toString();
    final email = (person['email'] ?? '').toString();
    final username = (person['username'] ?? '').toString();
    final personId = (person['_id'] ?? '').toString();
    final avgRating = person['avgRating'] as num?;
    final session = Provider.of<SessionProvider>(context, listen: false);
    final canSeeRatings = session.hasFeature('view_rankings') && !session.subscriptionAdminDeactivated;

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            _profileAvatar(personId, name.isNotEmpty ? name : username, username, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (canSeeRatings && avgRating != null && avgRating > 0) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> u, int index) {
    final name = (u['name'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final uid = u['_id']?.toString() ?? '';
    final isFriend = _friends.any((f) => f['_id']?.toString() == uid);
    final isOutgoing = _pendingOutgoingIds.contains(uid) ||
        _outgoing.any((r) {
          final to = r['to'];
          return (to is Map ? to['_id'] : to)?.toString() == uid;
        });
    final isIncoming = _incoming.any((r) {
      final from = r['from'];
      return (from is Map ? from['_id'] : from)?.toString() == uid;
    });

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            _profileAvatar(uid, name.isNotEmpty ? name : username, username, radius: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isNotEmpty ? name : username, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (username.isNotEmpty && username != name)
                    Text('@$username', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                  Text(email, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isFriend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(t('friend_label'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
              )
            else if (isIncoming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(t('wants_to_connect'), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12)),
              )
            else if (isOutgoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(t('pending_label'), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12)),
              )
            else
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  minimumSize: Size.zero,
                ),
                onPressed: () => _addFriend(u),
                child: Text(t('add_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionCard(Map<String, dynamic> u) {
    final name = (u['name'] ?? '').toString();
    final username = (u['username'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final mutualCount = (u['mutualFriends'] ?? u['mutual'] ?? 0) as int;
    final reason = (u['reason'] ?? '').toString();
    final displayName = name.isNotEmpty ? name : username;
    final suid = u['_id']?.toString() ?? '';
    final isOutgoing = _pendingOutgoingIds.contains(suid) ||
        _outgoing.any((r) {
          final to = r['to'];
          return (to is Map ? to['_id'] : to)?.toString() == suid;
        });

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            _profileAvatar(suid, displayName, username, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (username.isNotEmpty && username != name)
                    Text('@$username', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  if (mutualCount > 0)
                    GestureDetector(
                      onTap: () => _showMutualFriendsSheet(suid, displayName),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.people, size: 12, color: Colors.teal[600]),
                        const SizedBox(width: 3),
                        Text('$mutualCount ${mutualCount == 1 ? t('mutual_friend_singular') : t('mutual_friends_plural')}',
                          style: TextStyle(fontSize: 11, color: Colors.teal[600], fontWeight: FontWeight.w500)),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 12, color: Colors.teal[400]),
                      ]),
                    )
                  else if (reason.isNotEmpty)
                    Text(reason, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isOutgoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Text(t('pending_label'), style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 0,
                  minimumSize: Size.zero,
                ),
                icon: const Icon(Icons.person_add, color: Colors.white, size: 15),
                label: Text(t('add_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _addFriend(u),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _incoming.length;

    return Scaffold(
      backgroundColor: AppThemeColors.tinted(context, light: const Color(0xFFE0F7FA), dark: const Color(0xFF121212)),
      body: Stack(
        children: [
          // Wave header
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: AppThemeColors.waveGradient(context),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // App bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(t('friends'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
                            Text('${_friends.length} ${_friends.length == 1 ? t('friend_singular') : t('friends_plural')}',
                              style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                          ],
                        ),
                      ),
                      if (_selectedForGroup.isNotEmpty)
                        GestureDetector(
                          onTap: _openGroupWithSelected,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white54),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.group_add, color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text('${t('group_label')} (${_selectedForGroup.length})', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ]),
                          ),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            decoration: InputDecoration(
                              hintText: t('search_friends_placeholder'),
                              hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                              prefixIcon: Icon(Icons.search, color: AppThemeColors.mutedText(context)),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (_) { if (_searchError != null) setState(() => _searchError = null); },
                            onSubmitted: (_) => _searchUsers(),
                          ),
                        ),
                        if (_searching)
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                        else
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: AppColors.cyan),
                            onPressed: _searchUsers,
                          ),
                      ],
                    ),
                  ),
                ),

                // Tab bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicator: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: AppThemeColors.secondaryText(context),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.people, size: 15),
                          const SizedBox(width: 4),
                          Text('${t('friends')}${_friends.isNotEmpty ? ' (${_friends.length})' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mail, size: 15),
                          const SizedBox(width: 4),
                          Text('${t('requests_tab_label')}${pendingCount > 0 ? ' ($pendingCount)' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.block, size: 15),
                          const SizedBox(width: 4),
                          Text('${t('blocked_tab_label')}${_blocked.isNotEmpty ? ' (${_blocked.length})' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.person_search, size: 15),
                          const SizedBox(width: 4),
                          Text('${t('discover_tab_label')}${_suggestions.isNotEmpty ? ' (${_suggestions.length})' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.account_balance_wallet_rounded, size: 15),
                          const SizedBox(width: 4),
                          Text('${t('friend_balances_tab_label')}${_friendBalances.isNotEmpty ? ' (${_friendBalances.length})' : ''}'),
                        ]),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _fetchFriends,
                        color: AppColors.cyan,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // ── Tab 1: Friends ──────────────────────────────
                            ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                // Search results
                                if (_searchError != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.info_outline, color: Colors.red, size: 18),
                                      const SizedBox(width: 8),
                                      Flexible(child: Text(_searchError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
                                    ]),
                                  ),
                                // ── Birthday banner ─────────────────────────
                                if (_birthdayFriends.isNotEmpty) ...[
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFFF3CD), Color(0xFFFFE082)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                                          child: Row(children: [
                                            const Icon(Icons.cake_rounded, color: Colors.amber, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Birthdays this week',
                                              style: const TextStyle(
                                                fontSize: 14, fontWeight: FontWeight.bold,
                                                color: Color(0xFF7B5800),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.amber,
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text('${_birthdayFriends.length}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                            ),
                                          ]),
                                        ),
                                        ..._birthdayFriends.map((b) {
                                          final bName = (b['name'] ?? b['username'] ?? 'Friend').toString();
                                          final daysUntil = b['daysUntil'] as int? ?? 0;
                                          final isToday = daysUntil == 0;
                                          final bdayDate = DateTime.tryParse(b['birthday']?.toString() ?? '');
                                          final age = bdayDate != null ? DateTime.now().year - bdayDate.year : 0;
                                          return Padding(
                                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                                            child: Row(children: [
                                              _profileAvatar(
                                                b['_id']?.toString() ?? '',
                                                bName,
                                                b['username']?.toString() ?? '',
                                                radius: 18,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text(bName,
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF4A3500))),
                                                  Text(
                                                    isToday
                                                        ? (age > 0 ? 'Turning $age today! 🎉' : 'Birthday today!')
                                                        : 'Birthday in $daysUntil day${daysUntil == 1 ? '' : 's'}${age > 0 ? ' · Turning $age' : ''}',
                                                    style: TextStyle(fontSize: 11,
                                                      color: isToday ? Colors.deepOrange : const Color(0xFF7B5800),
                                                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ]),
                                              ),
                                              if (isToday) Builder(builder: (_) {
                                                final bid = b['_id']?.toString() ?? '';
                                                final wished = _wishedFriendIds.contains(bid);
                                                final gifted = _giftedCoins[bid] ?? 0;
                                                if (wished || gifted > 0) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade500,
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                      const Icon(Icons.check, size: 12, color: Colors.white),
                                                      const SizedBox(width: 3),
                                                      Text(
                                                        gifted > 0 ? '+$gifted coins' : 'Wished',
                                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                                                      ),
                                                    ]),
                                                  );
                                                }
                                                return GestureDetector(
                                                  onTap: () => _showBirthdayWishDialog(b),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                    decoration: BoxDecoration(
                                                      gradient: const LinearGradient(
                                                        colors: [Color(0xFFFFB300), Color(0xFFFF8C00)],
                                                      ),
                                                      borderRadius: BorderRadius.circular(20),
                                                    ),
                                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                                      Icon(Icons.cake_rounded, size: 13, color: Colors.white),
                                                      SizedBox(width: 4),
                                                      Text('Wish + Gift 🎁', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                                                    ]),
                                                  ),
                                                );
                                              }),
                                            ]),
                                          );
                                        }),
                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  ),
                                ],
                                if (_searchResults.isNotEmpty) ...[
                                  _sectionHeader(t('search_results_label'), _searchResults.length, badgeColor: Colors.purple),
                                  const SizedBox(height: 10),
                                  ..._searchResults.asMap().entries.map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildSearchResultCard(e.value, e.key),
                                  )),
                                  const Divider(height: 24),
                                ],
                                // ── Sent Requests (outgoing) ────────────────
                                if (_outgoing.isNotEmpty) ...[
                                  _sectionHeader(t('sent_requests_label'), _outgoing.length, badgeColor: Colors.orange),
                                  const SizedBox(height: 8),
                                  ..._outgoing.map((r) {
                                    final to = r['to'] is Map ? r['to'] as Map<String, dynamic> : <String, dynamic>{};
                                    final name = (to['name'] ?? to['username'] ?? 'Unknown').toString();
                                    final email = (to['email'] ?? '').toString();
                                    final username = (to['username'] ?? '').toString();
                                    final toId = (to['_id'] ?? '').toString();
                                    final toRating = to['avgRating'] as num?;
                                    final outSession = Provider.of<SessionProvider>(context, listen: false);
                                    final outCanSeeRatings = outSession.isSubscribed && !outSession.subscriptionAdminDeactivated;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                                        ),
                                        child: Row(children: [
                                          _profileAvatar(toId, name, username, radius: 20),
                                          const SizedBox(width: 10),
                                          Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppThemeColors.primaryText(context)),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                              Text(email, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                              if (outCanSeeRatings && toRating != null && toRating > 0) ...[
                                                const SizedBox(height: 3),
                                                Row(mainAxisSize: MainAxisSize.min, children: [
                                                  const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                                                  const SizedBox(width: 2),
                                                  Text(toRating.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                                                ]),
                                              ],
                                            ],
                                          )),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(t('pending_label'), style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
                                          ),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            onTap: () => _cancelRequest(r['_id']),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.red.withValues(alpha: 0.08),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                              ),
                                              child: const Icon(Icons.close, color: Colors.red, size: 16),
                                            ),
                                          ),
                                        ]),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 6),
                                  const Divider(height: 20),
                                ],

                                // ── Friends list ─────────────────────────────
                                _sectionHeader(t('your_friends_label'), _friends.length),
                                const SizedBox(height: 10),
                                // Search box
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppThemeColors.divider(context)),
                                  ),
                                  child: TextField(
                                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                                    decoration: InputDecoration(
                                      hintText: t('filter_friends_placeholder'),
                                      hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                                      prefixIcon: Icon(Icons.search, size: 18, color: AppThemeColors.mutedText(context)),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    onChanged: (val) {
                                      setState(() { _friendsQuery = val.trim(); _friendsVisibleCount = 10; });
                                      _friendsDebounceTimer?.cancel();
                                      _friendsDebounceTimer = Timer(const Duration(milliseconds: 350), _fetchFriends);
                                    },
                                  ),
                                ),
                                // Gender filter row
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(children: [
                                    _filterChip(t('all_genders_label'), null, _filterGender, (v) { setState(() { _filterGender = v; _friendsVisibleCount = 10; }); _fetchFriends(); }, icon: Icons.people),
                                    const SizedBox(width: 6),
                                    _filterChip(t('male_label'), 'Male', _filterGender, (v) { setState(() { _filterGender = v; _friendsVisibleCount = 10; }); _fetchFriends(); }, icon: Icons.male),
                                    const SizedBox(width: 6),
                                    _filterChip(t('female_label'), 'Female', _filterGender, (v) { setState(() { _filterGender = v; _friendsVisibleCount = 10; }); _fetchFriends(); }, icon: Icons.female),
                                    const SizedBox(width: 6),
                                    _filterChip(t('other_gender_label'), 'Other', _filterGender, (v) { setState(() { _filterGender = v; _friendsVisibleCount = 10; }); _fetchFriends(); }, icon: Icons.person_outline),
                                  ]),
                                ),
                                const SizedBox(height: 6),
                                // Sort row
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(children: [
                                    Icon(Icons.sort, size: 14, color: AppThemeColors.mutedText(context)),
                                    const SizedBox(width: 4),
                                    _sortChipF(t('sort_name_az'), 'name_az'),
                                    const SizedBox(width: 6),
                                    _sortChipF(t('sort_name_za'), 'name_za'),
                                    const SizedBox(width: 6),
                                    _sortChipF(t('sort_friend_since'), 'friend_since'),
                                    const SizedBox(width: 6),
                                    _sortChipF(t('sort_member_since'), 'member_since'),
                                    const SizedBox(width: 6),
                                    _sortChipF(t('sort_rating_label'), 'rating'),
                                  ]),
                                ),
                                const SizedBox(height: 10),
                                if (_friends.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.people_outline, size: 64, color: AppThemeColors.divider(context)),
                                        const SizedBox(height: 8),
                                        Text(
                                          _friendsQuery.isNotEmpty ? '${t('no_match_for_prefix')} "$_friendsQuery"' : t('no_friends_yet'),
                                          style: TextStyle(color: AppThemeColors.secondaryText(context)),
                                        ),
                                        if (_friendsQuery.isEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(t('search_above_to_add_friends'), style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                                        ],
                                      ]),
                                    ),
                                  )
                                else
                                  ..._friends.take(_friendsVisibleCount).toList().asMap().entries.map(
                                    (e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildFriendCard(e.value, e.key)),
                                  ),
                                if (_friends.length > _friendsVisibleCount)
                                  Center(
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.expand_more),
                                      label: Text('${t('show_label')} ${_friends.length - _friendsVisibleCount} ${t('more_label')}'),
                                      onPressed: () => setState(() => _friendsVisibleCount += 10),
                                    ),
                                  ),

                              ],
                            ),

                            // ── Tab 2: Requests ─────────────────────────────
                            ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                if (_incoming.isNotEmpty) ...[
                                  _sectionHeader(t('incoming_label'), _incoming.length, badgeColor: Colors.orange),
                                  const SizedBox(height: 10),
                                  ..._incoming.asMap().entries.map((e) {
                                    final r = e.value;
                                    final from = r['from'] is Map ? r['from'] as Map<String, dynamic> : <String, dynamic>{};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildRequestCard(
                                        from,
                                        t('wants_to_connect'),
                                        Row(mainAxisSize: MainAxisSize.min, children: [
                                          GestureDetector(
                                            onTap: () => _declineRequest(r['_id']),
                                            child: Container(
                                              width: 36, height: 36,
                                              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), shape: BoxShape.circle),
                                              child: const Icon(Icons.close, color: Colors.red, size: 18),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          GestureDetector(
                                            onTap: () => _acceptRequest(r['_id']),
                                            child: Container(
                                              width: 36, height: 36,
                                              decoration: const BoxDecoration(color: AppColors.cyan, shape: BoxShape.circle),
                                              child: const Icon(Icons.check, color: Colors.white, size: 18),
                                            ),
                                          ),
                                        ]),
                                        e.key,
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 16),
                                ],
                                if (_outgoing.isNotEmpty) ...[
                                  _sectionHeader(t('sent_label'), _outgoing.length, badgeColor: Colors.blue),
                                  const SizedBox(height: 10),
                                  ..._outgoing.asMap().entries.map((e) {
                                    final r = e.value;
                                    final to = r['to'] is Map ? r['to'] as Map<String, dynamic> : <String, dynamic>{};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildRequestCard(
                                        to, t('request_sent_label'),
                                        GestureDetector(
                                          onTap: () => _cancelRequest(r['_id']),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: AppThemeColors.divider(context)),
                                            ),
                                            child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 12, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                        e.key,
                                      ),
                                    );
                                  }),
                                ],
                                if (_incoming.isEmpty && _outgoing.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 48),
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.mail_outline, size: 64, color: AppThemeColors.divider(context)),
                                        const SizedBox(height: 8),
                                        Text(t('no_pending_requests'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                      ]),
                                    ),
                                  ),
                              ],
                            ),

                            // ── Tab 3: Blocked ──────────────────────────────
                            ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                _sectionHeader(t('blocked_users_label'), _blocked.length, badgeColor: Colors.red),
                                const SizedBox(height: 10),
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppThemeColors.divider(context)),
                                  ),
                                  child: TextField(
                                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                                    decoration: InputDecoration(
                                      hintText: t('search_blocked_users_placeholder'),
                                      hintStyle: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 13),
                                      prefixIcon: Icon(Icons.search, size: 18, color: AppThemeColors.mutedText(context)),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    onChanged: (val) => setState(() { _blockedQuery = val.trim(); _blockedVisibleCount = 10; }),
                                  ),
                                ),
                                if (_blocked.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.shield_outlined, size: 64, color: AppThemeColors.divider(context)),
                                        const SizedBox(height: 8),
                                        Text(t('no_blocked_users'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                      ]),
                                    ),
                                  )
                                else
                                  ...(_blockedQuery.isEmpty ? _blocked : _blocked.where((u) {
                                    final q = _blockedQuery.toLowerCase();
                                    return (u['email'] ?? '').toString().toLowerCase().contains(q) ||
                                        (u['name'] ?? u['username'] ?? '').toString().toLowerCase().contains(q);
                                  }).toList()).take(_blockedVisibleCount).toList().asMap().entries.map((e) {
                                    final u = e.value;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildRequestCard(
                                        Map<String, dynamic>.from(u),
                                        t('blocked_status_label'),
                                        GestureDetector(
                                          onTap: () => _unblockUser(u['_id']),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(t('unblock_label'), style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                        e.key,
                                      ),
                                    );
                                  }),
                              ],
                            ),

                            // ── Tab 4: Discover ─────────────────────────────
                            Consumer<SessionProvider>(
                              builder: (context, session, _) {
                                if (!session.hasFeature('discover')) {
                                  return const DiscoverPremiumGate();
                                }
                                return ListView(
                                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                  children: [
                                    _sectionHeader(t('people_you_may_know'), _suggestions.length, badgeColor: AppColors.cyan),
                                    const SizedBox(height: 4),
                                    Text(t('based_on_friends_transactions'),
                                      style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                    const SizedBox(height: 12),
                                    if (_suggestionsLoading)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.only(top: 64),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else if (_suggestions.isEmpty)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 48),
                                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(Icons.person_search, size: 64, color: AppThemeColors.divider(context)),
                                            const SizedBox(height: 8),
                                            Text(t('no_suggestions_right_now'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                            const SizedBox(height: 4),
                                            Text(t('add_more_friends_for_suggestions'), style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                                          ]),
                                        ),
                                      )
                                    else
                                      ..._suggestions.map((u) => Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: _buildSuggestionCard(u),
                                      )),
                                    const SizedBox(height: 20),
                                    _sectionHeader(t('top_rated_users_label'), _topRatedUsers.length, badgeColor: Colors.amber),
                                    const SizedBox(height: 8),
                                    if (_topRatedUsers.isEmpty)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 24),
                                          child: Text(t('no_top_rated_yet'), style: TextStyle(color: AppThemeColors.mutedText(context))),
                                        ),
                                      )
                                    else
                                      Builder(builder: (ctx) {
                                        final myId = Provider.of<SessionProvider>(ctx, listen: false).user?['_id']?.toString() ?? '';
                                        final friendIds = _friends.map((f) => f['_id']?.toString()).toSet();
                                        return Column(
                                          children: _topRatedUsers.map((u) {
                                            final uid = (u['_id'] ?? '').toString();
                                            if (uid == myId) return const SizedBox.shrink();
                                            final name = (u['name'] ?? u['username'] ?? 'Unknown').toString();
                                            final username = (u['username'] ?? '').toString();
                                            final avg = (u['avgRating'] as num?)?.toStringAsFixed(1) ?? '0.0';
                                            final rank = u['rank'] as int? ?? 0;
                                            final isFriend = friendIds.contains(uid);
                                            final isOutgoing = _pendingOutgoingIds.contains(uid) ||
                                              _outgoing.any((r) {
                                                final to = r['to'];
                                                return (to is Map ? to['_id'] : to)?.toString() == uid;
                                              });
                                            final isIncoming = _incoming.any((r) {
                                              final from = r['from'];
                                              return (from is Map ? from['_id'] : from)?.toString() == uid;
                                            });
                                            return Padding(
                                              padding: const EdgeInsets.only(bottom: 8),
                                              child: _tricolorBorder(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                                  decoration: BoxDecoration(
                                                    color: AppThemeColors.cardBg(context),
                                                    borderRadius: BorderRadius.circular(18),
                                                  ),
                                                  child: Row(children: [
                                                    Container(
                                                      width: 30,
                                                      alignment: Alignment.center,
                                                      child: Text('#$rank',
                                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber)),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    _profileAvatar(uid, name, username, radius: 22),
                                                    const SizedBox(width: 10),
                                                    Expanded(child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                        Row(children: [
                                                          if (username.isNotEmpty)
                                                            Text('@$username ', style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                                          const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                                                          const SizedBox(width: 2),
                                                          Text(avg, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                                                        ]),
                                                      ],
                                                    )),
                                                    const SizedBox(width: 8),
                                                    if (isFriend)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                                                        ),
                                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                          const Icon(Icons.check, size: 12, color: Colors.green),
                                                          const SizedBox(width: 4),
                                                          Text(t('friends_label'), style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                                                        ]),
                                                      )
                                                    else if (isIncoming)
                                                      ElevatedButton(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: Colors.green,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                          elevation: 0, minimumSize: Size.zero,
                                                        ),
                                                        onPressed: () {
                                                          final req = _incoming.firstWhere((r) {
                                                            final from = r['from'];
                                                            return (from is Map ? from['_id'] : from)?.toString() == uid;
                                                          }, orElse: () => {});
                                                          if (req.isNotEmpty) _acceptRequest(req['_id']?.toString() ?? '');
                                                        },
                                                        child: Text(t('accept'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                      )
                                                    else if (isOutgoing)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange.withValues(alpha: 0.1),
                                                          borderRadius: BorderRadius.circular(20),
                                                          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                                                        ),
                                                        child: Text(t('pending_label'), style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
                                                      )
                                                    else
                                                      ElevatedButton.icon(
                                                        style: ElevatedButton.styleFrom(
                                                          backgroundColor: AppColors.cyan,
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                                          elevation: 0, minimumSize: Size.zero,
                                                        ),
                                                        icon: const Icon(Icons.person_add, color: Colors.white, size: 13),
                                                        label: Text(t('add_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                                                        onPressed: () => _addFriend({'_id': uid, 'name': name, 'username': username}),
                                                      ),
                                                  ]),
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      }),
                                  ],
                                );
                              },
                            ),

                            // ── Tab 5: Balances ──────────────────────────────
                            _loadingBalances
                              ? const Center(child: CircularProgressIndicator())
                              : RefreshIndicator(
                                  onRefresh: _fetchFriendBalances,
                                  color: AppColors.cyan,
                                  child: _friendBalances.isEmpty
                                    ? ListView(
                                        padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
                                        children: [
                                          Center(
                                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                                              Icon(Icons.account_balance_wallet_outlined, size: 72,
                                                  color: AppThemeColors.divider(context)),
                                              const SizedBox(height: 14),
                                              Text(t('no_outstanding_balances_title'),
                                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                                      color: AppThemeColors.primaryText(context))),
                                              const SizedBox(height: 6),
                                              Text(t('no_outstanding_balances_subtitle'),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
                                            ]),
                                          ),
                                        ],
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                                        itemCount: _friendBalances.length,
                                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                                        itemBuilder: (_, i) {
                                          final b = _friendBalances[i];
                                          final name = (b['name'] ?? b['email'] ?? 'Unknown').toString();
                                          final net = (b['net'] as num?)?.toDouble() ?? 0;
                                          final owesYou = net > 0;
                                          final color = owesYou ? Colors.green.shade600 : Colors.red.shade600;
                                          final firstName = name.split(' ').first;
                                          final label = owesYou
                                              ? t('friend_owes_you_label').replaceAll('{name}', firstName)
                                              : t('you_owe_friend_label').replaceAll('{name}', firstName);
                                          final initials = _initials(name, (b['email'] ?? '').toString());
                                          final avatarColor = _avatarColor(name);
                                          final avatar = (b['avatar'] as String?);
                                          return Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: AppThemeColors.cardBg(context),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: color.withValues(alpha: 0.25)),
                                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
                                            ),
                                            child: Row(children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor: avatarColor,
                                                backgroundImage: avatar != null && avatar.isNotEmpty
                                                    ? NetworkImage('${ApiConfig.baseUrl}$avatar') : null,
                                                child: (avatar == null || avatar.isEmpty)
                                                    ? Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
                                                    : null,
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Text(name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                                                    color: AppThemeColors.primaryText(context))),
                                                const SizedBox(height: 2),
                                                Text(label, style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                                              ])),
                                              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                                Text('₹${net.abs().toStringAsFixed(0)}',
                                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                                                Container(
                                                  margin: const EdgeInsets.only(top: 4),
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: color.withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(owesYou ? t('gets_paid_label') : t('you_pay_label'),
                                                      style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                                                ),
                                              ]),
                                            ]),
                                          );
                                        },
                                      ),
                                ),
                          ],
                        ),
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

// ── Mutual Friends Bottom Sheet ───────────────────────────────────────────────

class _MutualFriendsSheet extends StatefulWidget {
  const _MutualFriendsSheet({
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.initials,
  });
  final String userId;
  final String displayName;
  final Color avatarColor;
  final String initials;

  @override
  State<_MutualFriendsSheet> createState() => _MutualFriendsSheetState();
}

class _MutualFriendsSheetState extends State<_MutualFriendsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _mutuals = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/friends/mutual?userId=${Uri.encodeComponent(widget.userId)}');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _mutuals = List<Map<String, dynamic>>.from(data['mutualFriends'] ?? []);
          _loading = false;
        });
      } else {
        setState(() { _error = AppLocalizations.of(context).t('could_not_load_mutual_friends'); _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = AppLocalizations.of(context).t('network_error'); _loading = false; });
    }
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF0077B6), Color(0xFF2E7D32), Color(0xFF6A1B9A),
      Color(0xFFD32F2F), Color(0xFF00838F), Color(0xFFE65100),
      Color(0xFF1565C0), Color(0xFF558B2F),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String username) {
    final n = name.trim();
    if (n.isNotEmpty) {
      final parts = n.split(' ');
      if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      return n[0].toUpperCase();
    }
    if (username.trim().isNotEmpty) return username[0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;

    final t = AppLocalizations.of(context).t;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppThemeColors.divider(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: widget.avatarColor,
                  child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                    Center(child: Text(widget.initials,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                    if (widget.userId.isNotEmpty)
                      Image.network(
                        '${ApiConfig.baseUrl}/api/users/${widget.userId}/profile-image',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                  ])),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('mutual_friends_title'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppThemeColors.primaryText(context))),
                      Text('${t('you_and_prefix')} ${widget.displayName}',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: AppThemeColors.mutedText(context),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          // Body
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: CircularProgressIndicator(color: AppColors.cyan),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          else if (_mutuals.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_outline, size: 48, color: AppThemeColors.divider(context)),
                const SizedBox(height: 8),
                Text(t('no_mutual_friends_found'), style: TextStyle(color: AppThemeColors.secondaryText(context))),
              ]),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: _mutuals.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                itemBuilder: (_, i) {
                  final m = _mutuals[i];
                  final mName = (m['name'] ?? '').toString();
                  final mUsername = (m['username'] ?? '').toString();
                  final mEmail = (m['email'] ?? '').toString();
                  final displayN = mName.isNotEmpty ? mName : mUsername;
                  final col = _avatarColor(displayN);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: col,
                          child: ClipOval(child: Stack(fit: StackFit.expand, children: [
                            Center(child: Text(_initials(mName, mUsername),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                            if ((m['_id']?.toString() ?? '').isNotEmpty)
                              Image.network(
                                '${ApiConfig.baseUrl}/api/users/${m['_id']}/profile-image',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                          ])),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayN,
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppThemeColors.primaryText(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (mUsername.isNotEmpty && mUsername != mName)
                                Text('@$mUsername',
                                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context))),
                              Text(mEmail,
                                style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(t('friend_label'), style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
