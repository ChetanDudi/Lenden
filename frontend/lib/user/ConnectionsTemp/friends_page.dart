import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../transaction/quick _transactions/quick_transactions_page.dart';
import '../transaction/secure_transactions/secure_transaction_page.dart';
import '../transaction/group_transactions/create_group_page.dart';
import '../../widgets/stylish_dialog.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({Key? key}) : super(key: key);

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
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
  final Set<String> _selectedForGroup = {};
  String _friendsQuery = '';
  int _friendsVisibleCount = 10;
  String _blockedQuery = '';
  int _blockedVisibleCount = 10;
  Map<String, int> _mutualCounts = {};
  Map<String, int> _interactionCounts = {};
  bool _showBlockedOnly = false;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  @override
  void dispose() {
    _friendsDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFriends() async {
    setState(() => _loading = true);
    try {
      final query = _friendsQuery.trim().isNotEmpty
          ? '?search=${Uri.encodeComponent(_friendsQuery.trim())}'
          : '';
      final res = await ApiClient.get('/api/friends$query');
      final reqRes = await ApiClient.get('/api/friends/requests');
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
      }
      await _loadInteractionCounts();
    } finally {
      setState(() => _loading = false);
    }
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
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final res =
          await ApiClient.get('/api/friends/search?q=${Uri.encodeComponent(query)}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = List<Map<String, dynamic>>.from(data['users'] ?? []);
        final lowerQuery = query.toLowerCase();
        final matchingFriends = _friends.where((f) {
          final email = (f['email'] ?? '').toString().toLowerCase();
          final name =
              (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
          return email.contains(lowerQuery) || name.contains(lowerQuery);
        }).toList();
        final matchingBlocked = _blocked.where((u) {
          final email = (u['email'] ?? '').toString().toLowerCase();
          final name =
              (u['name'] ?? u['username'] ?? '').toString().toLowerCase();
          return email.contains(lowerQuery) || name.contains(lowerQuery);
        }).toList();
        setState(() {
          _searchResults = results;
          if (results.isEmpty && matchingFriends.isNotEmpty) {
            _searchError = 'User already in your friends list.';
          } else if (results.isEmpty && matchingBlocked.isNotEmpty) {
            _searchError = 'User is blocked. Unblock to add again.';
          } else {
            _searchError =
                results.isEmpty ? 'No users found for "$query".' : null;
          }
        });
      } else {
        setState(() {
          _searchResults = [];
          _searchError = 'Failed to search users. Please try again.';
        });
      }
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _addFriend(Map<String, dynamic> user) async {
    final res =
        await ApiClient.post('/api/friends/request', body: {'userId': user['_id']});
    if (res.statusCode == 200 || res.statusCode == 201) {
      await _fetchFriends();
      await showDialog(
        context: context,
        builder: (_) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                color: _getNoteColor(1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Request Sent',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your friend request has been sent.',
                    style: TextStyle(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send request')),
      );
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    final res =
        await ApiClient.post('/api/friends/requests/$requestId/accept');
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<void> _declineRequest(String requestId) async {
    final res =
        await ApiClient.post('/api/friends/requests/$requestId/decline');
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    final res =
        await ApiClient.post('/api/friends/requests/$requestId/cancel');
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<void> _removeFriend(String friendId) async {
    final ok = await _confirmAction(
        title: 'Remove Friend',
        message: 'Are you sure you want to remove this friend?');
    if (!ok) return;
    final res = await ApiClient.delete('/api/friends/$friendId');
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<void> _blockUser(String userId) async {
    final ok = await _confirmAction(
        title: 'Block User',
        message:
            'Blocking will prevent some requests. Continue?');
    if (!ok) return;
    final res = await ApiClient.post('/api/friends/block', body: {
      'userId': userId,
    });
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<void> _unblockUser(String userId) async {
    final ok = await _confirmAction(
        title: 'Unblock User',
        message: 'Do you want to unblock this user?');
    if (!ok) return;
    final res = await ApiClient.post('/api/friends/unblock', body: {
      'userId': userId,
    });
    if (res.statusCode == 200) {
      await _fetchFriends();
    }
  }

  Future<bool> _confirmAction(
      {required String title, required String message}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              color: _getNoteColor(2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style:
                        const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal),
                        child: const Text('Confirm'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return result == true;
  }

  void _openQuickTransaction(String email) {
    if (_isBlockedEmail(email)) {
      showBlockedUserDialog(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickTransactionsPage(
          prefillCounterpartyEmail: email,
          openCreateOnLoad: true,
        ),
      ),
    );
  }

  void _openUserTransaction(String email) {
    if (_isBlockedEmail(email)) {
      showBlockedUserDialog(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionPage(prefillCounterpartyEmail: email),
      ),
    );
  }

  void _openGroupWithSelected() {
    if (_selectedForGroup.isEmpty) return;
    if (_selectedForGroup.any(_isBlockedEmail)) {
      showBlockedUserDialog(context);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateGroupPage(
          prefillMemberEmails: _selectedForGroup.toList(),
        ),
      ),
    );
  }

  Widget _buildFriendTile(Map<String, dynamic> friend, int index) {
    final email = friend['email'] ?? '';
    final name = (friend['name'] ?? '').toString();
    final username = (friend['username'] ?? '').toString();
    final selected = _selectedForGroup.contains(email);
    final friendId = friend['_id'] ?? '';
    final isBlocked = _blocked.any((u) => u['_id'] == friendId);
    final isBlockedByThem = friend['blockedByThem'] == true;
    final interactions =
        _interactionCounts[email.toString().toLowerCase().trim()] ?? 0;

    return _tricolorWrapper(
      index: index,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (username.isNotEmpty && username != name) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        email.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade800,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Checkbox(
                  value: selected,
                  visualDensity: VisualDensity.compact,
                  onChanged: (val) {
                    if (val == true && isBlockedByThem) {
                      showBlockedUserDialog(context,
                          message: 'You cannot add this user because they have blocked you.');
                      return;
                    }
                    if (val == true && isBlocked) {
                      showBlockedUserDialog(context);
                      return;
                    }
                    setState(() {
                      if (val == true) {
                        _selectedForGroup.add(email);
                      } else {
                        _selectedForGroup.remove(email);
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_mutualCounts.containsKey(friendId))
                  _buildInfoChip(
                    label: '${_mutualCounts[friendId]} mutual',
                    textColor: Colors.teal.shade700,
                    backgroundColor: Colors.teal.withOpacity(0.12),
                  ),
                if (interactions > 0)
                  _buildInfoChip(
                    label: 'Interactions: $interactions',
                    textColor: Colors.blue.shade700,
                    backgroundColor: Colors.blue.withOpacity(0.10),
                  ),
                if (isBlockedByThem)
                  _buildInfoChip(
                    label: 'Blocked you',
                    textColor: Colors.red.shade700,
                    backgroundColor: Colors.red.withOpacity(0.10),
                  ),
                if (isBlocked)
                  _buildInfoChip(
                    label: 'You blocked',
                    textColor: Colors.orange.shade800,
                    backgroundColor: Colors.orange.withOpacity(0.14),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildActionButton(
                  icon: Icons.flash_on,
                  label: 'Quick',
                  onPressed: () {
                    if (isBlockedByThem) {
                      showBlockedUserDialog(context,
                          message: 'You cannot add this user because they have blocked you.');
                      return;
                    }
                    if (isBlocked) {
                      showBlockedUserDialog(context);
                      return;
                    }
                    _openQuickTransaction(email);
                  },
                ),
                _buildActionButton(
                  icon: Icons.receipt_long,
                  label: 'Transaction',
                  onPressed: () {
                    if (isBlockedByThem) {
                      showBlockedUserDialog(context,
                          message: 'You cannot add this user because they have blocked you.');
                      return;
                    }
                    if (isBlocked) {
                      showBlockedUserDialog(context);
                      return;
                    }
                    _openUserTransaction(email);
                  },
                ),
                _buildActionButton(
                  icon: Icons.person_remove,
                  label: 'Remove',
                  onPressed: () => _removeFriend(friendId),
                ),
                _buildActionButton(
                  icon: isBlocked ? Icons.lock_open : Icons.block,
                  label: isBlocked ? 'Unblock' : 'Block',
                  onPressed: () =>
                      isBlocked ? _unblockUser(friendId) : _blockUser(friendId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required String label,
    required Color textColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.82),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF00B4D8).withOpacity(0.18),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF4D4A57)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4D4A57),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isBlockedEmail(String email) {
    final target = email.toLowerCase().trim();
    return _blocked.any((u) =>
        (u['email'] ?? '').toString().toLowerCase().trim() == target);
  }

  Future<void> _loadMutualCounts() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final now = DateTime.now();
    final lastFetched = session.mutualCountsLastFetched;
    if (session.mutualFriendCounts != null &&
        lastFetched != null &&
        now.difference(lastFetched).inMinutes < 10) {
      setState(() {
        _mutualCounts = session.mutualFriendCounts!;
      });
      return;
    }

    final ids = _friends
        .map((f) => f['_id']?.toString())
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return;
    try {
      final res = await ApiClient.post('/api/friends/mutual-counts',
          body: {'userIds': ids});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final counts = Map<String, dynamic>.from(data['counts'] ?? {});
        if (mounted) {
          setState(() {
            _mutualCounts = counts.map(
              (k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0),
            );
          });
          session.setMutualFriendCounts(_mutualCounts);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_mutualCounts.isEmpty && _friends.isNotEmpty) {
      _loadMutualCounts();
    }
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
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Friends',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                      if (_selectedForGroup.isNotEmpty)
                        TextButton(
                          onPressed: _openGroupWithSelected,
                          child: const Text('Create Group'),
                        )
                      else
                        const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _fetchFriends,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            children: [
                              _tricolorWrapper(
                                index: 0,
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    labelText: 'Search by email or username',
                                    border: InputBorder.none,
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.arrow_forward),
                                      onPressed: _searchUsers,
                                    ),
                                  ),
                                  onChanged: (_) {
                                    if (_searchError != null) {
                                      setState(() {
                                        _searchError = null;
                                      });
                                    }
                                  },
                                  onSubmitted: (_) => _searchUsers(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_searching) const LinearProgressIndicator(),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Show Blocked Only',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Switch(
                                    value: _showBlockedOnly,
                                    onChanged: (val) {
                                      setState(() {
                                        _showBlockedOnly = val;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_showBlockedOnly) ...[
                                const SizedBox(height: 8),
                                const Text('Blocked Users',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _tricolorWrapper(
                                  index: 3,
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      hintText: 'Search blocked users',
                                      prefixIcon: Icon(Icons.search),
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _blockedQuery = val.trim();
                                        _blockedVisibleCount = 10;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...(_blockedQuery.isEmpty
                                        ? _blocked
                                        : _blocked.where((u) {
                                            final q = _blockedQuery.toLowerCase();
                                            return (u['email'] ?? '').toString().toLowerCase().contains(q) ||
                                                (u['name'] ?? u['username'] ?? '').toString().toLowerCase().contains(q);
                                          }).toList())
                                    .take(_blockedVisibleCount)
                                    .toList()
                                    .asMap()
                                    .entries
                                    .map((entry) {
                                  final u = entry.value;
                                  final email = u['email'] ?? '';
                                  final name = u['name'] ?? u['username'] ?? '';
                                  return _tricolorWrapper(
                                    index: entry.key + 3,
                                    child: ListTile(
                                      title: Text(name.toString()),
                                      subtitle: Text(email.toString()),
                                      trailing: TextButton(
                                        onPressed: () => _unblockUser(u['_id']),
                                        child: const Text('Unblock'),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                if ((_blockedQuery.isEmpty ? _blocked : _blocked.where((u) {
                                      final q = _blockedQuery.toLowerCase();
                                      return (u['email'] ?? '').toString().toLowerCase().contains(q) ||
                                          (u['name'] ?? u['username'] ?? '').toString().toLowerCase().contains(q);
                                    }).toList()).length >
                                    _blockedVisibleCount)
                                  Center(
                                    child: TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _blockedVisibleCount += 10;
                                        });
                                      },
                                      child: const Text('Load more'),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                              ],
                              if (_searchError != null) ...[
                                const SizedBox(height: 12),
                                _tricolorWrapper(
                                  index: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      _searchError!,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (_showBlockedOnly)
                                const SizedBox(height: 8)
                              else
                              if (_searchResults.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                const Text('Search Results',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ..._searchResults.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final u = entry.value;
                                  final email = u['email'] ?? '';
                                  final name = (u['name'] ?? '').toString();
                                  final username =
                                      (u['username'] ?? '').toString();
                                  final isFriend =
                                      _friends.any((f) => f['_id'] == u['_id']);
                                  final isOutgoing = _outgoing.any((r) =>
                                      (r['to']?['_id'] ?? r['to']) == u['_id']);
                                  final isIncoming = _incoming.any((r) =>
                                      (r['from']?['_id'] ?? r['from']) ==
                                      u['_id']);
                                  return _tricolorWrapper(
                                    index: i,
                                    child: ListTile(
                                      title:
                                          Text(name.isNotEmpty ? name : username),
                                      subtitle: Text(email),
                                      trailing: isFriend
                                          ? const Text('Friend')
                                          : isIncoming
                                              ? const Text('Requested You')
                                              : isOutgoing
                                                  ? const Text('Requested')
                                                  : ElevatedButton(
                                                      onPressed: () =>
                                                          _addFriend(u),
                                                      child: const Text('Add'),
                                                    ),
                                    ),
                                  );
                                }).toList(),
                              ],
                              if (_showBlockedOnly)
                                const SizedBox(height: 8)
                              else
                              if (_incoming.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text('Requests',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ..._incoming.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final r = entry.value;
                                  final from = r['from'] ?? {};
                                  final email = from['email'] ?? '';
                                  final name =
                                      from['name'] ?? from['username'] ?? '';
                                  return _tricolorWrapper(
                                    index: i + 1,
                                    child: ListTile(
                                      title: Text(name.toString()),
                                      subtitle: Text(email.toString()),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          TextButton(
                                            onPressed: () =>
                                                _declineRequest(r['_id']),
                                            child: const Text('Decline'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                _acceptRequest(r['_id']),
                                            child: const Text('Accept'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                              if (_showBlockedOnly)
                                const SizedBox(height: 8)
                              else
                              if (_outgoing.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const Text('Sent Requests',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ..._outgoing.asMap().entries.map((entry) {
                                  final i = entry.key;
                                  final r = entry.value;
                                  final to = r['to'] ?? {};
                                  final email = to['email'] ?? '';
                                  final name =
                                      to['name'] ?? to['username'] ?? '';
                                  return _tricolorWrapper(
                                    index: i + 2,
                                    child: ListTile(
                                      title: Text(name.toString()),
                                      subtitle: Text(email.toString()),
                                      trailing: TextButton(
                                        onPressed: () =>
                                            _cancelRequest(r['_id']),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                              if (!_showBlockedOnly) ...[
                                const SizedBox(height: 16),
                                const Text('Your Friends',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _tricolorWrapper(
                                  index: 2,
                                  child: TextField(
                                    decoration: const InputDecoration(
                                      hintText: 'Search friends',
                                      prefixIcon: Icon(Icons.search),
                                      border: InputBorder.none,
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _friendsQuery = val.trim();
                                        _friendsVisibleCount = 10;
                                      });
                                      _friendsDebounceTimer?.cancel();
                                      _friendsDebounceTimer = Timer(
                                        const Duration(milliseconds: 300),
                                        _fetchFriends,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (_friends.isEmpty)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(top: 24),
                                      child: Text('No friends yet'),
                                    ),
                                  )
                                else
                                  ..._friends
                                      .take(_friendsVisibleCount)
                                      .toList()
                                      .asMap()
                                      .entries
                                      .map((entry) => _buildFriendTile(
                                          entry.value, entry.key))
                                      .toList(),
                                if (_friends.length >
                                    _friendsVisibleCount)
                                  Center(
                                    child: TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _friendsVisibleCount += 10;
                                        });
                                      },
                                      child: const Text('Load more'),
                                    ),
                                  ),
                              ],
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

  Widget _tricolorWrapper({required Widget child, required int index}) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: _getNoteColor(index),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: child,
        ),
      ),
    );
  }

  Color _getNoteColor(int index) {
    final colors = [
      const Color(0xFFFFF4E6),
      const Color(0xFFE8F5E9),
      const Color(0xFFFCE4EC),
      const Color(0xFFE3F2FD),
      const Color(0xFFFFF9C4),
      const Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    final double factor = 0.5; // 🔽 reduce to half

    path.lineTo(0, size.height * 0.8 * factor);

    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 1.0 * factor,
      size.width * 0.5,
      size.height * 0.8 * factor,
    );

    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6 * factor,
      size.width,
      size.height * 0.8 * factor,
    );

    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
