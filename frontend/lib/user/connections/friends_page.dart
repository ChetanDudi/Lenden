import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../transaction/secure_transactions/secure_transaction_page.dart';
import '../transaction/group_transactions/create_group_page.dart';
import '../../widgets/stylish_dialog.dart';

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
  final Set<String> _pendingOutgoingIds = {};
  final Set<String> _selectedForGroup = {};
  String _friendsQuery = '';
  int _friendsVisibleCount = 10;
  String _blockedQuery = '';
  int _blockedVisibleCount = 10;
  Map<String, int> _mutualCounts = {};
  Map<String, int> _interactionCounts = {};
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchFriends();
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

  // Filtered view — pure client-side, no network call needed
  List<Map<String, dynamic>> get _filteredFriends {
    if (_friendsQuery.isEmpty) return _friends;
    final q = _friendsQuery.toLowerCase();
    return _friends.where((f) {
      final name = (f['name'] ?? '').toString().toLowerCase();
      final username = (f['username'] ?? '').toString().toLowerCase();
      final email = (f['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || username.contains(q) || email.contains(q);
    }).toList();
  }

  Future<void> _fetchFriends() async {
    setState(() => _loading = true);
    try {
      // Run both API calls in parallel — cuts wait time in half
      final results = await Future.wait([
        ApiClient.get('/api/friends'),
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
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadSuggestions() async {
    try {
      final res = await ApiClient.get('/api/friends/suggestions?limit=10');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = List<Map<String, dynamic>>.from(data['suggestions'] ?? data['users'] ?? []);
        // Exclude existing friends, blocked, and pending
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
    } catch (_) {}
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
        _searchError = "That's you! You can't add yourself as a friend.";
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
            _searchError = 'User already in your friends list.';
          } else if (results.isEmpty && matchingBlocked.isNotEmpty) {
            _searchError = 'User is blocked. Unblock to add again.';
          } else {
            _searchError = results.isEmpty ? 'No users found for "$query".' : null;
          }
        });
      } else {
        setState(() { _searchResults = []; _searchError = 'Failed to search. Try again.'; });
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
      _showSuccessDialog('Request Sent', 'Friend request sent successfully!', Icons.check_circle, Colors.green);
    } else if (res.statusCode == 200) {
      // Already pending from a prior send — refresh to sync state
      await _fetchFriends();
    } else {
      setState(() => _pendingOutgoingIds.remove(uid));
      showSnack(context, 'Failed to send request', isError: true);
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    final res = await ApiClient.post('/api/friends/requests/$requestId/accept');
    if (res.statusCode == 200) {
      await _fetchFriends();
      showSnack(context, 'Friend request accepted!');
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
    final ok = await _confirmAction(title: 'Remove Friend', message: 'Remove this friend from your list?', icon: Icons.person_remove, color: Colors.red);
    if (!ok) return;
    final res = await ApiClient.delete('/api/friends/$friendId');
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _blockUser(String userId) async {
    final ok = await _confirmAction(title: 'Block User', message: 'Block this user? They won\'t be able to interact with you.', icon: Icons.block, color: Colors.orange);
    if (!ok) return;
    final res = await ApiClient.post('/api/friends/block', body: {'userId': userId});
    if (res.statusCode == 200) await _fetchFriends();
  }

  Future<void> _unblockUser(String userId) async {
    final ok = await _confirmAction(title: 'Unblock User', message: 'Unblock this user?', icon: Icons.lock_open, color: Colors.teal);
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
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 30),
                ),
                const SizedBox(height: 14),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: color),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm', style: TextStyle(color: Colors.white)),
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

  void _showSuccessDialog(String title, String msg, IconData icon, Color color) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: _tricolorBorder(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: 52),
              const SizedBox(height: 12),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: color),
                onPressed: () => Navigator.pop(context),
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
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
    if (!session.isSubscribed) {
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
            featureName: 'secure transaction', coinCost: 10, currentCoins: coins);
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
    if (!session.isSubscribed) {
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
            featureName: 'group creation', coinCost: 20, currentCoins: coins);
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

    return _tricolorBorder(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
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
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: color,
                        child: Text(
                          _initials(name, username),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
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
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        if (username.isNotEmpty && username != name)
                          Text('@$username', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1),
                        Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  // Group checkbox
                  GestureDetector(
                    onTap: () {
                      if (!selected && isBlockedByThem) { showBlockedUserDialog(context, message: 'You cannot add this user because they have blocked you.'); return; }
                      if (!selected && isBlocked) { showBlockedUserDialog(context); return; }
                      setState(() {
                        if (selected) _selectedForGroup.remove(email);
                        else _selectedForGroup.add(email);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.cyan.withValues(alpha: 0.12) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? AppColors.cyan : Colors.grey[300]!),
                      ),
                      child: Icon(
                        selected ? Icons.group_add : Icons.group_add_outlined,
                        size: 18,
                        color: selected ? AppColors.cyan : Colors.grey[500],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chips row — horizontal scroll, single line
            if (mutualCount > 0 || interactions > 0 || isBlocked || isBlockedByThem)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (mutualCount > 0) ...[
                        GestureDetector(
                          onTap: () => _showMutualFriendsSheet(friendId, displayName),
                          child: _chip('$mutualCount mutual 👥', Colors.teal.shade600, Colors.teal.withValues(alpha: 0.1)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (interactions > 0) ...[_chip('$interactions transactions', Colors.blue.shade600, Colors.blue.withValues(alpha: 0.1)), const SizedBox(width: 6)],
                      if (isBlockedByThem) ...[_chip('Blocked you', Colors.red.shade700, Colors.red.withValues(alpha: 0.1)), const SizedBox(width: 6)],
                      if (isBlocked) _chip('You blocked', Colors.orange.shade700, Colors.orange.withValues(alpha: 0.1)),
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
                    _actionBtn(Icons.flash_on, 'Quick', const Color(0xFF0077B6), () {
                      if (isBlockedByThem || isBlocked) { showBlockedUserDialog(context); return; }
                      _openQuickTransaction(email);
                    }),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.receipt_long, 'Secure', const Color(0xFF2E7D32), () {
                      if (isBlockedByThem || isBlocked) { showBlockedUserDialog(context); return; }
                      _openUserTransaction(email);
                    }),
                    const SizedBox(width: 12),
                    _iconActionBtn(isBlocked ? Icons.lock_open : Icons.block, isBlocked ? Colors.teal : Colors.orange,
                      () => isBlocked ? _unblockUser(friendId) : _blockUser(friendId),
                      tooltip: isBlocked ? 'Unblock' : 'Block',
                    ),
                    const SizedBox(width: 6),
                    _iconActionBtn(Icons.person_remove, Colors.red,
                      () => _removeFriend(friendId),
                      tooltip: 'Remove friend',
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

  Widget _sectionHeader(String title, int count, {Color? badgeColor}) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF023E8A))),
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
    final color = _avatarColor(name);

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color,
              child: Text(_initials(name, username), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final color = _avatarColor(name.isNotEmpty ? name : username);

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color,
              child: Text(_initials(name, username), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isNotEmpty ? name : username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (username.isNotEmpty && username != name)
                    Text('@$username', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text(email, style: TextStyle(fontSize: 12, color: Colors.grey[500]), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isFriend)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Friend', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 12)),
              )
            else if (isIncoming)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Wants to connect', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12)),
              )
            else if (isOutgoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                child: const Text('Pending', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600, fontSize: 12)),
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
                child: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
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
    final color = _avatarColor(displayName);
    final suid = u['_id']?.toString() ?? '';
    final isOutgoing = _pendingOutgoingIds.contains(suid) ||
        _outgoing.any((r) {
          final to = r['to'];
          return (to is Map ? to['_id'] : to)?.toString() == suid;
        });

    return _tricolorBorder(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: color,
              child: Text(_initials(name, username),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (username.isNotEmpty && username != name)
                    Text('@$username', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  if (email.isNotEmpty)
                    Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  if (mutualCount > 0)
                    GestureDetector(
                      onTap: () => _showMutualFriendsSheet(suid, displayName),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.people, size: 12, color: Colors.teal[600]),
                        const SizedBox(width: 3),
                        Text('$mutualCount mutual friend${mutualCount == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11, color: Colors.teal[600], fontWeight: FontWeight.w500)),
                        const SizedBox(width: 2),
                        Icon(Icons.chevron_right, size: 12, color: Colors.teal[400]),
                      ]),
                    )
                  else if (reason.isNotEmpty)
                    Text(reason, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                child: const Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
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
                label: const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
      backgroundColor: const Color(0xFFE0F7FA),
      body: Stack(
        children: [
          // Wave header
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF48CAE4)],
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
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Friends', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                            Text('${_friends.length} friend${_friends.length == 1 ? '' : 's'}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70)),
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
                              Text('Group (${_selectedForGroup.length})', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'Search by name, email, or username',
                              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                              prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
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
                    color: Colors.white,
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
                    unselectedLabelColor: Colors.grey[600],
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.people, size: 15),
                          const SizedBox(width: 4),
                          Text('Friends${_friends.isNotEmpty ? ' (${_friends.length})' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.mail, size: 15),
                          const SizedBox(width: 4),
                          Text('Requests${pendingCount > 0 ? ' ($pendingCount)' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.block, size: 15),
                          const SizedBox(width: 4),
                          Text('Blocked${_blocked.isNotEmpty ? ' (${_blocked.length})' : ''}'),
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.person_search, size: 15),
                          const SizedBox(width: 4),
                          Text('Discover${_suggestions.isNotEmpty ? ' (${_suggestions.length})' : ''}'),
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
                                if (_searchResults.isNotEmpty) ...[
                                  _sectionHeader('Search Results', _searchResults.length, badgeColor: Colors.purple),
                                  const SizedBox(height: 10),
                                  ..._searchResults.asMap().entries.map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildSearchResultCard(e.value, e.key),
                                  )),
                                  const Divider(height: 24),
                                ],
                                // ── Sent Requests (outgoing) ────────────────
                                if (_outgoing.isNotEmpty) ...[
                                  _sectionHeader('Sent Requests', _outgoing.length, badgeColor: Colors.orange),
                                  const SizedBox(height: 8),
                                  ..._outgoing.map((r) {
                                    final to = r['to'] is Map ? r['to'] as Map<String, dynamic> : <String, dynamic>{};
                                    final name = (to['name'] ?? to['username'] ?? 'Unknown').toString();
                                    final email = (to['email'] ?? '').toString();
                                    final username = (to['username'] ?? '').toString();
                                    final color = _avatarColor(name);
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
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: color,
                                            child: Text(_initials(name, username),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                              Text(email, style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          )),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Text('Pending', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w600)),
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
                                _sectionHeader('Your Friends', _filteredFriends.length),
                                const SizedBox(height: 10),
                                // Filter search
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Filter friends...',
                                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                      prefixIcon: Icon(Icons.filter_list, size: 18, color: Colors.grey[400]),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    onChanged: (val) {
                                      setState(() { _friendsQuery = val.trim(); _friendsVisibleCount = 10; });
                                    },
                                  ),
                                ),
                                if (_filteredFriends.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 32),
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text(
                                          _friendsQuery.isNotEmpty ? 'No match for "$_friendsQuery"' : 'No friends yet',
                                          style: TextStyle(color: Colors.grey[500]),
                                        ),
                                        if (_friendsQuery.isEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text('Search above to add friends', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                                        ],
                                      ]),
                                    ),
                                  )
                                else
                                  ..._filteredFriends.take(_friendsVisibleCount).toList().asMap().entries.map(
                                    (e) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _buildFriendCard(e.value, e.key)),
                                  ),
                                if (_filteredFriends.length > _friendsVisibleCount)
                                  Center(
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.expand_more),
                                      label: Text('Show ${_filteredFriends.length - _friendsVisibleCount} more'),
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
                                  _sectionHeader('Incoming', _incoming.length, badgeColor: Colors.orange),
                                  const SizedBox(height: 10),
                                  ..._incoming.asMap().entries.map((e) {
                                    final r = e.value;
                                    final from = r['from'] is Map ? r['from'] as Map<String, dynamic> : <String, dynamic>{};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildRequestCard(
                                        from,
                                        'Wants to connect',
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
                                  _sectionHeader('Sent', _outgoing.length, badgeColor: Colors.blue),
                                  const SizedBox(height: 10),
                                  ..._outgoing.asMap().entries.map((e) {
                                    final r = e.value;
                                    final to = r['to'] is Map ? r['to'] as Map<String, dynamic> : <String, dynamic>{};
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildRequestCard(
                                        to, 'Request sent',
                                        GestureDetector(
                                          onTap: () => _cancelRequest(r['_id']),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.grey[300]!),
                                            ),
                                            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                        Icon(Icons.mail_outline, size: 64, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text('No pending requests', style: TextStyle(color: Colors.grey[500])),
                                      ]),
                                    ),
                                  ),
                              ],
                            ),

                            // ── Tab 3: Blocked ──────────────────────────────
                            ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                _sectionHeader('Blocked Users', _blocked.length, badgeColor: Colors.red),
                                const SizedBox(height: 10),
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Search blocked users...',
                                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                                      prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
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
                                        Icon(Icons.shield_outlined, size: 64, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text('No blocked users', style: TextStyle(color: Colors.grey[500])),
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
                                        'Blocked',
                                        GestureDetector(
                                          onTap: () => _unblockUser(u['_id']),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                                            ),
                                            child: const Text('Unblock', style: TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.w600)),
                                          ),
                                        ),
                                        e.key,
                                      ),
                                    );
                                  }),
                              ],
                            ),

                            // ── Tab 4: Discover ─────────────────────────────
                            ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              children: [
                                _sectionHeader('People You May Know', _suggestions.length, badgeColor: AppColors.cyan),
                                const SizedBox(height: 4),
                                Text('Based on your friends & transactions',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                const SizedBox(height: 12),
                                if (_suggestions.isEmpty)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 48),
                                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text('No suggestions right now', style: TextStyle(color: Colors.grey[500])),
                                        const SizedBox(height: 4),
                                        Text('Add more friends to get suggestions', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                                      ]),
                                    ),
                                  )
                                else
                                  ..._suggestions.map((u) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _buildSuggestionCard(u),
                                  )),
                              ],
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
        setState(() { _error = 'Could not load mutual friends.'; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Network error.'; _loading = false; });
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

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
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
                  child: Text(widget.initials,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mutual Friends', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('You & ${widget.displayName}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.grey[500],
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
                Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('No mutual friends found', style: TextStyle(color: Colors.grey[500])),
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
                          child: Text(_initials(mName, mUsername),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(displayN,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (mUsername.isNotEmpty && mUsername != mName)
                                Text('@$mUsername',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              Text(mEmail,
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
                          child: const Text('Friend', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
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
