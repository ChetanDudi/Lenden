import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import '../../utils/api_client.dart';
import '../transaction/secure_transactions/secure_transaction_page.dart';
import '../transaction/secure_transactions/view_secure_transactions_page.dart';
import '../transaction/analytics_page.dart';
import '../digitise/gift_card_page.dart';
import '../support/notes_page.dart';
import '../transaction/group_transactions/group_transaction_page.dart';
import '../transaction/group_transactions/view_group_transactions_page.dart';
import '../../profile/profile_page.dart';
import '../rating/ratings_page.dart';
import '../activity/activity_page.dart';
import '../support/help_support_page.dart';
import '../activity/leaderboard_page.dart';
import '../digitise/referral_page.dart';
import '../../widgets/notification_icon.dart';
import '../digitise/subscriptions_page.dart';
import '../transaction/quick_transactions/quick_transactions_page.dart';
import '../connections/friends_page.dart';
import '../digitise/offers_page.dart';
import '../connections/counterparties_page.dart';
import '../digitise/lenden_coins_page.dart';
import '../ads_and_updates/updates_page.dart';
import '../ads_and_updates/ad_popup_dialog.dart';
import '../wallet/lenden_wallet_page.dart';
import '../../widgets/stylish_dialog.dart';
import '../scanner/qr_scanner_page.dart';
import 'package:elegant_notification/elegant_notification.dart';
import '../../utils/responsive.dart';

enum _QuickActionsViewStyle {
  grid,
  orbit,
  verticalOrbit,
  galaxy,
  zigzag,
  star,
  spiral,
  wave,
  circle,
  list,
}

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> transactions = [];
  bool _friendToastShown = false;
  bool loading = true;
  int _imageRefreshKey = 0;
  final ScrollController _scrollController = ScrollController();
  final Random _adRandom = Random();
  Timer? _adTimer;
  bool _adDialogOpen = false;
  int _unreadUpdatesCount = 0;
  int _adsShownThisSession = 0;
  DateTime? _lastAdShownAt;

  bool _hasRatedApp = false;
  bool _ratingDialogShown = false;
  bool _useCompactTransactionOptions = true;
  _QuickActionsViewStyle _quickActionsViewStyle = _QuickActionsViewStyle.grid;
  AnimationController? _quickActionsRotationController;

  static const Set<_QuickActionsViewStyle> _animatedQuickActionStyles = {
    _QuickActionsViewStyle.orbit,
    _QuickActionsViewStyle.verticalOrbit,
    _QuickActionsViewStyle.galaxy,
    _QuickActionsViewStyle.star,
    _QuickActionsViewStyle.spiral,
    _QuickActionsViewStyle.wave,
  };
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _sectionKeys = {
    'quick_transactions': GlobalKey(),
    'transactions': GlobalKey(),
    'your_transactions': GlobalKey(),
    'analytics': GlobalKey(),
    'group_transaction': GlobalKey(),
    'view_group': GlobalKey(),
  };

  final List<Map<String, dynamic>> _carouselItems = [
    {
      'icon': Icons.account_balance_wallet,
      'label': 'Balance',
      'color': Colors.blue,
      'action': 'balance'
    },
    {
      'icon': Icons.history,
      'label': 'History',
      'color': Colors.orange,
      'action': 'history'
    },
    {
      'icon': Icons.favorite,
      'label': 'Favourites',
      'color': Colors.red,
      'action': 'favourites'
    },
    {
      'icon': Icons.local_offer,
      'label': 'Offers',
      'color': Colors.purple,
      'action': 'offers'
    },
    {
      'icon': Icons.share,
      'label': 'Refer',
      'color': Colors.green,
      'action': 'refer'
    },
    {
      'icon': Icons.star,
      'label': 'Ratings',
      'color': Colors.amber,
      'action': 'ratings'
    },
    {
      'icon': Icons.subscriptions,
      'label': 'Subscriptions',
      'color': Colors.red,
      'action': 'subscriptions'
    },
    {
      'icon': Icons.people,
      'label': 'Friends',
      'color': Colors.blue,
      'action': 'friends'
    },
    {
      'icon': Icons.card_giftcard,
      'label': 'Gift Cards',
      'color': Colors.green,
      'action': 'gift_cards'
    },
  ];

  Future<void> _openLenDenCoinsPage(int coins) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LenDenCoinsPage(coins: coins),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchTransactions();
    _fetchFriends();
    _fetchUnreadUpdatesCount();
    _checkAndShowRatingDialog();
    _quickActionsRotationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = Provider.of<SessionProvider>(context, listen: false);
      session.addListener(_onSessionChanged);
      _scheduleNextAd();
    });
  }

  @override
  void dispose() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    session.removeListener(_onSessionChanged);
    _scrollController.dispose();
    _searchController.dispose();
    _adTimer?.cancel();
    _quickActionsRotationController?.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    setState(() {
      _imageRefreshKey++;
    });
    _scheduleNextAd();
  }

  void _scheduleNextAd() {
    _adTimer?.cancel();
    if (!mounted) return;
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;
    if (_adsShownThisSession >= 3) return;
    if (_lastAdShownAt != null &&
        DateTime.now().difference(_lastAdShownAt!) < const Duration(minutes: 8)) {
      final remaining = const Duration(minutes: 8) -
          DateTime.now().difference(_lastAdShownAt!);
      _adTimer = Timer(remaining, _showRandomAdIfNeeded);
      return;
    }

    final delaySeconds = 45 + _adRandom.nextInt(76);
    _adTimer = Timer(Duration(seconds: delaySeconds), _showRandomAdIfNeeded);
  }

  Future<void> _showRandomAdIfNeeded() async {
    if (!mounted || _adDialogOpen) {
      _scheduleNextAd();
      return;
    }

    final session = Provider.of<SessionProvider>(context, listen: false);
    if (session.isSubscribed) return;

    try {
      final res = await ApiClient.get('/api/ads/random');
      final data = jsonDecode(res.body);
      final ad = data['ad'];
      if (!mounted || ad == null) {
        _scheduleNextAd();
        return;
      }

      _adDialogOpen = true;
      _adsShownThisSession += 1;
      _lastAdShownAt = DateTime.now();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UserAdPopupDialog(
          ad: Map<String, dynamic>.from(ad),
        ),
      );
    } catch (_) {
      // ignore ad failures quietly
    } finally {
      _adDialogOpen = false;
      if (mounted) {
        _scheduleNextAd();
      }
    }
  }

  Future<void> _fetchUnreadUpdatesCount() async {
    try {
      final res = await ApiClient.get('/api/app-updates');
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final updates = (data['updates'] as List? ?? const []);
      final unread = updates.where((item) {
        if (item is! Map) return false;
        return item['isRead'] != true;
      }).length;
      if (!mounted) return;
      setState(() => _unreadUpdatesCount = unread);
    } catch (_) {}
  }

  void _performSearch(String query) {
    if (query.isEmpty) return;

    final lowerQuery = query.toLowerCase();
    String? matchedSection;

    if (lowerQuery.contains('quick') || lowerQuery.contains('transaction')) {
      matchedSection = 'quick_transactions';
    } else if (lowerQuery.contains('create') ||
        lowerQuery.contains('transaction')) {
      matchedSection = 'transactions';
    } else if (lowerQuery.contains('your') || lowerQuery.contains('detail')) {
      matchedSection = 'your_transactions';
    } else if (lowerQuery.contains('analytic') ||
        lowerQuery.contains('visual')) {
      matchedSection = 'analytics';
    } else if (lowerQuery.contains('group') && lowerQuery.contains('create')) {
      matchedSection = 'group_transaction';
    } else if (lowerQuery.contains('group') && lowerQuery.contains('view')) {
      matchedSection = 'view_group';
    }

    if (matchedSection != null &&
        _sectionKeys[matchedSection]?.currentContext != null) {
      Scrollable.ensureVisible(
        _sectionKeys[matchedSection]!.currentContext!,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> fetchTransactions() async {
    setState(() => loading = true);
    final res = await ApiClient.get('/api/transactions/me');
    setState(() {
      transactions = res.statusCode == 200
          ? List<Map<String, dynamic>>.from(jsonDecode(res.body))
          : [];
      loading = false;
    });
  }

  Future<void> _fetchFriends() async {
    try {
      final results = await Future.wait([
        ApiClient.get('/api/friends'),
        ApiClient.get('/api/friends/requests'),
      ]);
      final res = results[0];
      final reqRes = results[1];
      if (res.statusCode == 200) {
        // Keep the request warm-up so the friends module data is available.
      }
      if (reqRes.statusCode == 200) {
        final data = jsonDecode(reqRes.body);
        final pending = (data['incoming'] as List? ?? []).length;
        if (pending > 0 && !_friendToastShown && mounted) {
          _friendToastShown = true;
          ElegantNotification.info(
            title: Text('Friend Request'),
            description: Text('You have $pending pending request(s).'),
            action: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsPage()),
                );
              },
              child: Text('View', style: TextStyle(color: Colors.blue)),
            ),
          ).show(context);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> showTransactionForm() async {
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
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TransactionPage(useCoins: true)));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionPage()));
  }

  ImageProvider _getUserAvatar() {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final user = session.user;
    final gender = user?['gender'] ?? 'Other';
    final imageUrl = user?['profileImage'];

    if (imageUrl != null &&
        imageUrl is String &&
        imageUrl.trim().isNotEmpty &&
        imageUrl != 'null') {
      final cacheBustingUrl =
          '$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      return NetworkImage(cacheBustingUrl);
    } else {
      return AssetImage(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
      );
    }
  }

  Future<void> _checkAndShowRatingDialog() async {
    try {
      final res = await ApiClient.get('/api/rating/my');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _hasRatedApp = data['rating'] != null;
        });
        if (!_hasRatedApp &&
            !_ratingDialogShown &&
            (_adRandom.nextInt(3) == 0)) {
          _ratingDialogShown = true;
          Future.delayed(Duration(milliseconds: 500), () {
            if (mounted) _showAppRatingDialog();
          });
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }

  void _showAppRatingDialog() {
    int _selectedStars = 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
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
              padding: EdgeInsets.all(ctx.sw(22)),
              decoration: BoxDecoration(
                color: const Color(0xFFFCE4EC),
                borderRadius: BorderRadius.circular(20),
              ),
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: AppColors.cyan, size: ctx.sp(44)),
                      SizedBox(height: ctx.sh(10)),
                      Text(
                        'Rate Our App!',
                        style: TextStyle(
                          fontSize: ctx.sp(20),
                          fontWeight: FontWeight.bold,
                          color: AppColors.cyan,
                        ),
                      ),
                      SizedBox(height: ctx.sh(8)),
                      Text(
                        'Your feedback helps us improve.\nHow would you rate your experience?',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: ctx.sp(15), color: Colors.grey[700]),
                      ),
                      SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (i) {
                          return IconButton(
                            icon: Stack(
                              children: <Widget>[
                                Icon(
                                  Icons.star,
                                  color: i < _selectedStars
                                      ? Colors.amber
                                      : Colors.grey[300],
                                  size: 36,
                                ),
                                Icon(
                                  Icons.star_border,
                                  color: Colors.black,
                                  size: 36,
                                ),
                              ],
                            ),
                            onPressed: () {
                              setState(() => _selectedStars = i + 1);
                            },
                          );
                        }),
                      ),
                      SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text('Close',
                                style: TextStyle(
                                    color: Colors.grey[700],
                                    fontWeight: FontWeight.bold)),
                          ),
                          ElevatedButton(
                            onPressed: _selectedStars > 0
                                ? () async {
                                    final res = await ApiClient.post(
                                      '/api/rating',
                                      body: {'rating': _selectedStars},
                                    );
                                    if (res.statusCode == 200) {
                                      setState(() {
                                        _hasRatedApp = true;
                                      });
                                      Navigator.of(ctx).pop();
                                      _showThankYouDialog();
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Failed to submit rating.')),
                                      );
                                    }
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                            child: Text('Submit',
                                style: TextStyle(
                                    color: _selectedStars > 0
                                        ? Colors.black
                                        : Colors.grey[600],
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _showThankYouDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: EdgeInsets.all(ctx.sw(26)),
          decoration: BoxDecoration(
            color: const Color(0xFFE0F7FA),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.cyan.withValues(alpha: 0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration, color: AppColors.cyan, size: ctx.sp(52)),
              SizedBox(height: ctx.sh(14)),
              Text(
                'Thank You for Rating!',
                style: TextStyle(
                  fontSize: ctx.sp(22),
                  fontWeight: FontWeight.bold,
                  color: AppColors.cyan,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ctx.sh(10)),
              Text(
                'Your feedback means a lot to us.\nWe appreciate your support!',
                style: TextStyle(
                  fontSize: ctx.sp(15),
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ctx.sh(20)),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(
                      horizontal: ctx.sw(28), vertical: ctx.sh(12)),
                ),
                child: Text(
                  'Continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: ctx.sp(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleCarouselAction(String action) {
    switch (action) {
      case 'balance':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => AnalyticsPage()));
        break;
      case 'history':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => ActivityPage()));
        break;
      case 'favourites':
        _showFavouritesDialog();
        break;
      case 'offers':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserOffersPage()),
        );
        break;
      case 'refer':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReferralPage()),
        );
        break;
      case 'ratings':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const RatingsPage()));
        break;
      case 'subscriptions':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SubscriptionsPage()));
        break;
      case 'friends':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FriendsPage()),
        );
        break;
      case 'gift_cards':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GiftCardPage(),
          ),
        );
        break;
    }
  }

  void _showFavouritesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 16,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  Color(0xFFE0F7FA),
                  Color(0xFFB2EBF2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    'Favourites',
                    style: TextStyle(
                      fontSize: context.sp(22),
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF00796B),
                    ),
                  ),
                ),
                _buildFavouriteItem(
                  context,
                  icon: Icons.shield,
                  text: 'Secure',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserTransactionsPage(
                          initialShowFavouritesOnly: true,
                        ),
                      ),
                    );
                  },
                ),
                _buildFavouriteItem(
                  context,
                  icon: Icons.group,
                  text: 'Groups',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GroupTransactionPage(
                          initialShowFavouritesOnly: true,
                        ),
                      ),
                    );
                  },
                ),
                _buildFavouriteItem(
                  context,
                  icon: Icons.bolt,
                  text: 'Quick',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuickTransactionsPage(
                          initialShowFavouritesOnly: true,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFavouriteItem(BuildContext context,
      {required IconData icon,
      required String text,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Color(0xFF00796B)),
            SizedBox(width: 20),
            Text(
              text,
              style: TextStyle(
                fontSize: context.sp(16),
                fontWeight: FontWeight.w500,
                color: const Color(0xFF004D40),
              ),
            ),
            Spacer(),
            Icon(Icons.arrow_forward_ios, color: Color(0xFF00796B), size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pushReplacementNamed(context, '/');
        }
      },
      child: Scaffold(
        drawer: Drawer(
          width: context.sw(200),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: AppColors.cyan),
                child: Text('Menu',
                    style: TextStyle(color: Colors.white, fontSize: context.sp(22))),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.pushNamed(context, '/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.timeline),
                title: const Text('Activity'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ActivityPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: const Text('Updates'),
                trailing: _unreadUpdatesCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_unreadUpdatesCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : null,
                onTap: () async {
                  Navigator.of(context).pop();
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UserUpdatesPage()),
                  );
                  if (mounted) {
                    _fetchUnreadUpdatesCount();
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.note),
                title: Text('Notes'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => NotesPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_center),
                title: const Text('Help & Support'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => HelpSupportPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.feedback),
                title: const Text('Feedback'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.pushNamed(context, '/feedback');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Logout'),
                onTap: () => _confirmLogout(context),
              ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFFF8F6FA),
        floatingActionButton: Container(
          width: context.sh(64),
          height: context.sh(64),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
            ],
            gradient: const LinearGradient(
              colors: [Color(0xFFFF6B00), Color(0xFFFFAB00)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _openQrScanner,
              splashColor: Colors.white24,
              child: Center(
                child: Icon(Icons.qr_code_scanner,
                    color: Colors.white, size: context.sh(28)),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 6,
          color: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          child: SizedBox(
            height: context.sh(78),
            child: Stack(
              children: [
                // S-curve wave background (vertical mirror of TopWaveClipper)
                Positioned.fill(
                  child: ClipPath(
                    clipper: _BottomNavWaveClipper(),
                    child: Container(color: const Color(0xFF009999)),
                  ),
                ),
                // Icons sit in the solid area at the bottom of the wave
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _navBarItem(Icons.settings_rounded, 'Settings', () {
                        Navigator.pushNamed(context, '/settings');
                      }),
                      _navBarItem(Icons.monetization_on_rounded, 'Coins', () {
                        final session = Provider.of<SessionProvider>(context,
                            listen: false);
                        _openLenDenCoinsPage(session.lenDenCoins ?? 0);
                      }, accent: const Color(0xFFFF9F45)),
                      SizedBox(width: context.sh(48)),
                      _navBarItem(Icons.account_balance_wallet_rounded,
                          'Wallet', () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LendenWalletPage()));
                      }, accent: const Color(0xFFFF9F45)),
                      _navBarItem(Icons.logout_rounded, 'Logout',
                          () => _confirmLogout(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Stack(
          children: [
            // Main content
            SafeArea(
              child: RefreshIndicator(
                onRefresh: () => Future.wait([
                  fetchTransactions(),
                  _fetchFriends(),
                  _fetchUnreadUpdatesCount(),
                ]),
                color: AppColors.cyan,
                child: SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: 80,
                  bottom: 100,
                  left: 0,
                  right: 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search Bar with tricolor border + view menu
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(27),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.orange,
                                    Colors.white,
                                    Colors.green
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.search,
                                      color: Colors.grey[600],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        onSubmitted: _performSearch,
                                        decoration: InputDecoration(
                                          hintText: 'Search sections...',
                                          hintStyle: TextStyle(
                                              color: Colors.grey[400]),
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 8),
                                        ),
                                        style:
                                            TextStyle(fontSize: context.sp(15)),
                                      ),
                                    ),
                                    if (_searchController.text.isNotEmpty)
                                      IconButton(
                                        icon: Icon(Icons.clear,
                                            color: Colors.grey[600], size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _searchController.clear();
                                          });
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.orange,
                                  Colors.white,
                                  Colors.green
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(Icons.more_vert,
                                    color: Color(0xFF00B4D8)),
                                tooltip: 'Quick Actions View',
                                onPressed: _showQuickActionsViewMenu,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Quick Actions — selectable view style
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: _buildQuickActionsView(),
                    ),

                    const SizedBox(height: 16),

                    // Counterparties entry card
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.white, Colors.green],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F7FA),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.people,
                                        color: AppColors.cyan),
                                    SizedBox(width: 8),
                                    Text(
                                      'Counterparties',
                                      style: TextStyle(
                                        fontSize: context.sp(16),
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.cyan,
                                      ),
                                    ),
                                  ],
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const CounterpartiesPage(),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.cyan,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('View'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transaction Options',
                            style: TextStyle(
                              fontSize: context.sp(16),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Open the main transaction tools from one place.',
                            style: TextStyle(
                              fontSize: context.sp(12),
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.orange,
                                    Colors.white,
                                    Colors.green
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTransactionLayoutChip(
                                      label: 'Single View',
                                      selected: !_useCompactTransactionOptions,
                                      onTap: () {
                                        setState(() {
                                          _useCompactTransactionOptions = false;
                                        });
                                      },
                                    ),
                                    _buildTransactionLayoutChip(
                                      label: 'Grid View',
                                      selected: _useCompactTransactionOptions,
                                      onTap: () {
                                        setState(() {
                                          _useCompactTransactionOptions = true;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _buildTransactionOptionsLayout(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ), // closes RefreshIndicator
            ), // closes SafeArea

            // Top blue wave
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: context.sh(78),
                  color: AppColors.cyan,
                ),
              ),
            ),

            // Header section
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Container(
                      height: 60,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back,
                                    color: Colors.black),
                                onPressed: () async {
                                  final popped =
                                      await Navigator.of(context).maybePop();
                                  if (!popped && context.mounted) {
                                    Navigator.pushReplacementNamed(
                                        context, '/');
                                  }
                                },
                              ),
                              Builder(
                                builder: (context) => IconButton(
                                  icon: const Icon(Icons.menu,
                                      color: Colors.black),
                                  onPressed: () =>
                                      Scaffold.of(context).openDrawer(),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Row(
                            children: [
                              NotificationIcon(),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.emoji_events,
                                    color: Color(0xFF005F73), size: 26),
                                tooltip: 'Leaderboard',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LeaderboardPage(),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Colors.orange,
                                      Colors.white,
                                      Colors.green
                                    ],
                                  ),
                                ),
                                child: GestureDetector(
                                  onTap: () async {
                                    try {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                const ProfilePage()),
                                      );
                                      final session =
                                          Provider.of<SessionProvider>(context,
                                              listen: false);
                                      await session.forceRefreshProfile();
                                      setState(() {
                                        _imageRefreshKey++;
                                      });
                                    } catch (_) {}
                                  },
                                  child: CircleAvatar(
                                    key: ValueKey(_imageRefreshKey),
                                    radius: 16,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _getUserAvatar(),
                                    onBackgroundImageError:
                                        (exception, stackTrace) {},
                                    child: _getUserAvatar() is AssetImage
                                        ? Icon(
                                            Icons.person,
                                            color: Colors.grey[400],
                                            size: 20,
                                          )
                                        : null,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<Map<String, dynamic>> _quickActionsViewOptions = [
    {
      'style': _QuickActionsViewStyle.grid,
      'label': 'Grid',
      'icon': Icons.grid_view_rounded,
    },
    {
      'style': _QuickActionsViewStyle.orbit,
      'label': 'Orbit',
      'icon': Icons.circle_outlined,
    },
    {
      'style': _QuickActionsViewStyle.verticalOrbit,
      'label': 'Vertical Orbit',
      'icon': Icons.swap_vert_circle_outlined,
    },
    {
      'style': _QuickActionsViewStyle.galaxy,
      'label': 'Galaxy',
      'icon': Icons.blur_circular,
    },
    {
      'style': _QuickActionsViewStyle.zigzag,
      'label': 'Zig Zag',
      'icon': Icons.show_chart_rounded,
    },
    {
      'style': _QuickActionsViewStyle.star,
      'label': 'Star',
      'icon': Icons.star_rate_rounded,
    },
    {
      'style': _QuickActionsViewStyle.spiral,
      'label': 'Spiral',
      'icon': Icons.cyclone_rounded,
    },
    {
      'style': _QuickActionsViewStyle.wave,
      'label': 'Wave',
      'icon': Icons.waves_rounded,
    },
    {
      'style': _QuickActionsViewStyle.circle,
      'label': 'Circle',
      'icon': Icons.radio_button_unchecked,
    },
    {
      'style': _QuickActionsViewStyle.list,
      'label': 'List',
      'icon': Icons.view_list_rounded,
    },
  ];

  void _setQuickActionsViewStyle(_QuickActionsViewStyle style) {
    setState(() => _quickActionsViewStyle = style);
    if (_animatedQuickActionStyles.contains(style)) {
      _quickActionsRotationController?.repeat();
    } else {
      _quickActionsRotationController?.stop();
    }
  }

  void _showQuickActionsViewMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(23),
              ),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF00B4D8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.dashboard_customize,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text('Quick Actions View',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how the 9 quick actions are displayed.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _quickActionsViewOptions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    itemBuilder: (context, i) {
                      final option = _quickActionsViewOptions[i];
                      final style =
                          option['style'] as _QuickActionsViewStyle;
                      final selected = style == _quickActionsViewStyle;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _setQuickActionsViewStyle(style);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: selected
                                ? const LinearGradient(
                                    colors: [
                                      Colors.orange,
                                      Colors.white,
                                      Colors.green
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            border: selected
                                ? null
                                : Border.all(color: Colors.grey[300]!),
                          ),
                          padding: EdgeInsets.all(selected ? 2 : 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFE0F7FA)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(option['icon'] as IconData,
                                    color: selected
                                        ? const Color(0xFF00B4D8)
                                        : Colors.grey[600],
                                    size: 26),
                                const SizedBox(height: 6),
                                Text(
                                  option['label'] as String,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: selected
                                        ? const Color(0xFF00B4D8)
                                        : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsView() {
    switch (_quickActionsViewStyle) {
      case _QuickActionsViewStyle.orbit:
        return _buildOrbitQuickActions();
      case _QuickActionsViewStyle.verticalOrbit:
        return _buildVerticalOrbitQuickActions();
      case _QuickActionsViewStyle.galaxy:
        return _buildGalaxyQuickActions();
      case _QuickActionsViewStyle.zigzag:
        return _buildZigZagQuickActions();
      case _QuickActionsViewStyle.star:
        return _buildStarQuickActions();
      case _QuickActionsViewStyle.spiral:
        return _buildSpiralQuickActions();
      case _QuickActionsViewStyle.wave:
        return _buildWaveQuickActions();
      case _QuickActionsViewStyle.circle:
        return _buildCircleQuickActions();
      case _QuickActionsViewStyle.list:
        return _buildListQuickActions();
      case _QuickActionsViewStyle.grid:
        return _buildGridQuickActions();
    }
  }

  Widget _buildGridQuickActions() {
    return Column(
      children: [
        for (int row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (col) {
              final index = row * 3 + col;
              final item = _carouselItems[index];
              return _buildQuickActionItem(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                color: item['color'] as Color,
                onTap: () => _handleCarouselAction(item['action'] as String),
                index: index,
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildOrbitQuickActions() {
    return SizedBox(
      height: 150,
      child: AnimatedBuilder(
        animation: _quickActionsRotationController!,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(_carouselItems.length, (index) {
              final item = _carouselItems[index];
              final angle = (index / _carouselItems.length) * 2 * pi +
                  (_quickActionsRotationController!.value * 2 * pi);
              final x = cos(angle) * 130;
              final y = sin(angle) * 45;
              final scale = 0.7 + (sin(angle) + 1) / 2 * 0.5;

              return Transform(
                transform: Matrix4.identity()
                  ..translate(x, y)
                  ..scale(scale),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (sin(angle) + 1) / 2 * 0.8 + 0.2,
                  child: _buildQuickActionItem(
                    icon: item['icon'] as IconData,
                    label: item['label'] as String,
                    color: item['color'] as Color,
                    onTap: () =>
                        _handleCarouselAction(item['action'] as String),
                    index: index,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildVerticalOrbitQuickActions() {
    return SizedBox(
      height: 220,
      child: AnimatedBuilder(
        animation: _quickActionsRotationController!,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(_carouselItems.length, (index) {
              final item = _carouselItems[index];
              final angle = (index / _carouselItems.length) * 2 * pi +
                  (_quickActionsRotationController!.value * 2 * pi);
              final x = cos(angle) * 45;
              final y = sin(angle) * 95;
              final scale = 0.7 + (cos(angle) + 1) / 2 * 0.5;

              return Transform(
                transform: Matrix4.identity()
                  ..translate(x, y)
                  ..scale(scale),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (cos(angle) + 1) / 2 * 0.8 + 0.2,
                  child: _buildQuickActionItem(
                    icon: item['icon'] as IconData,
                    label: item['label'] as String,
                    color: item['color'] as Color,
                    onTap: () =>
                        _handleCarouselAction(item['action'] as String),
                    index: index,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildGalaxyQuickActions() {
    const ringRadii = [45.0, 85.0, 125.0];
    const ringSpeeds = [1.0, -0.7, 0.5];
    return SizedBox(
      height: 270,
      child: AnimatedBuilder(
        animation: _quickActionsRotationController!,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(_carouselItems.length, (index) {
              final item = _carouselItems[index];
              final ring = index ~/ 3;
              final posInRing = index % 3;
              final angle = (posInRing / 3) * 2 * pi +
                  (_quickActionsRotationController!.value *
                      2 *
                      pi *
                      ringSpeeds[ring]);
              final radius = ringRadii[ring];
              final x = cos(angle) * radius;
              final y = sin(angle) * radius * 0.55;
              final scale = 0.65 + (sin(angle) + 1) / 2 * 0.35;

              return Transform(
                transform: Matrix4.identity()
                  ..translate(x, y)
                  ..scale(scale),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: (sin(angle) + 1) / 2 * 0.7 + 0.3,
                  child: _buildQuickActionItem(
                    icon: item['icon'] as IconData,
                    label: item['label'] as String,
                    color: item['color'] as Color,
                    onTap: () =>
                        _handleCarouselAction(item['action'] as String),
                    index: index,
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildZigZagQuickActions() {
    return SizedBox(
      height: 140,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(_carouselItems.length, (index) {
            final item = _carouselItems[index];
            final offsetUp = index.isEven;
            return Padding(
              padding: EdgeInsets.only(
                right: 18,
                top: offsetUp ? 0 : 40,
                bottom: offsetUp ? 40 : 0,
              ),
              child: _buildQuickActionItem(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                color: item['color'] as Color,
                onTap: () => _handleCarouselAction(item['action'] as String),
                index: index,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildStarQuickActions() {
    return SizedBox(
      height: 240,
      child: AnimatedBuilder(
        animation: _quickActionsRotationController!,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(_carouselItems.length, (index) {
              final item = _carouselItems[index];
              final baseAngle = (index / _carouselItems.length) * 2 * pi;
              final angle = baseAngle +
                  (_quickActionsRotationController!.value * 2 * pi * 0.3);
              final radius = index.isEven ? 130.0 : 75.0;
              final x = cos(angle) * radius;
              final y = sin(angle) * radius;

              return Transform.translate(
                offset: Offset(x, y),
                child: _buildQuickActionItem(
                  icon: item['icon'] as IconData,
                  label: item['label'] as String,
                  color: item['color'] as Color,
                  onTap: () =>
                      _handleCarouselAction(item['action'] as String),
                  index: index,
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildSpiralQuickActions() {
    return SizedBox(
      height: 260,
      child: AnimatedBuilder(
        animation: _quickActionsRotationController!,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(_carouselItems.length, (index) {
              final item = _carouselItems[index];
              final radius = 18.0 + index * 14.0;
              final angle = index * (2 * pi / 3.6) +
                  (_quickActionsRotationController!.value * 2 * pi * 0.4);
              final x = cos(angle) * radius;
              final y = sin(angle) * radius;
              final scale = 0.6 + (index / _carouselItems.length) * 0.5;

              return Transform(
                transform: Matrix4.identity()
                  ..translate(x, y)
                  ..scale(scale),
                alignment: Alignment.center,
                child: _buildQuickActionItem(
                  icon: item['icon'] as IconData,
                  label: item['label'] as String,
                  color: item['color'] as Color,
                  onTap: () =>
                      _handleCarouselAction(item['action'] as String),
                  index: index,
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildWaveQuickActions() {
    return SizedBox(
      height: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = constraints.maxWidth / _carouselItems.length;
          return AnimatedBuilder(
            animation: _quickActionsRotationController!,
            builder: (context, child) {
              return Stack(
                children: List.generate(_carouselItems.length, (index) {
                  final item = _carouselItems[index];
                  final phase = _quickActionsRotationController!.value * 2 * pi;
                  final y = sin(index * 0.9 + phase) * 24;
                  return Positioned(
                    left: spacing * index + spacing / 2 - 32,
                    top: 50 + y,
                    child: _buildQuickActionItem(
                      icon: item['icon'] as IconData,
                      label: item['label'] as String,
                      color: item['color'] as Color,
                      onTap: () =>
                          _handleCarouselAction(item['action'] as String),
                      index: index,
                    ),
                  );
                }),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCircleQuickActions() {
    return SizedBox(
      height: 230,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(_carouselItems.length, (index) {
          final item = _carouselItems[index];
          final angle = (index / _carouselItems.length) * 2 * pi - pi / 2;
          final x = cos(angle) * 110;
          final y = sin(angle) * 110;
          return Transform.translate(
            offset: Offset(x, y),
            child: _buildQuickActionItem(
              icon: item['icon'] as IconData,
              label: item['label'] as String,
              color: item['color'] as Color,
              onTap: () => _handleCarouselAction(item['action'] as String),
              index: index,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildListQuickActions() {
    return Column(
      children: List.generate(_carouselItems.length, (index) {
        final item = _carouselItems[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: GestureDetector(
            onTap: () => _handleCarouselAction(item['action'] as String),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (item['color'] as Color).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(item['icon'] as IconData,
                        color: item['color'] as Color, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item['label'] as String,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[400]),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required int index,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(2), // Border width
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getBoxColor(index),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: context.sp(22)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: context.sp(10),
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTransactionOptionCards() {
    return [
      _buildDashboardOptionCard(
        key: _sectionKeys['quick_transactions'],
        icon: Icons.flash_on,
        title: 'Quick Transactions',
        subtitle: 'Fast entries and shortcuts',
        valueLabel: 'Quick',
        iconColor: Colors.amber,
        fillColor: _getBoxColor(0),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuickTransactionsPage(),
          ),
        ),
      ),
      _buildDashboardOptionCard(
        key: _sectionKeys['transactions'],
        icon: Icons.swap_horiz,
        title: 'Create Secure Transactions',
        subtitle: 'Start a secure transaction',
        valueLabel: 'Create',
        iconColor: Colors.teal,
        fillColor: _getBoxColor(1),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: showTransactionForm,
      ),
      _buildDashboardOptionCard(
        key: _sectionKeys['your_transactions'],
        icon: Icons.account_balance_wallet,
        title: 'View Secure Transactions',
        subtitle: 'See all secure records',
        valueLabel: 'View',
        iconColor: Colors.blue,
        fillColor: _getBoxColor(2),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserTransactionsPage(),
          ),
        ),
      ),
      _buildDashboardOptionCard(
        key: _sectionKeys['analytics'],
        icon: Icons.analytics,
        title: 'Analytics',
        subtitle: 'Secure and group insights',
        valueLabel: 'Stats',
        iconColor: AppColors.cyan,
        fillColor: _getBoxColor(3),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnalyticsPage(),
          ),
        ),
      ),
      _buildDashboardOptionCard(
        key: _sectionKeys['group_transaction'],
        icon: Icons.group,
        title: 'Create Group',
        subtitle: 'Start a shared expense group',
        valueLabel: 'Create',
        iconColor: Colors.deepPurple,
        fillColor: _getBoxColor(4),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupTransactionPage(),
          ),
        ),
      ),
      _buildDashboardOptionCard(
        key: _sectionKeys['view_group'],
        icon: Icons.visibility,
        title: 'View Groups',
        subtitle: 'Open your group transactions',
        valueLabel: 'View',
        iconColor: Colors.orange,
        fillColor: _getBoxColor(5),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewGroupTransactionsPage(),
          ),
        ),
      ),
    ];
  }

  Widget _buildTransactionOptionsLayout() {
    final cards = _buildTransactionOptionCards();

    if (_useCompactTransactionOptions) {
      return GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.1,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cards,
      );
    }

    return Column(
      children: cards
          .map(
            (card) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SizedBox(
                width: double.infinity,
                height: 150,
                child: card,
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTransactionLayoutChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? AppColors.cyan : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: context.sp(12),
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.cyan,
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardOptionCard({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required String valueLabel,
    required Color iconColor,
    required Color fillColor,
    required bool showSubtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: context.sp(16),
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(11),
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openQrScanner() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const QrScannerPage()));
  }

  Widget _navBarItem(IconData icon, String label, VoidCallback onTap,
      {Color? accent}) {
    final Color base = accent ?? AppColors.cyan;
    final Color dark = Color.lerp(base, const Color(0xFF001A2E), 0.4)!;
    return Tooltip(
      message: label,
      // Outer tricolor ring — identical to profile pic border
      child: Container(
        width: 36,
        height: 36,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [dark, base],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              splashColor: Colors.white30,
              child: Center(child: Icon(icon, size: 16, color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    bool isLoggingOut = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Wave header + floating icon badge
                Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      child: ClipPath(
                        clipper: LogoutWaveClipper(),
                        child: Container(
                          height: context.sh(80),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0077B6), AppColors.cyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Floating logout icon — sits at wave/content boundary
                    Positioned(
                      bottom: -28,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE53935), Color(0xFFFF7043)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.logout_rounded,
                            color: Colors.white, size: 26),
                      ),
                    ),
                  ],
                ),
                // Content area
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      context.sw(24), context.sh(42), context.sw(24), context.sh(24)),
                  child: Column(
                    children: [
                      if (isLoggingOut) ...[
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.cyan),
                        ),
                        SizedBox(height: context.sh(16)),
                        Text('Logging out...',
                            style: TextStyle(
                              fontSize: context.sp(16),
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            )),
                      ] else ...[
                        Text('Are you sure?',
                            style: TextStyle(
                              fontSize: context.sp(22),
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            )),
                        SizedBox(height: context.sh(8)),
                        Text(
                          'You will be logged out of\nyour account.',
                          style: TextStyle(
                            fontSize: context.sp(14),
                            color: Colors.grey[500],
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: context.sh(28)),
                        Row(
                          children: [
                            // Cancel button
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.cyan,
                                  side: const BorderSide(
                                      color: AppColors.cyan, width: 1.5),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  padding: EdgeInsets.symmetric(
                                      vertical: context.sh(14)),
                                ),
                                child: Text('Cancel',
                                    style: TextStyle(
                                        fontSize: context.sp(14),
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                            SizedBox(width: context.sw(12)),
                            // Logout button — red gradient
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE53935),
                                      Color(0xFFFF7043)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: () async {
                                    setState(() => isLoggingOut = true);
                                    await Provider.of<SessionProvider>(context,
                                            listen: false)
                                        .logout();
                                    Navigator.of(context).pop(true);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    padding: EdgeInsets.symmetric(
                                        vertical: context.sh(14)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.logout_rounded, size: 18),
                                      const SizedBox(width: 6),
                                      Text('Logout',
                                          style: TextStyle(
                                              fontSize: context.sp(14),
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.25, size.height, size.width * 0.5, size.height * 0.7);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.4, size.width, size.height * 0.7);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Vertical mirror of TopWaveClipper — wave edge at top, solid teal below
class _BottomNavWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.3);
    path.quadraticBezierTo(
        size.width * 0.25, 0, size.width * 0.5, size.height * 0.3);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.6, size.width, size.height * 0.3);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BottomNavWaveClipper oldClipper) => false;
}

class LogoutWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.8, size.width * 0.5, size.height);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.8, 0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

Color _getBoxColor(int index) {
  // Returns alternating soft colors for visual variety
  final colors = [
    Color(0xFFE8F5E9), // Soft green
    Color(0xFFFFF8E7), // Soft cream
    Color(0xFFF3E5F5), // Soft purple
    Color(0xFFE8F5F7), // Soft blue
    Color(0xFFFCE4EC), // Soft pink
    Color(0xFFFFF3E0), // Soft orange
  ];
  return colors[index % colors.length];
}
