import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../utils/api_client.dart';
import '../../session.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart';
import '../../widgets/search_tab_bar.dart';

class CounterpartiesPage extends StatefulWidget {
  final bool initialShowCloseOnly;
  const CounterpartiesPage({super.key, this.initialShowCloseOnly = false});

  @override
  State<CounterpartiesPage> createState() => _CounterpartiesPageState();
}

class _CounterpartiesPageState extends State<CounterpartiesPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _friendEmails = {};
  final Set<String> _outgoingRequestEmails = {};

  List<Map<String, dynamic>> _counterparties = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _sortBy = 'count_desc';
  String? _filterGender;
  Timer? _searchDebounce;
  Map<String, Map<String, dynamic>> _birthdayByEmail = {};
  final Set<String> _wishedFriendIds = {};
  final Map<String, int> _giftedCoins = {};
  final Set<String> _closeCounterpartyIds = {};
  bool _showCloseOnly = false;

  @override
  void initState() {
    super.initState();
    _showCloseOnly = widget.initialShowCloseOnly;
    _fetchCounterparties();
    _fetchFriends();
    _loadBirthdayFriends();
    _fetchCloseCounterparties();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchCounterparties({bool forceRefresh = false}) async {
    final session = Provider.of<SessionProvider>(context, listen: false);

    // Use cache only when no active filters are set and cache is fresh
    final hasFilters = _searchQuery.isNotEmpty || _filterGender != null || _sortBy != 'count_desc';
    if (!forceRefresh && !hasFilters) {
      final lastFetched = session.counterpartiesLastFetched;
      final now = DateTime.now();
      if (lastFetched != null &&
          now.difference(lastFetched).inMinutes < 5 &&
          session.counterparties != null) {
        setState(() {
          _counterparties = session.counterparties!;
          _isLoading = false;
        });
        return;
      }
    }

    final email = session.user?['email'];
    if (email == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      final params = StringBuffer('/api/counterparties/user?email=${Uri.encodeComponent(email)}');
      if (_searchQuery.isNotEmpty) params.write('&search=${Uri.encodeComponent(_searchQuery)}');
      if (_filterGender != null) params.write('&gender=${Uri.encodeComponent(_filterGender!)}');
      if (_sortBy.isNotEmpty) params.write('&sortBy=${Uri.encodeComponent(_sortBy)}');

      final res = await ApiClient.get(params.toString());
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['counterparties'] ?? []);
        if (mounted) setState(() => _counterparties = list);
        // Only cache unfiltered results
        if (!hasFilters) session.setCounterparties(list);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load counterparties.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
        final gifted = <String, int>{};
        for (final b in list) {
          final email = (b['email'] ?? '').toString().toLowerCase().trim();
          if (email.isNotEmpty) map[email] = b;
          if (b['hasWished'] == true) {
            final id = b['_id']?.toString() ?? '';
            if (id.isNotEmpty) alreadyWished.add(id);
          }
          final amt = (b['giftedAmount'] as num? ?? 0).toInt();
          if (amt > 0) {
            final id = b['_id']?.toString() ?? '';
            if (id.isNotEmpty) gifted[id] = amt;
          }
        }
        if (mounted) {
          setState(() {
            _birthdayByEmail = map;
            _wishedFriendIds.addAll(alreadyWished);
            _giftedCoins.addAll(gifted);
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchCloseCounterparties() async {
    try {
      final res = await ApiClient.get('/api/user/favourites');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        final list = (data['closeCounterparties'] as List?) ?? [];
        setState(() {
          _closeCounterpartyIds
            ..clear()
            ..addAll(list.map((c) => c['_id'].toString()));
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleCloseCounterparty(String userId) async {
    try {
      final res = await ApiClient.post('/api/user/favourites/close-counterparty/$userId');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() {
          if (data['added'] == true) {
            _closeCounterpartyIds.add(userId);
          } else {
            _closeCounterpartyIds.remove(userId);
          }
        });
      }
    } catch (_) {}
  }

  void _showBirthdayWishDialog(Map<String, dynamic> friend) {
    final t = AppLocalizations.of(context).t;
    final name = (friend['name'] ?? 'Friend').toString();
    final friendId = friend['_id']?.toString() ?? '';

    final templates = [
      'Happy Birthday $name! Wishing you a wonderful day filled with joy and happiness!',
      'Many happy returns of the day, $name! May this year bring you health, wealth, and success!',
      'Wishing you a very Happy Birthday, $name! Hope your day is as amazing as you are!',
      'Happy Birthday $name! Sending you warmest wishes and lots of love on your special day!',
    ];
    final controller = TextEditingController(text: templates[0]);
    int selectedTemplate = 0;
    int selectedGift = 0;
    const giftAmounts = [5, 10, 25, 50];
    bool sending = false;

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
                      Center(child: Column(children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.cake_rounded, size: 32, color: Colors.amber),
                        ),
                        const SizedBox(height: 10),
                        Text('Happy Birthday, $name!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(ctx))),
                        const SizedBox(height: 4),
                        Text('Today is their special day',
                          style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(ctx))),
                      ])),
                      const SizedBox(height: 18),
                      Text('Quick message', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppThemeColors.secondaryText(ctx))),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(templates.length, (i) {
                            final labels = ['Cheerful', 'Inspiring', 'Warm', 'Classic'];
                            final sel = selectedTemplate == i;
                            return GestureDetector(
                              onTap: () => setS(() {
                                selectedTemplate = i;
                                controller.text = templates[i];
                              }),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: sel ? Colors.amber : Colors.amber.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: sel ? Colors.amber : Colors.amber.withValues(alpha: 0.4)),
                                ),
                                child: Text(labels[i],
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                      color: sel ? Colors.white : const Color(0xFF7B4F00))),
                              ),
                            );
                          }),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        maxLines: 3,
                        onChanged: (_) => setS(() => selectedTemplate = -1),
                        style: TextStyle(fontSize: 13, color: AppThemeColors.primaryText(ctx)),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppThemeColors.surfaceBg(ctx),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          hintText: 'Write your wish...',
                        ),
                      ),
                      const SizedBox(height: 16),
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
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF7B4F00)),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Text('· $myCoins coins',
                                style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(ctx))),
                            ]),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [
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
                                GestureDetector(
                                  onTap: () {
                                    final affordable = giftAmounts.where((a) => myCoins >= a).toList();
                                    if (affordable.isEmpty) return;
                                    setS(() => selectedGift = affordable[Random().nextInt(affordable.length)]);
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
                              ]),
                            ),
                            if (selectedGift > 0) ...[
                              const SizedBox(height: 8),
                              Text('$selectedGift coins will be deducted from your balance',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF997000))),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              side: BorderSide(color: AppThemeColors.divider(ctx)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(t('cancel')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: sending ? null : () async {
                              setS(() => sending = true);
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
                                if (giftOk && ctx.mounted) {
                                  final giftData = jsonDecode(giftRes.body);
                                  final remaining = (giftData['remainingCoins'] as num?)?.toInt();
                                  if (remaining != null) {
                                    Provider.of<SessionProvider>(ctx, listen: false).updateUserCoins(remaining);
                                  }
                                }
                              }
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (wishRes.statusCode == 201 && mounted) {
                                setState(() {
                                  _wishedFriendIds.add(friendId);
                                  if (selectedGift > 0 && giftOk) _giftedCoins[friendId] = selectedGift;
                                });
                                final msg = selectedGift > 0 && giftOk
                                    ? 'Wish sent + $selectedGift coins gifted to $name!'
                                    : 'Birthday wish sent to $name!';
                                ElegantNotification.success(
                                  title: Text(t('success')),
                                  description: Text(msg),
                                ).show(context);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: sending
                                ? const SizedBox(width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text(
                                    selectedGift > 0 ? 'Send Wish + Gift 🎁' : 'Send Wish',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
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

  Widget _genderChip(String label, String? value, {IconData? icon}) {
    final selected = _filterGender == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filterGender = selected ? null : value);
        _fetchCounterparties(forceRefresh: true);
      },
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
      onTap: () {
        if (_sortBy != value) {
          setState(() => _sortBy = value);
          _fetchCounterparties(forceRefresh: true);
        }
      },
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
    final filtered = _showCloseOnly
        ? _counterparties.where((cp) => _closeCounterpartyIds.contains(cp['_id']?.toString())).toList()
        : _counterparties;

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
                AppSearchBar(
                  controller: _searchController,
                  hintText: t('search_counterparties'),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
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
                          _sortChip(t('most_label'), 'count_desc'),
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
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() => _showCloseOnly = !_showCloseOnly),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _showCloseOnly ? Colors.orange : AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _showCloseOnly ? Colors.orange : Colors.grey.withValues(alpha: 0.35)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.handshake_rounded, size: 13,
                                  color: _showCloseOnly ? Colors.white : Colors.orange),
                                const SizedBox(width: 4),
                                Text('Close only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                  color: _showCloseOnly ? Colors.white : AppThemeColors.secondaryText(context))),
                              ]),
                            ),
                          ),
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
                      : _error != null
                          ? errorStateWidget(context, _error!, () => _fetchCounterparties(forceRefresh: true))
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
                                  if (_counterparties.isEmpty) ...[
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      onPressed: () => _fetchCounterparties(forceRefresh: true),
                                      icon: const Icon(Icons.refresh_rounded, size: 18),
                                      label: Text(t('retry'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFFF06322),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                      ),
                                    ),
                                  ],
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
                                                final bdayDate = DateTime.tryParse(bInfo['birthday']?.toString() ?? '');
                                                final age = bdayDate != null ? DateTime.now().year - bdayDate.year : 0;
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
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            (cp['name'] ?? 'Unknown').toString(),
                                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF4A3500)),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                          Text(
                                                            isToday
                                                                ? (age > 0 ? 'Turning $age today! 🎉' : 'Birthday today!')
                                                                : 'in $days day${days == 1 ? '' : 's'}${age > 0 ? ' · Turning $age' : ''}',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color: isToday ? Colors.deepOrange : const Color(0xFF7B5800),
                                                              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    if (isToday) Builder(builder: (_) {
                                                      final bid = bInfo['_id']?.toString() ?? '';
                                                      final wished = _wishedFriendIds.contains(bid);
                                                      final gifted = _giftedCoins[bid] ?? 0;
                                                      if (wished || gifted > 0) {
                                                        return Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.green.shade500,
                                                            borderRadius: BorderRadius.circular(8),
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
                                                      return TextButton(
                                                        onPressed: () => _showBirthdayWishDialog(bInfo),
                                                        style: TextButton.styleFrom(
                                                          backgroundColor: Colors.amber,
                                                          foregroundColor: Colors.white,
                                                          minimumSize: const Size(80, 28),
                                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                        ),
                                                        child: const Text('Wish + Gift 🎁', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                                      );
                                                    })
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
                                            final bid = bInfo?['_id']?.toString() ?? '';
                                            final hasWished = bInfo != null && _wishedFriendIds.contains(bid);
                                            final giftedAmt = bid.isNotEmpty ? (_giftedCoins[bid] ?? 0) : 0;
                                            final cpId = cp['_id']?.toString() ?? '';
                                            return _CounterpartyGridCard(
                                              counterparty: cp,
                                              avatarProvider: _buildAvatarProvider(cp),
                                              accentColor: _getBoxColor(index),
                                              birthdayInfo: bInfo,
                                              hasWished: hasWished,
                                              giftedAmount: giftedAmt,
                                              isClose: cpId.isNotEmpty && _closeCounterpartyIds.contains(cpId),
                                              onToggleClose: cpId.isNotEmpty
                                                  ? () => _toggleCloseCounterparty(cpId)
                                                  : null,
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
  final int giftedAmount;
  final bool isClose;
  final VoidCallback? onToggleClose;

  const _CounterpartyGridCard({
    required this.counterparty,
    required this.avatarProvider,
    required this.accentColor,
    required this.onTap,
    this.birthdayInfo,
    this.hasWished = false,
    this.giftedAmount = 0,
    this.isClose = false,
    this.onToggleClose,
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
                  Positioned(
                    bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: onToggleClose,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: isClose
                              ? Colors.orange.withValues(alpha: 0.9)
                              : Colors.black.withValues(alpha: 0.28),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isClose ? Icons.handshake_rounded : Icons.handshake_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (birthdayInfo != null)
                    Positioned(
                      top: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: (hasWished || giftedAmount > 0)
                              ? Colors.green.shade500
                              : (birthdayInfo!['daysUntil'] == 0
                                  ? Colors.amber
                                  : Colors.amber.withValues(alpha: 0.80)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                            (hasWished || giftedAmount > 0) ? Icons.check : Icons.cake_rounded,
                            size: 11, color: Colors.white,
                          ),
                          if (hasWished || giftedAmount > 0 || birthdayInfo!['daysUntil'] == 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              giftedAmount > 0 ? '+$giftedAmount coins' : hasWished ? 'Wished' : 'Today!',
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
