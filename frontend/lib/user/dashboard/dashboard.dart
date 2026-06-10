import 'package:flutter/material.dart';
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
import 'package:elegant_notification/elegant_notification.dart';
import '../../utils/responsive.dart';

class UserDashboardPage extends StatefulWidget {
  const UserDashboardPage({super.key});

  @override
  State<UserDashboardPage> createState() => _UserDashboardPageState();
}

class _UserDashboardPageState extends State<UserDashboardPage>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> transactions = [];
  int _pendingFriendRequests = 0;
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
      final res = await ApiClient.get('/api/friends');
      final reqRes = await ApiClient.get('/api/friends/requests');
      if (res.statusCode == 200) {
        // Keep the request warm-up so the friends module data is available.
      }
      if (reqRes.statusCode == 200) {
        final data = jsonDecode(reqRes.body);
        final pending = (data['incoming'] as List? ?? []).length;
        setState(() {
          _pendingFriendRequests = pending;
        });
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

  void showTransactionForm() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => TransactionPage()));

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
    final session = Provider.of<SessionProvider>(context, listen: false);
    try {
      final res = await ApiClient.get('/api/rating/my');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _hasRatedApp = data['rating'] != null;
        });
        if (!_hasRatedApp &&
            !_ratingDialogShown &&
            (DateTime.now().millisecondsSinceEpoch % 3 == 0)) {
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
                      Icon(Icons.star, color: const Color(0xFF00B4D8), size: ctx.sp(44)),
                      SizedBox(height: ctx.sh(10)),
                      Text(
                        'Rate Our App!',
                        style: TextStyle(
                          fontSize: ctx.sp(20),
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF00B4D8),
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
                color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration, color: const Color(0xFF00B4D8), size: ctx.sp(52)),
              SizedBox(height: ctx.sh(14)),
              Text(
                'Thank You for Rating!',
                style: TextStyle(
                  fontSize: ctx.sp(22),
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00B4D8),
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
                  backgroundColor: const Color(0xFF00B4D8),
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
                  icon: Icons.person,
                  text: 'Transaction',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserTransactionsPage(),
                        settings: RouteSettings(
                          arguments: {'showFavouritesOnly': true},
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
                        builder: (_) => GroupTransactionPage(),
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
    final session = Provider.of<SessionProvider>(context, listen: false);
    final userId = session.user?['_id'];

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
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
                decoration: const BoxDecoration(color: Color(0xFF00B4D8)),
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
                leading: const Icon(Icons.list_alt),
                title: const Text('Transaction Details'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => UserTransactionsPage()));
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
                leading: const Icon(Icons.star),
                title: const Text('Ratings'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RatingsPage()));
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
                leading: const Icon(Icons.subscriptions),
                title: const Text('Subscriptions'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SubscriptionsPage()));
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
        body: Stack(
          children: [
            // Main content
            SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: 80,
                  bottom: 100,
                  left: 0,
                  right: 0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Search Bar with tricolor border
                    Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(27),
                        gradient: const LinearGradient(
                          colors: [Colors.orange, Colors.white, Colors.green],
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
                                  hintStyle: TextStyle(color: Colors.grey[400]),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                ),
                                style: TextStyle(fontSize: context.sp(15)),
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

                    // Quick Actions Grid
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildQuickActionItem(
                                icon: _carouselItems[0]['icon'] as IconData,
                                label: _carouselItems[0]['label'] as String,
                                color: _carouselItems[0]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[0]['action'] as String),
                                index: 0,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[1]['icon'] as IconData,
                                label: _carouselItems[1]['label'] as String,
                                color: _carouselItems[1]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[1]['action'] as String),
                                index: 1,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[2]['icon'] as IconData,
                                label: _carouselItems[2]['label'] as String,
                                color: _carouselItems[2]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[2]['action'] as String),
                                index: 2,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildQuickActionItem(
                                icon: _carouselItems[3]['icon'] as IconData,
                                label: _carouselItems[3]['label'] as String,
                                color: _carouselItems[3]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[3]['action'] as String),
                                index: 3,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[4]['icon'] as IconData,
                                label: _carouselItems[4]['label'] as String,
                                color: _carouselItems[4]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[4]['action'] as String),
                                index: 4,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[5]['icon'] as IconData,
                                label: _carouselItems[5]['label'] as String,
                                color: _carouselItems[5]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[5]['action'] as String),
                                index: 5,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildQuickActionItem(
                                icon: _carouselItems[6]['icon'] as IconData,
                                label: _carouselItems[6]['label'] as String,
                                color: _carouselItems[6]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[6]['action'] as String),
                                index: 6,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[7]['icon'] as IconData,
                                label: _carouselItems[7]['label'] as String,
                                color: _carouselItems[7]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[7]['action'] as String),
                                index: 7,
                              ),
                              _buildQuickActionItem(
                                icon: _carouselItems[8]['icon'] as IconData,
                                label: _carouselItems[8]['label'] as String,
                                color: _carouselItems[8]['color'] as Color,
                                onTap: () => _handleCarouselAction(
                                    _carouselItems[8]['action'] as String),
                                index: 8,
                              ),
                            ],
                          ),
                        ],
                      ),
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
                                        color: Color(0xFF00B4D8)),
                                    SizedBox(width: 8),
                                    Text(
                                      'Counterparties',
                                      style: TextStyle(
                                        fontSize: context.sp(16),
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF00B4D8),
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
                                    backgroundColor: const Color(0xFF00B4D8),
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
            ),

            // Top blue wave
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: TopWaveClipper(),
                child: Container(
                  height: context.sh(78),
                  color: const Color(0xFF00B4D8),
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
                          Row(
                            children: [
                              NotificationIcon(),
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
                              GestureDetector(
                                onTap: () {
                                  final session = Provider.of<SessionProvider>(
                                      context,
                                      listen: false);
                                  _openLenDenCoinsPage(
                                      session.lenDenCoins ?? 0);
                                },
                                child: Icon(Icons.monetization_on,
                                    color: Colors.amber, size: 28),
                              ),
                              IconButton(
                                icon: const Icon(Icons.account_balance_wallet_rounded,
                                    color: Color(0xFF023E8A), size: 26),
                                tooltip: 'LenDen Wallet',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LendenWalletPage(),
                                    ),
                                  );
                                },
                              ),
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
                              IconButton(
                                icon: const Icon(Icons.logout,
                                    color: Colors.black, size: 28),
                                tooltip: 'Logout',
                                onPressed: () => _confirmLogout(context),
                              ),
                            ],
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
        iconColor: const Color(0xFF00B4D8),
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
          color: selected ? const Color(0xFF00B4D8) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: context.sp(12),
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF00B4D8),
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
            padding: const EdgeInsets.all(16),
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

  Future<void> _confirmLogout(BuildContext context) async {
    bool isLoggingOut = false;

    final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
              builder: (context, setState) => Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: context.sh(75),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: ClipPath(
                          clipper: LogoutWaveClipper(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF00B4D8), Color(0xFF0096CC)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(context.sw(22)),
                        child: Column(
                          children: [
                            if (isLoggingOut) ...[
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFF00B4D8),
                                ),
                              ),
                              SizedBox(height: context.sh(16)),
                              Text(
                                'Logging out...',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: context.sp(16),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ] else ...[
                              Text(
                                'Are you sure?',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: context.sp(22),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: context.sh(14)),
                              Text(
                                'Do you want to logout?',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: context.sp(15),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 32),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: Container(
                                      margin: EdgeInsets.only(right: 8),
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(false),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey[100],
                                          foregroundColor: Colors.grey[700],
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            side: BorderSide(
                                                color: Colors.grey[300]!),
                                          ),
                                          padding: EdgeInsets.symmetric(
                                              vertical: 16),
                                          elevation: 0,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.close, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'NO',
                                              style: TextStyle(
                                                fontSize: context.sp(15),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      margin: EdgeInsets.only(left: 8),
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          setState(() {
                                            isLoggingOut = true;
                                          });

                                          await Provider.of<SessionProvider>(
                                                  context,
                                                  listen: false)
                                              .logout();

                                          Navigator.of(context).pop(true);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(0xFF00B4D8),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          padding: EdgeInsets.symmetric(
                                              vertical: 16),
                                          elevation: 2,
                                          shadowColor: Color(0xFF00B4D8)
                                              .withValues(alpha: 0.3),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.logout, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'YES',
                                              style: TextStyle(
                                                fontSize: context.sp(15),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
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
            ));

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
