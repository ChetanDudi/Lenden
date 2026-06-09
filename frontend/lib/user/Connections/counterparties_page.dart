import 'dart:convert';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/api_client.dart';
import '../../session.dart';

class CounterpartiesPage extends StatefulWidget {
  const CounterpartiesPage({super.key});

  @override
  State<CounterpartiesPage> createState() => _CounterpartiesPageState();
}

class _CounterpartiesPageState extends State<CounterpartiesPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _friendEmails = {};
  final Set<String> _outgoingRequestEmails = {};

  List<Map<String, dynamic>> _counterparties = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchCounterparties();
    _fetchFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounterparties({bool forceRefresh = false}) async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final now = DateTime.now();
    final lastFetched = session.counterpartiesLastFetched;

    if (!forceRefresh &&
        lastFetched != null &&
        now.difference(lastFetched).inMinutes < 5 &&
        session.counterparties != null) {
      setState(() {
        _counterparties = session.counterparties!;
        _isLoading = false;
      });
      return;
    }

    final email = session.user?['email'];
    if (email == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.get('/api/counterparties/user?email=$email');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawCounterparties =
            List<Map<String, dynamic>>.from(data['counterparties'] ?? []);

        final profiles = await Future.wait(
          rawCounterparties.map(
              (cp) => _fetchCounterpartyProfile(cp['email']?.toString() ?? '')),
        );

        final merged = <Map<String, dynamic>>[];
        for (int i = 0; i < rawCounterparties.length; i++) {
          final base = rawCounterparties[i];
          final profile = profiles[i];
          if (profile != null) {
            merged.add({...base, ...profile});
          } else {
            merged.add({
              ...base,
              'name': 'Unknown',
              'email': base['email'],
            });
          }
        }

        // Filter out the logged-in user from counterparties
        final filtered = merged.where((cp) {
          final cpEmail = (cp['email'] ?? '').toString().toLowerCase().trim();
          final currentUserEmail = email.toLowerCase().trim();
          return cpEmail != currentUserEmail;
        }).toList();

        if (mounted) {
          setState(() {
            _counterparties = filtered;
          });
        }
        session.setCounterparties(filtered);
      }
    } catch (_) {
      // Keep the page resilient if the request fails.
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchFriends() async {
    try {
      final friendsRes = await ApiClient.get('/api/friends');
      final requestsRes = await ApiClient.get('/api/friends/requests');

      if (friendsRes.statusCode == 200) {
        final data = jsonDecode(friendsRes.body);
        _friendEmails
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(data['friends'] ?? [])
                .map((f) => (f['email'] ?? '').toString().toLowerCase().trim())
                .where((e) => e.isNotEmpty),
          );
      }

      if (requestsRes.statusCode == 200) {
        final data = jsonDecode(requestsRes.body);
        _outgoingRequestEmails
          ..clear()
          ..addAll(
            (data['outgoing'] as List? ?? [])
                .map((r) => (r['to']?['email'] ?? r['toEmail'] ?? '')
                    .toString()
                    .toLowerCase()
                    .trim())
                .where((e) => e.isNotEmpty),
          );
      }

      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Ignore friend lookup failures and keep counterparties usable.
    }
  }

  Future<Map<String, dynamic>?> _fetchCounterpartyProfile(String email) async {
    if (email.isEmpty) return null;
    try {
      final res =
          await ApiClient.get('/api/users/profile-by-email?email=$email');
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchCounterpartyStats(String email) async {
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final myEmail = session.user?['email'];
      if (myEmail == null || email.isEmpty) return null;
      final res = await ApiClient.get(
        '/api/counterparties/stats?email=$myEmail&counterpartyEmail=$email',
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _sendFriendRequest({
    String? userId,
    String? email,
    bool closeDialogOnSuccess = true,
  }) async {
    try {
      final body = userId != null ? {'userId': userId} : {'query': email};
      final res = await ApiClient.post('/api/friends/request', body: body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (email != null && email.isNotEmpty) {
          _outgoingRequestEmails.add(email.toLowerCase().trim());
        }
        if (mounted) {
          setState(() {});
        }
        ElegantNotification.success(
          title: const Text('Request Sent'),
          description: const Text('Friend request sent successfully.'),
        ).show(context);
        if (closeDialogOnSuccess) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? 'Failed to send request';
        ElegantNotification.error(
          title: const Text('Error'),
          description: Text(err.toString()),
        ).show(context);
      }
    } catch (e) {
      ElegantNotification.error(
        title: const Text('Error'),
        description: Text(e.toString()),
      ).show(context);
    }
  }

  List<Map<String, dynamic>> get _filteredCounterparties {
    if (_searchQuery.trim().isEmpty) {
      return _counterparties;
    }
    final query = _searchQuery.toLowerCase().trim();
    return _counterparties.where((counterparty) {
      final name = (counterparty['name'] ?? '').toString().toLowerCase();
      final email = (counterparty['email'] ?? '').toString().toLowerCase();
      final phone = (counterparty['phone'] ?? '').toString().toLowerCase();
      final gender = (counterparty['gender'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          email.contains(query) ||
          phone.contains(query) ||
          gender.contains(query);
    }).toList();
  }

  ImageProvider _buildAvatarProvider(Map<String, dynamic> counterparty) {
    final imageUrl = counterparty['profileImage'];
    final gender = counterparty['gender'] ?? 'Other';

    if (imageUrl != null &&
        imageUrl is String &&
        imageUrl.trim().isNotEmpty &&
        imageUrl != 'null') {
      return NetworkImage(imageUrl);
    }

    return AssetImage(
      gender == 'Male'
          ? 'assets/Male.png'
          : gender == 'Female'
              ? 'assets/Female.png'
              : 'assets/Other.png',
    );
  }

  Future<void> _openCounterparty(Map<String, dynamic> counterparty) async {
    final name = counterparty['name'] ?? 'Unknown';
    final avatar = _buildAvatarProvider(counterparty);
    final isPrivate = counterparty['profileIsPrivate'] == true;
    final isDeactivated = counterparty['deactivatedAccount'] == true;
    final currentUserEmail =
        Provider.of<SessionProvider>(context, listen: false).user?['email'];
    final counterpartyEmail =
        counterparty['email']?.toString().toLowerCase().trim() ?? '';

    if (isPrivate || isDeactivated) {
      showDialog(
        context: context,
        builder: (_) => _PrivateProfileDialog(
          name: name,
          isPrivate: isPrivate,
          isDeactivated: isDeactivated,
          avatarProvider: avatar,
        ),
      );
      return;
    }

    final stats =
        await _fetchCounterpartyStats(counterparty['email']?.toString() ?? '');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => _StylishProfileDialog(
        title: 'Counterparty',
        name: name,
        avatarProvider: avatar,
        email: counterparty['email']?.toString(),
        phone: counterparty['phone']?.toString(),
        gender: counterparty['gender']?.toString(),
        stats: stats,
        canAddFriend: counterpartyEmail.isNotEmpty &&
            counterpartyEmail !=
                (currentUserEmail ?? '').toString().toLowerCase().trim() &&
            !_friendEmails.contains(counterpartyEmail) &&
            !_outgoingRequestEmails.contains(counterpartyEmail),
        isFriend: _friendEmails.contains(counterpartyEmail),
        requestPending: _outgoingRequestEmails.contains(counterpartyEmail),
        onAddFriend: () => _sendFriendRequest(
          userId: counterparty['_id']?.toString(),
          email: counterparty['email']?.toString(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCounterparties;

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
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Counterparties',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.black),
                        onPressed: () =>
                            _fetchCounterparties(forceRefresh: true),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          icon: const Icon(Icons.search,
                              color: Color(0xFF00B4D8)),
                          hintText: 'Search counterparties',
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        '${filtered.length} shown',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_counterparties.length} total',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F7FA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Tap any counterparty card to open profile details.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B8FAC),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_outline,
                                      size: 72, color: Colors.grey[400]),
                                  const SizedBox(height: 14),
                                  Text(
                                    _counterparties.isEmpty
                                        ? 'No counterparties yet'
                                        : 'No counterparties match your search',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final crossAxisCount = width > 1200
                                    ? 5
                                    : width > 900
                                        ? 4
                                        : width > 650
                                            ? 3
                                            : 2;

                                return GridView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 14,
                                    mainAxisSpacing: width < 420 ? 26 : 18,
                                    childAspectRatio: width < 420 ? 0.82 : 0.8,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    return _CounterpartyGridCard(
                                      counterparty: filtered[index],
                                      avatarProvider:
                                          _buildAvatarProvider(filtered[index]),
                                      accentColor: _getBoxColor(index),
                                      onTap: () =>
                                          _openCounterparty(filtered[index]),
                                    );
                                  },
                                );
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
}

class _CounterpartyGridCard extends StatelessWidget {
  final Map<String, dynamic> counterparty;
  final ImageProvider avatarProvider;
  final Color accentColor;
  final VoidCallback onTap;

  const _CounterpartyGridCard({
    required this.counterparty,
    required this.avatarProvider,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = (counterparty['name'] ?? 'Unknown').toString();
    final isPrivate = counterparty['profileIsPrivate'] == true;
    final isDeactivated = counterparty['deactivatedAccount'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: accentColor,
                      image: DecorationImage(
                        image: avatarProvider,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (isDeactivated || isPrivate)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDeactivated
                              ? Colors.red.withOpacity(0.08)
                              : Colors.orange.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isDeactivated
                              ? 'Account inactive'
                              : 'Private profile',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDeactivated
                                ? Colors.red.shade400
                                : Colors.orange.shade700,
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

class _PrivateProfileDialog extends StatelessWidget {
  final String name;
  final bool isPrivate;
  final bool isDeactivated;
  final ImageProvider avatarProvider;

  const _PrivateProfileDialog({
    required this.name,
    required this.isPrivate,
    required this.isDeactivated,
    required this.avatarProvider,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;

    if (isDeactivated) {
      message = 'This user account is deactivated.';
      icon = Icons.visibility_off;
    } else if (isPrivate) {
      message = 'This user\'s profile is private.';
      icon = Icons.lock;
    } else {
      message = 'This profile is not available.';
      icon = Icons.error;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF00B4D8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundImage: avatarProvider),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Column(
              children: [
                Icon(icon, size: 40, color: Colors.teal),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4D8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StylishProfileDialog extends StatelessWidget {
  final String title;
  final String name;
  final ImageProvider avatarProvider;
  final String? email;
  final String? phone;
  final String? gender;
  final Map<String, dynamic>? stats;
  final bool canAddFriend;
  final bool isFriend;
  final bool requestPending;
  final VoidCallback? onAddFriend;

  const _StylishProfileDialog({
    required this.title,
    required this.name,
    required this.avatarProvider,
    this.email,
    this.phone,
    this.gender,
    this.stats,
    this.canAddFriend = false,
    this.isFriend = false,
    this.requestPending = false,
    this.onAddFriend,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF00B4D8),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundImage: avatarProvider),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (email != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.email, size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(email!,
                              style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (phone != null && phone!.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(phone!, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (gender != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.transgender,
                          size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(gender!, style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (stats != null) ...[
                  Row(
                    children: const [
                      Icon(Icons.insights, size: 18, color: Colors.teal),
                      SizedBox(width: 8),
                      Text(
                        'Interactions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Trxns: ${stats?['userTransactions'] ?? 0} • Quick: ${stats?['quickTransactions'] ?? 0} • Groups: ${stats?['groups'] ?? 0}',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 10),
                ],
                if (isFriend) ...[
                  const Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'Already a friend',
                        style: TextStyle(fontSize: 16, color: Colors.green),
                      ),
                    ],
                  ),
                ] else if (requestPending) ...[
                  const Row(
                    children: [
                      Icon(Icons.hourglass_top, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text(
                        'Request pending',
                        style: TextStyle(fontSize: 16, color: Colors.orange),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (canAddFriend)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ElevatedButton(
                      onPressed: onAddFriend,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Add Friend'),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00B4D8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _getBoxColor(int index) {
  const colors = [
    Color(0xFFE8F5E9),
    Color(0xFFFFF8E7),
    Color(0xFFF3E5F5),
    Color(0xFFE8F5F7),
    Color(0xFFFCE4EC),
    Color(0xFFFFF3E0),
  ];
  return colors[index % colors.length];
}
