import 'dart:convert';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../utils/api_client.dart';
import '../../session.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';

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
  String _sortBy = 'count';
  String? _filterGender;
  Map<String, Map<String, dynamic>> _birthdayByEmail = {};
  final Set<String> _wishedFriendIds = {};

  @override
  void initState() {
    super.initState();
    _fetchCounterparties();
    _fetchFriends();
    _loadBirthdayFriends();
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

  Future<void> _loadBirthdayFriends() async {
    try {
      final res = await ApiClient.get('/api/friends/birthdays?days=7');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['birthdays'] ?? []);
        final map = <String, Map<String, dynamic>>{};
        final alreadyWished = <String>{};
        for (final b in list) {
          final email = (b['email'] ?? '').toString().toLowerCase().trim();
          if (email.isNotEmpty) map[email] = b;
          if (b['hasWished'] == true) {
            final id = b['_id']?.toString() ?? '';
            if (id.isNotEmpty) alreadyWished.add(id);
          }
        }
        if (mounted) {
          setState(() {
            _birthdayByEmail = map;
            _wishedFriendIds.addAll(alreadyWished);
          });
        }
      }
    } catch (_) {}
  }

  void _showBirthdayWishDialog(Map<String, dynamic> friend) {
    final t = AppLocalizations.of(context).t;
    final name = (friend['name'] ?? 'Friend').toString();
    final controller = TextEditingController(
      text: 'Happy Birthday $name! Wishing you a wonderful day filled with joy and happiness. Many happy returns!',
    );
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB300), Color(0xFFFFF176), Color(0xFFFFB300)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.cake_rounded, color: Colors.amber, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  'Send Birthday Wish',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(ctx)),
                ),
                const SizedBox(height: 4),
                Text(
                  'to $name',
                  style: const TextStyle(fontSize: 13, color: Colors.amber, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppThemeColors.surfaceBg(ctx),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    hintText: 'Write your wish...',
                  ),
                  style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(ctx)),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: const BorderSide(color: Colors.grey),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final message = controller.text.trim();
                        Navigator.pop(ctx);
                        try {
                          await ApiClient.post('/api/friends/${friend['_id']}/wish', body: {'message': message});
                          if (mounted) {
                            setState(() => _wishedFriendIds.add(friend['_id']?.toString() ?? ''));
                            ElegantNotification.success(
                              title: Text(t('success')),
                              description: Text('Birthday wish sent to $name!'),
                            ).show(context);
                          }
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Send Wish', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    ).then((_) => controller.dispose());
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
    final t = AppLocalizations.of(context).t;
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
          title: Text(t('request_sent_title')),
          description: Text(t('friend_request_sent_success')),
        ).show(context);
        if (closeDialogOnSuccess) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      } else {
        final err = jsonDecode(res.body)['error'] ?? t('failed_to_send_request');
        ElegantNotification.error(
          title: Text(t('error')),
          description: Text(err.toString()),
        ).show(context);
      }
    } catch (e) {
      ElegantNotification.error(
        title: Text(t('error')),
        description: Text(e.toString()),
      ).show(context);
    }
  }

  List<Map<String, dynamic>> get _filteredCounterparties {
    var list = _counterparties.where((cp) {
      final q = _searchQuery.toLowerCase().trim();
      final matchesQuery = q.isEmpty ||
          (cp['name'] ?? '').toString().toLowerCase().contains(q) ||
          (cp['email'] ?? '').toString().toLowerCase().contains(q) ||
          (cp['phone'] ?? '').toString().toLowerCase().contains(q);
      final matchesGender = _filterGender == null ||
          (cp['gender'] ?? '').toString() == _filterGender;
      return matchesQuery && matchesGender;
    }).toList();

    switch (_sortBy) {
      case 'name_asc':
        list.sort((a, b) => (a['name'] ?? '').toString().toLowerCase()
            .compareTo((b['name'] ?? '').toString().toLowerCase()));
        break;
      case 'count_asc':
        list.sort((a, b) => ((a['count'] ?? 0) as num).compareTo((b['count'] ?? 0) as num));
        break;
      default:
        list.sort((a, b) => ((b['count'] ?? 0) as num).compareTo((a['count'] ?? 0) as num));
    }
    return list;
  }

  Widget _genderChip(String label, String? value, {IconData? icon}) {
    final selected = _filterGender == value;
    return GestureDetector(
      onTap: () => setState(() => _filterGender = selected ? null : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.deepPurple : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.deepPurple : Colors.grey.withValues(alpha: 0.35)),
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

  Widget _sortChip(String label, String value) {
    final selected = _sortBy == value;
    return GestureDetector(
      onTap: () => setState(() => _sortBy = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.cyan : Colors.grey.withValues(alpha: 0.35)),
        ),
        child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppThemeColors.secondaryText(context))),
      ),
    );
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
    final t = AppLocalizations.of(context).t;
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
        title: t('counterparty_label'),
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
    final t = AppLocalizations.of(context).t;
    final filtered = _filteredCounterparties;

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
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
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
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('counterparties'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
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
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(color: AppThemeColors.primaryText(context)),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          icon: const Icon(Icons.search,
                              color: AppColors.cyan),
                          hintText: t('search_counterparties'),
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Row(
                    children: [
                      Text('${filtered.length} ${t('shown_suffix')}',
                        style: TextStyle(color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      Text('${_counterparties.length} ${t('total_suffix')}',
                        style: TextStyle(color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          Icon(Icons.sort_rounded, size: 15, color: AppThemeColors.secondaryText(context)),
                          const SizedBox(width: 6),
                          Text(t('sort_colon'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          _sortChip(t('most_label'), 'count'),
                          const SizedBox(width: 6),
                          _sortChip(t('a_z_label'), 'name_asc'),
                          const SizedBox(width: 6),
                          _sortChip(t('least_label'), 'count_asc'),
                        ]),
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          Icon(Icons.people_outline, size: 15, color: AppThemeColors.secondaryText(context)),
                          const SizedBox(width: 6),
                          Text(t('filter_label'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          _genderChip(t('all_genders_label'), null, icon: Icons.people),
                          const SizedBox(width: 6),
                          _genderChip(t('male_label'), 'Male', icon: Icons.male),
                          const SizedBox(width: 6),
                          _genderChip(t('female_label'), 'Female', icon: Icons.female),
                          const SizedBox(width: 6),
                          _genderChip(t('other_gender_label'), 'Other', icon: Icons.person_outline),
                        ]),
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
                      color: AppThemeColors.tinted(context,
                          light: const Color(0xFFE8F7FA), dark: const Color(0xFF163A42)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      t('tap_counterparty_card_hint'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0B8FAC),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _fetchCounterparties(forceRefresh: true),
                    color: AppColors.cyan,
                    child: _isLoading
                      ? const SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: SizedBox(height: 300, child: Center(child: CircularProgressIndicator())))
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_outline,
                                      size: 72, color: AppThemeColors.mutedText(context)),
                                  const SizedBox(height: 14),
                                  Text(
                                    _counterparties.isEmpty
                                        ? t('no_counterparties_yet')
                                        : t('no_counterparties_match_search'),
                                    style: TextStyle(
                                      color: AppThemeColors.secondaryText(context),
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

                                // Counterparties who also have birthdays soon
                                final birthdayCounterparties = filtered.where((cp) {
                                  final email = (cp['email'] ?? '').toString().toLowerCase().trim();
                                  return _birthdayByEmail.containsKey(email);
                                }).toList();
                                final todayBirthdays = birthdayCounterparties
                                    .where((cp) {
                                      final email = (cp['email'] ?? '').toString().toLowerCase().trim();
                                      return (_birthdayByEmail[email]?['daysUntil'] ?? 1) == 0;
                                    })
                                    .toList();

                                return CustomScrollView(
                                  slivers: [
                                    if (birthdayCounterparties.isNotEmpty)
                                      SliverToBoxAdapter(
                                        child: Container(
                                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFFFFF3CD), Color(0xFFFFE082)],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(children: [
                                                const Icon(Icons.cake_rounded, size: 16, color: Colors.amber),
                                                const SizedBox(width: 8),
                                                Text(
                                                  'Birthdays this week',
                                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF7B4F00)),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                                                  child: Text('${birthdayCounterparties.length}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                                ),
                                              ]),
                                              const SizedBox(height: 10),
                                              ...birthdayCounterparties.map((cp) {
                                                final email = (cp['email'] ?? '').toString().toLowerCase().trim();
                                                final bInfo = _birthdayByEmail[email]!;
                                                final isToday = (bInfo['daysUntil'] ?? 1) == 0;
                                                final days = bInfo['daysUntil'] as int? ?? 0;
                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: Row(children: [
                                                    CircleAvatar(
                                                      radius: 14,
                                                      backgroundImage: _buildAvatarProvider(cp),
                                                      backgroundColor: Colors.amber.withValues(alpha: 0.3),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Text(
                                                        (cp['name'] ?? 'Unknown').toString(),
                                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF7B4F00)),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (isToday)
                                                      _wishedFriendIds.contains(bInfo['_id']?.toString())
                                                        ? Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.green.shade400,
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                                              Icon(Icons.check, size: 12, color: Colors.white),
                                                              SizedBox(width: 3),
                                                              Text('You wished', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                                            ]),
                                                          )
                                                        : TextButton(
                                                            onPressed: () => _showBirthdayWishDialog(bInfo),
                                                            style: TextButton.styleFrom(
                                                              backgroundColor: Colors.amber,
                                                              foregroundColor: Colors.white,
                                                              minimumSize: const Size(60, 28),
                                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                            ),
                                                            child: const Text('Wish', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                                          )
                                                    else
                                                      Text(
                                                        'in $days day${days == 1 ? '' : 's'}',
                                                        style: const TextStyle(fontSize: 11, color: Color(0xFF997A00)),
                                                      ),
                                                  ]),
                                                );
                                              }),
                                              if (todayBirthdays.isEmpty)
                                                const Padding(
                                                  padding: EdgeInsets.only(top: 2),
                                                  child: Text('Tap their card to wish them!', style: TextStyle(fontSize: 11, color: Color(0xFF997A00))),
                                                ),
                                            ]),
                                          ),
                                        ),
                                      ),
                                    SliverPadding(
                                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                                      sliver: SliverGrid(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                            final cp = filtered[index];
                                            final email = (cp['email'] ?? '').toString().toLowerCase().trim();
                                            final bInfo = _birthdayByEmail[email];
                                            final hasWished = bInfo != null &&
                                                _wishedFriendIds.contains(bInfo['_id']?.toString());
                                            return _CounterpartyGridCard(
                                              counterparty: cp,
                                              avatarProvider: _buildAvatarProvider(cp),
                                              accentColor: _getBoxColor(index),
                                              birthdayInfo: bInfo,
                                              hasWished: hasWished,
                                              onTap: () => _openCounterparty(cp),
                                            );
                                          },
                                          childCount: filtered.length,
                                        ),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 14,
                                          mainAxisSpacing: width < 420 ? 26 : 18,
                                          childAspectRatio: width < 420 ? 0.82 : 0.8,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
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

class _CounterpartyGridCard extends StatelessWidget {
  final Map<String, dynamic> counterparty;
  final ImageProvider avatarProvider;
  final Color accentColor;
  final VoidCallback onTap;
  final Map<String, dynamic>? birthdayInfo;
  final bool hasWished;

  const _CounterpartyGridCard({
    required this.counterparty,
    required this.avatarProvider,
    required this.accentColor,
    required this.onTap,
    this.birthdayInfo,
    this.hasWished = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final name = (counterparty['name'] ?? 'Unknown').toString();
    final isPrivate = counterparty['profileIsPrivate'] == true;
    final isDeactivated = counterparty['deactivatedAccount'] == true;
    final avgRating = counterparty['avgRating'] as num?;

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
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
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
                  if ((counterparty['count'] ?? 0) > 0)
                    Positioned(
                      top: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${counterparty['count']}×',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  if (birthdayInfo != null)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: hasWished
                              ? Colors.green.shade400
                              : (birthdayInfo!['daysUntil'] == 0
                                  ? Colors.amber
                                  : Colors.amber.withValues(alpha: 0.80)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            hasWished ? Icons.check : Icons.cake_rounded,
                            size: 11, color: Colors.white,
                          ),
                          if (hasWished || birthdayInfo!['daysUntil'] == 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              hasWished ? 'Wished' : 'Today!',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ]),
                      ),
                    ),
                ],
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    if (avgRating != null && avgRating > 0) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(avgRating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    if (isDeactivated || isPrivate)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isDeactivated
                              ? Colors.red.withValues(alpha: 0.08)
                              : Colors.orange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isDeactivated
                              ? t('account_inactive')
                              : t('private_profile'),
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
    final t = AppLocalizations.of(context).t;
    String message;
    IconData icon;

    if (isDeactivated) {
      message = t('user_account_deactivated_msg');
      icon = Icons.visibility_off;
    } else if (isPrivate) {
      message = t('user_profile_private_msg');
      icon = Icons.lock;
    } else {
      message = t('profile_not_available_msg');
      icon = Icons.error;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppThemeColors.cardBg(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.cyan,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundImage: avatarProvider, onBackgroundImageError: (_, __) {}),
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
                  style: TextStyle(fontSize: 16, color: AppThemeColors.secondaryText(context)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(t('close')),
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
    final t = AppLocalizations.of(context).t;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: AppThemeColors.cardBg(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.cyan,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundImage: avatarProvider, onBackgroundImageError: (_, __) {}),
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
                              style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(context)))),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (phone != null && phone!.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(phone!, style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(context))),
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
                      Text(gender!, style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(context))),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (stats != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.insights, size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Text(
                        t('interactions_label'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${t('trxns_label')}: ${stats?['userTransactions'] ?? 0} • ${t('quick_label')}: ${stats?['quickTransactions'] ?? 0} • ${t('groups_label')}: ${stats?['groups'] ?? 0}',
                    style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(height: 10),
                ],
                if (isFriend) ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 18, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        t('already_a_friend'),
                        style: const TextStyle(fontSize: 16, color: Colors.green),
                      ),
                    ],
                  ),
                ] else if (requestPending) ...[
                  Row(
                    children: [
                      const Icon(Icons.hourglass_top, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        t('request_pending'),
                        style: const TextStyle(fontSize: 16, color: Colors.orange),
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
                      child: Text(t('add_friend')),
                    ),
                  ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(t('close')),
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
