import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import '../../utils/api_client.dart';
import '../transaction/secure_transactions/create_secure_transaction_page.dart';
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
import '../../widgets/app_widgets.dart';
import '../scanner/qr_scanner_page.dart';
import '../scanner/user_qr_page.dart';
import 'package:elegant_notification/elegant_notification.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/wave_widget.dart' show DeepTopWaveClipper;
import '../../widgets/avatar_action_sheet.dart';
import '../../widgets/birthday_banner.dart';
import '../reports/reports_page.dart';
import '../budget/budget_planning_page.dart';
import '../insights/smart_insights_page.dart';
import '../favorites/favorites_page.dart';
import 'widgets/dashboard_clipper.dart';
import 'widgets/dashboard_analytics_card.dart';
import 'widgets/dashboard_option_card.dart';
import '../community/community_page.dart';
import '../community/create_community_page.dart';
import '../../api_config.dart';
import 'widgets/dashboard_greeting_card.dart';

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
  bool _friendToastShown = false;
  int _imageRefreshKey = 0;
  ImageProvider? _cachedAvatarImage;
  int _lastAvatarKey = -1;
  final ScrollController _scrollController = ScrollController();
  final Random _adRandom = Random();
  Timer? _adTimer;
  bool _adDialogOpen = false;
  int _unreadUpdatesCount = 0;
  int _adsShownThisSession = 0;
  DateTime? _lastAdShownAt;

  late final String _greetingSubtitle;
  late final int _dailyTip;
  double? _netLent;
  double? _netBorrowed;
  List<Map<String, dynamic>> _savingsGoals = [];
  List<Map<String, dynamic>> _communities = [];
  bool _loadingCommunities = false;
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
    'savings_goals': GlobalKey(),
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

  String t(String key) => AppLocalizations.of(context).t(key);

  String _quickActionLabel(String action) {
    switch (action) {
      case 'balance':
        return t('balance');
      case 'history':
        return t('history_label');
      case 'favourites':
        return t('favourites_label');
      case 'offers':
        return t('offers');
      case 'refer':
        return t('refer_label');
      case 'ratings':
        return t('ratings_label');
      case 'subscriptions':
        return t('subscriptions_label');
      case 'friends':
        return t('friends');
      case 'gift_cards':
        return t('gift_cards_label');
      default:
        return action;
    }
  }

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
    final h = DateTime.now().hour;
    const _morningSubs    = ['Welcome Back','Rise & Shine','Have a Great Day','New Day','Fresh Start',"Let's Go",'Stay Focused','Good to See You'];
    const _afternoonSubs  = ['Keep Going','Stay Productive',"You're Doing Great",'Keep Smiling','Stay Motivated','Have Fun','Keep Growing'];
    const _eveningSubs    = ['Welcome Back','Relax Time','Wind Down','Unwind Now','Take It Easy','Evening Vibes','Enjoy Evening'];
    const _nightSubs      = ['Sleep Well','Rest Well','Sweet Dreams','See You Tomorrow','Good Rest','Recharge Time','Take Care'];
    final subs = h >= 5 && h < 12 ? _morningSubs : h >= 12 && h < 17 ? _afternoonSubs : h >= 17 && h < 21 ? _eveningSubs : _nightSubs;
    _greetingSubtitle = subs[Random().nextInt(subs.length)];
    _dailyTip = Random().nextInt(15);
    _fetchFriends();
    _fetchNetPosition();
    _fetchSavingsGoals();
    _fetchUnreadUpdatesCount();
    _loadCommunities();
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
    // Ads are a user-only feature â€” never show them to an admin session.
    if (session.role == 'admin') return;
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
    if (session.role == 'admin' || session.isSubscribed) return;

    try {
      final res = await ApiClient.get('/api/ads/random');
      if (res.statusCode != 200) {
        _scheduleNextAd();
        return;
      }
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

  static const _searchIndex = [
    // section scroll targets
    {'keys': ['quick', 'quick tx', 'lend', 'borrow', 'quick transaction'], 'section': 'quick_transactions', 'label': 'Quick Transactions', 'icon': 'flash'},
    {'keys': ['create transaction', 'new transaction', 'add transaction'], 'section': 'transactions', 'label': 'Create Transaction', 'icon': 'add'},
    {'keys': ['your transaction', 'my transaction', 'transaction history'], 'section': 'your_transactions', 'label': 'Your Transactions', 'icon': 'history'},
    {'keys': ['analytic', 'visual', 'chart', 'stat'], 'section': 'analytics', 'label': 'Analytics', 'icon': 'bar_chart'},
    {'keys': ['create group', 'new group', 'group expense', 'group transaction'], 'section': 'group_transaction', 'label': 'Group Transactions', 'icon': 'group'},
    {'keys': ['view group', 'my group', 'group list'], 'section': 'view_group', 'label': 'View Groups', 'icon': 'group_work'},
    {'keys': ['saving', 'goal', 'savings goal', 'target'], 'section': 'savings_goals', 'label': 'Savings Goals', 'icon': 'savings'},
    // page navigations
    {'keys': ['report', 'export', 'statement'], 'page': 'reports', 'label': 'Reports', 'icon': 'bar_chart'},
    {'keys': ['budget', 'limit', 'spending limit', 'budget plan'], 'page': 'budget', 'label': 'Budget Planning', 'icon': 'savings'},
    {'keys': ['insight', 'smart', 'ai', 'predict', 'tip'], 'page': 'insights', 'label': 'Smart Insights', 'icon': 'auto_awesome'},
    {'keys': ['wallet', 'pay', 'balance', 'money', 'transfer'], 'page': 'wallet', 'label': 'LenDen Wallet', 'icon': 'wallet'},
    {'keys': ['friend', 'contact', 'people', 'connection'], 'page': 'friends', 'label': 'Friends', 'icon': 'people'},
    {'keys': ['secure', 'loan', 'formal', 'interest', 'otp'], 'page': 'secure', 'label': 'Secure Transactions', 'icon': 'shield'},
    {'keys': ['scan', 'qr', 'camera', 'qr code'], 'page': 'scanner', 'label': 'QR Scanner', 'icon': 'qr_code_scanner'},
    {'keys': ['profile', 'account', 'settings', 'me'], 'page': 'profile', 'label': 'My Profile', 'icon': 'person'},
    {'keys': ['coin', 'reward', 'lenden coin'], 'page': 'coins', 'label': 'LenDen Coins', 'icon': 'monetization_on'},
    {'keys': ['offer', 'discount', 'deal', 'promo'], 'page': 'offers', 'label': 'Offers', 'icon': 'local_offer'},
    {'keys': ['notification', 'update', 'news'], 'page': 'updates', 'label': 'Updates', 'icon': 'notifications'},
  ];

  void _performSearch(String query) {
    setState(() => _searchController.clear());
    if (query.isEmpty) return;
    final q = query.toLowerCase();

    // Check section scroll targets first
    for (final item in _searchIndex) {
      if (item['section'] == null) continue;
      final keys = item['keys'] as List;
      if (keys.any((k) => q.contains(k.toString()) || k.toString().contains(q))) {
        final key = _sectionKeys[item['section'] as String];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(key!.currentContext!,
              duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
        }
        return;
      }
    }

    // Navigate to page
    for (final item in _searchIndex) {
      if (item['page'] == null) continue;
      final keys = item['keys'] as List;
      if (keys.any((k) => q.contains(k.toString()) || k.toString().contains(q))) {
        _navigateToPage(item['page'] as String);
        return;
      }
    }
  }

  void _navigateToPage(String page) {
    switch (page) {
      case 'reports':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage()));
      case 'budget':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetPlanningPage()))
            .then((_) => _fetchSavingsGoals());
      case 'insights':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartInsightsPage()));
      case 'wallet':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const LendenWalletPage()));
      case 'friends':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FriendsPage()));
      case 'secure':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserTransactionsPage()));
      case 'scanner':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerPage()));
      case 'profile':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
      case 'coins':
        _openLenDenCoinsPage(Provider.of<SessionProvider>(context, listen: false).lenDenCoins ?? 0);
      case 'offers':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserOffersPage()));
      case 'updates':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const UserUpdatesPage()));
    }
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
            title: Text(t('friend_request_title')),
            description: Text(
                '${t('you_have_label')} $pending ${t('pending_requests_suffix')}'),
            action: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsPage()),
                );
              },
              child: Text(t('view_label'), style: TextStyle(color: Colors.blue)),
            ),
          ).show(context);
        }
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _fetchNetPosition() async {
    try {
      final res = await ApiClient.get('/api/analytics/quick');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['analyticsSharing'] == false) return;
        setState(() {
          _netLent = (data['totalLent'] as num?)?.toDouble() ?? 0;
          _netBorrowed = (data['totalBorrowed'] as num?)?.toDouble() ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchSavingsGoals() async {
    try {
      final res = await ApiClient.get('/api/savings-goals');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final raw = jsonDecode(res.body);
        setState(() {
          _savingsGoals = List<Map<String, dynamic>>.from(
              raw is List ? raw : (raw['goals'] ?? []));
        });
      }
    } catch (_) {}
  }

  Future<void> _loadCommunities() async {
    if (!mounted) return;
    setState(() => _loadingCommunities = true);
    try {
      final res = await ApiClient.get('/api/communities');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _communities = List<Map<String, dynamic>>.from(data['communities'] ?? []));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingCommunities = false);
    }
  }

  Future<void> showTransactionForm() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    if (!session.hasFeature('secure_transactions')) {
      if (mounted) showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black26,
        builder: (_) => const PopScope(canPop: false, child: Center(child: CircularProgressIndicator())),
      );
      int? dailyRemaining;
      try {
        await Future.wait([
          session.loadFreebieCounts(),
          ApiClient.get('/api/limits/daily').then((res) {
            if (res.statusCode == 200) {
              final data = jsonDecode(res.body);
              dailyRemaining = data['limits']?['userTransactions']?['remaining'];
            }
          }),
        ]);
      } finally {
        if (mounted) Navigator.pop(context);
      }
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
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TransactionPage(useCoins: true)));
        return;
      }
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionPage()));
  }

  ImageProvider _getUserAvatar() {
    if (_imageRefreshKey == _lastAvatarKey && _cachedAvatarImage != null) {
      return _cachedAvatarImage!;
    }
    final session = Provider.of<SessionProvider>(context, listen: false);
    final user = session.user;
    final gender = user?['gender'] ?? 'Other';
    final imageUrl = user?['profileImage'];

    ImageProvider provider;
    if (imageUrl != null &&
        imageUrl is String &&
        imageUrl.trim().isNotEmpty &&
        imageUrl != 'null') {
      provider = NetworkImage('$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}');
    } else {
      provider = AssetImage(
        gender == 'Male'
            ? 'assets/Male.png'
            : gender == 'Female'
                ? 'assets/Female.png'
                : 'assets/Other.png',
      );
    }
    _cachedAvatarImage = provider;
    _lastAvatarKey = _imageRefreshKey;
    return provider;
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
    bool isSuccess = false;
    bool submitting = false;
    int selectedStars = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppThemeColors.divider(ctx),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                            .animate(animation),
                        child: child,
                      ),
                    ),
                    child: isSuccess
                        ? _appRatingThankYouPhase(ctx, selectedStars)
                        : _appRatingInputPhase(ctx, setSheet, selectedStars, submitting, (stars) {
                            setSheet(() => selectedStars = stars);
                          }, () async {
                            if (selectedStars == 0 || submitting) return;
                            setSheet(() => submitting = true);
                            try {
                              final res = await ApiClient.post('/api/rating', body: {'rating': selectedStars});
                              if (res.statusCode == 200 && mounted) {
                                setState(() => _hasRatedApp = true);
                                setSheet(() { isSuccess = true; submitting = false; });
                                Future.delayed(const Duration(milliseconds: 3200), () {
                                  if (ctx.mounted) Navigator.pop(ctx);
                                });
                              } else {
                                setSheet(() => submitting = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(t('failed_submit_rating'))),
                                  );
                                }
                              }
                            } catch (_) {
                              setSheet(() => submitting = false);
                            }
                          }),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _appRatingInputPhase(
    BuildContext ctx,
    StateSetter setSheet,
    int selectedStars,
    bool submitting,
    void Function(int) onStarTap,
    VoidCallback onSubmit,
  ) {
    return Padding(
      key: const ValueKey('rating-input'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              colors: [AppColors.cyan, AppColors.blue],
            ).createShader(r),
            child: const Icon(Icons.star_rounded, size: 48, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Text(
            t('rate_our_app_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx)),
          ),
          const SizedBox(height: 8),
          Text(
            t('rate_app_feedback_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx), height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < selectedStars;
              return GestureDetector(
                onTap: () => onStarTap(i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      key: ValueKey(filled),
                      color: filled ? Colors.amber : AppThemeColors.mutedText(ctx),
                      size: 40,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppThemeColors.border(ctx)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(t('close'), style: TextStyle(color: AppThemeColors.secondaryText(ctx), fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: selectedStars > 0
                        ? const LinearGradient(colors: [AppColors.cyan, AppColors.blue])
                        : null,
                    color: selectedStars == 0 ? AppThemeColors.surfaceBg(ctx) : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: selectedStars > 0 && !submitting ? onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: submitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(
                            t('submit'),
                            style: TextStyle(
                              color: selectedStars > 0 ? Colors.white : AppThemeColors.mutedText(ctx),
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _appRatingThankYouPhase(BuildContext ctx, int stars) {
    return Padding(
      key: const ValueKey('rating-thankyou'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 72, height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            t('thank_you_rating_title'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.cyan),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t('thank_you_rating_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx), height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i < stars ? Colors.amber : AppThemeColors.mutedText(ctx),
                size: 28,
              ),
            )),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent, shadowColor: Colors.transparent, elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(t('continue'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ),
        ],
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
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage()));
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
          backgroundColor: AppThemeColors.cardBg(context),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: AppColors.cyan),
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('menu_label'),
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: context.sp(22),
                                fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Tooltip(
                          message: 'My QR Code',
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const UserQrPage()));
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.qr_code_rounded,
                                  color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white.withValues(alpha: 0.25),
                          backgroundImage: _getUserAvatar(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                Provider.of<SessionProvider>(context, listen: false)
                                        .user?['name']?.toString() ?? '',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '@${Provider.of<SessionProvider>(context, listen: false).user?['username']?.toString() ?? ''}',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: Text(t('dashboard')),
                onTap: () {
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(t('settings')),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.pushNamed(context, '/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.hub_rounded),
                title: const Text('Communities'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage()))
                      .then((_) => _loadCommunities());
                },
              ),
              ListTile(
                leading: const Icon(Icons.timeline),
                title: Text(t('activity')),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ActivityPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(t('updates')),
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
                title: Text(t('notes')),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => NotesPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_center),
                title: Text(t('help_and_support')),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => HelpSupportPage()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.feedback),
                title: Text(t('feedback')),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.pushNamed(context, '/feedback');
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(t('logout')),
                onTap: () {
                  Navigator.of(context).pop();
                  showLogoutDialog(context, onConfirm: () {
                    Provider.of<SessionProvider>(context, listen: false).logout();
                    Navigator.of(context).pushReplacementNamed('/');
                  });
                },
              ),
            ],
          ),
        ),
        backgroundColor: AppThemeColors.scaffoldBg(context),
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
                    clipper: BottomNavWaveClipper(),
                    child: Container(color: AppThemeColors.waveSolid(context)),
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
                      _navBarItem(Icons.settings_rounded, t('settings'), () {
                        Navigator.pushNamed(context, '/settings');
                      }),
                      _navBarItem(Icons.monetization_on_rounded, t('coins_label'), () {
                        final session = Provider.of<SessionProvider>(context,
                            listen: false);
                        _openLenDenCoinsPage(session.lenDenCoins ?? 0);
                      }, accent: const Color(0xFFFF9F45)),
                      SizedBox(width: context.sh(48)),
                      _navBarItem(Icons.account_balance_wallet_rounded,
                          t('wallet_label'), () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LendenWalletPage()));
                      }, accent: const Color(0xFFFF9F45)),
                      _navBarItem(Icons.logout_rounded, t('logout'),
                          () => showLogoutDialog(context, onConfirm: () {
                            Provider.of<SessionProvider>(context, listen: false).logout();
                            Navigator.of(context).pushReplacementNamed('/');
                          })),
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
                onRefresh: () {
                  final session = Provider.of<SessionProvider>(context, listen: false);
                  return Future.wait([
                    _fetchFriends(),
                    _fetchUnreadUpdatesCount(),
                    session.refreshUserProfile(),
                  ]);
                },
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
                    // â”€â”€ Own birthday celebration banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Builder(builder: (bCtx) {
                      final sess = Provider.of<SessionProvider>(bCtx, listen: false);
                      return BirthdayBanner(birthdayRaw: sess.user?['birthday']?.toString());
                    }),
                    const SizedBox(height: 8),
                    DashboardGreetingCard(
                      greetingSubtitle: _greetingSubtitle,
                      dailyTip: _dailyTip,
                      netLent: _netLent,
                      netBorrowed: _netBorrowed,
                    ),
                    const SizedBox(height: 4),
                    // Search Bar with tricolor border + view menu
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: const LinearGradient(
                                    colors: [Colors.orange, Colors.white, Colors.green],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.search,
                                          color: AppThemeColors.secondaryText(context), size: 19),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _searchController,
                                          onSubmitted: _performSearch,
                                          style: TextStyle(
                                            fontSize: context.sp(14),
                                            color: AppThemeColors.primaryText(context),
                                          ),
                                          decoration: InputDecoration(
                                            hintText: t('search_sections_placeholder'),
                                            hintStyle: TextStyle(
                                                color: AppThemeColors.mutedText(context),
                                                fontSize: context.sp(14)),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                      if (_searchController.text.isNotEmpty)
                                        GestureDetector(
                                          onTap: () => setState(() => _searchController.clear()),
                                          child: Icon(Icons.clear,
                                              color: AppThemeColors.secondaryText(context), size: 17),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 44,
                              child: Container(
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [Colors.orange, Colors.white, Colors.green],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.cardBg(context),
                                    shape: BoxShape.circle,
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.more_vert, color: Color(0xFF00B4D8)),
                                    tooltip: t('quick_actions_view_label'),
                                    onPressed: _showQuickActionsViewMenu,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    iconSize: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Quick Actions â€” selectable view style
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
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFE0F7FA),
                              dark: const Color(0xFF0F2E33)),
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
                                      t('counterparties'),
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
                                  child: Text(t('view_label')),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // â”€â”€ Analytics & Planning â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: Row(
                        children: [
                          Expanded(child: DashboardAnalyticsCard(
                            icon: Icons.bar_chart_rounded,
                            color: const Color(0xFF00BCD4),
                            label: t('reports_title'),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsPage())),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: DashboardAnalyticsCard(
                            icon: Icons.savings_outlined,
                            color: const Color(0xFF4CAF50),
                            label: t('budget_planning_title'),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetPlanningPage()))
                                .then((_) => _fetchSavingsGoals()),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: DashboardAnalyticsCard(
                            icon: Icons.auto_awesome_rounded,
                            color: const Color(0xFF9C27B0),
                            label: t('smart_insights_title'),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartInsightsPage())),
                          )),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // â”€â”€ Savings Goals â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    KeyedSubtree(
                      key: _sectionKeys['savings_goals'],
                      child: _buildSavingsGoalsCard(context),
                    ),

                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('transaction_options_title'),
                            style: TextStyle(
                              fontSize: context.sp(16),
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t('open_main_transaction_tools_subtitle'),
                            style: TextStyle(
                              fontSize: context.sp(12),
                              color: AppThemeColors.secondaryText(context),
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
                                  color: AppThemeColors.cardBg(context),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildTransactionLayoutChip(
                                      label: t('single_view_label'),
                                      selected: !_useCompactTransactionOptions,
                                      onTap: () {
                                        setState(() {
                                          _useCompactTransactionOptions = false;
                                        });
                                      },
                                    ),
                                    _buildTransactionLayoutChip(
                                      label: t('grid_view_label'),
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
                          const SizedBox(height: 28),
                          _buildCommunitiesSection(),
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
                clipper: const DeepTopWaveClipper(),
                child: Container(
                  height: context.sh(78),
                  color: AppThemeColors.waveSolid(context),
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
                                icon: Icon(Icons.arrow_back,
                                    color: AppThemeColors.primaryText(context)),
                                tooltip: t('back'),
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
                                  icon: Icon(Icons.menu,
                                      color: AppThemeColors.primaryText(context)),
                                  tooltip: t('menu'),
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
                                icon: Icon(Icons.emoji_events,
                                    color: AppThemeColors.primaryText(context), size: 26),
                                tooltip: t('leaderboard'),
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
                                  onTap: () {
                                    showAvatarActionSheet(
                                      context,
                                      avatarImage: _getUserAvatar(),
                                      onViewDetails: () async {
                                        try {
                                          await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    const ProfilePage()),
                                          );
                                          final session =
                                              Provider.of<SessionProvider>(
                                                  context,
                                                  listen: false);
                                          await session.forceRefreshProfile();
                                          if (mounted) {
                                            setState(() {
                                              _imageRefreshKey++;
                                            });
                                          }
                                        } catch (_) {}
                                      },
                                    );
                                  },
                                  child: CircleAvatar(
                                    key: ValueKey(_imageRefreshKey),
                                    radius: 16,
                                    backgroundColor: AppThemeColors.cardBg(context),
                                    backgroundImage: _getUserAvatar(),
                                    onBackgroundImageError:
                                        (exception, stackTrace) {},
                                    child: _getUserAvatar() is AssetImage
                                        ? Icon(
                                            Icons.person,
                                            color: AppThemeColors.mutedText(context),
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
      'label': 'grid_label',
      'icon': Icons.grid_view_rounded,
    },
    {
      'style': _QuickActionsViewStyle.orbit,
      'label': 'orbit_label',
      'icon': Icons.circle_outlined,
    },
    {
      'style': _QuickActionsViewStyle.verticalOrbit,
      'label': 'vertical_orbit_label',
      'icon': Icons.swap_vert_circle_outlined,
    },
    {
      'style': _QuickActionsViewStyle.galaxy,
      'label': 'galaxy_label',
      'icon': Icons.blur_circular,
    },
    {
      'style': _QuickActionsViewStyle.zigzag,
      'label': 'zig_zag_label',
      'icon': Icons.show_chart_rounded,
    },
    {
      'style': _QuickActionsViewStyle.star,
      'label': 'star_label',
      'icon': Icons.star_rate_rounded,
    },
    {
      'style': _QuickActionsViewStyle.spiral,
      'label': 'spiral_label',
      'icon': Icons.cyclone_rounded,
    },
    {
      'style': _QuickActionsViewStyle.wave,
      'label': 'wave_label',
      'icon': Icons.waves_rounded,
    },
    {
      'style': _QuickActionsViewStyle.circle,
      'label': 'circle_label',
      'icon': Icons.radio_button_unchecked,
    },
    {
      'style': _QuickActionsViewStyle.list,
      'label': 'list_label',
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
                color: AppThemeColors.cardBg(context),
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
                      Text(t('quick_actions_view_label'),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t('choose_quick_actions_display'),
                    style: TextStyle(
                        fontSize: 12,
                        color: AppThemeColors.secondaryText(context)),
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
                                : Border.all(color: AppThemeColors.divider(context)),
                          ),
                          padding: EdgeInsets.all(selected ? 2 : 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppThemeColors.tinted(context,
                                      light: const Color(0xFFE0F7FA),
                                      dark: const Color(0xFF0F2E33))
                                  : AppThemeColors.cardBg(context),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(option['icon'] as IconData,
                                    color: selected
                                        ? const Color(0xFF00B4D8)
                                        : AppThemeColors.secondaryText(context),
                                    size: 26),
                                const SizedBox(height: 6),
                                Text(
                                  t(option['label'] as String),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    color: selected
                                        ? const Color(0xFF00B4D8)
                                        : AppThemeColors.secondaryText(context),
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
                label: _quickActionLabel(item['action'] as String),
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
                    label: _quickActionLabel(item['action'] as String),
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
                    label: _quickActionLabel(item['action'] as String),
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
                    label: _quickActionLabel(item['action'] as String),
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
                label: _quickActionLabel(item['action'] as String),
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
                  label: _quickActionLabel(item['action'] as String),
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
                  label: _quickActionLabel(item['action'] as String),
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
                      label: _quickActionLabel(item['action'] as String),
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
              label: _quickActionLabel(item['action'] as String),
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
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppThemeColors.divider(context)),
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
                      _quickActionLabel(item['action'] as String),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppThemeColors.primaryText(context)),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppThemeColors.mutedText(context)),
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
                color: getDashboardBoxColor(index, context),
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
              color: AppThemeColors.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTransactionOptionCards() {
    return [
      DashboardOptionCard(
        key: _sectionKeys['quick_transactions'],
        icon: Icons.flash_on,
        title: t('quick_transactions_title'),
        subtitle: t('fast_entries_shortcuts_desc'),
        valueLabel: t('quick_label'),
        iconColor: Colors.amber,
        fillColor: getDashboardBoxColor(0, context),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => QuickTransactionsPage(),
          ),
        ),
      ),
      DashboardOptionCard(
        key: _sectionKeys['transactions'],
        icon: Icons.swap_horiz,
        title: t('create_secure_transactions_title'),
        subtitle: t('start_secure_transaction_desc'),
        valueLabel: t('create'),
        iconColor: Colors.teal,
        fillColor: getDashboardBoxColor(1, context),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: showTransactionForm,
      ),
      DashboardOptionCard(
        key: _sectionKeys['your_transactions'],
        icon: Icons.account_balance_wallet,
        title: t('view_secure_transactions_title'),
        subtitle: t('see_all_secure_records_desc'),
        valueLabel: t('view_label'),
        iconColor: Colors.blue,
        fillColor: getDashboardBoxColor(2, context),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UserTransactionsPage(),
          ),
        ),
      ),
      DashboardOptionCard(
        key: _sectionKeys['analytics'],
        icon: Icons.analytics,
        title: t('analytics'),
        subtitle: t('secure_and_group_insights_desc'),
        valueLabel: t('stats_label'),
        iconColor: AppColors.cyan,
        fillColor: getDashboardBoxColor(3, context),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnalyticsPage(),
          ),
        ),
      ),
      DashboardOptionCard(
        key: _sectionKeys['group_transaction'],
        icon: Icons.group,
        title: t('create_group_title'),
        subtitle: t('start_shared_expense_group_desc'),
        valueLabel: t('create'),
        iconColor: Colors.deepPurple,
        fillColor: getDashboardBoxColor(4, context),
        showSubtitle: !_useCompactTransactionOptions,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GroupTransactionPage(),
          ),
        ),
      ),
      DashboardOptionCard(
        key: _sectionKeys['view_group'],
        icon: Icons.visibility,
        title: t('view_groups_title'),
        subtitle: t('open_your_group_transactions_desc'),
        valueLabel: t('view_label'),
        iconColor: Colors.orange,
        fillColor: getDashboardBoxColor(5, context),
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

  Color _communityParseColor(dynamic c) {
    try {
      if (c is String && c.startsWith('#')) {
        return Color(int.parse('FF${c.replaceFirst('#', '')}', radix: 16));
      }
    } catch (_) {}
    return AppColors.cyan;
  }

  Widget _buildCommunitiesSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppThemeColors.border(context)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 0),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.hub_rounded, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text('Communities', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
            const Spacer(),
            if (_communities.isNotEmpty)
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage())).then((_) => _loadCommunities()),
                style: TextButton.styleFrom(foregroundColor: AppColors.cyan, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                child: const Text('See All', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        if (_loadingCommunities)
          SizedBox(
            height: 130,
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan))),
          )
        else if (_communities.isEmpty)
          _buildCommunityEmptyState()
        else
          SizedBox(
            height: 148,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              itemCount: _communities.length + 1,
              itemBuilder: (_, i) {
                if (i == _communities.length) return _buildCreateCommunityCard();
                return _buildCommunityMiniCard(_communities[i]);
              },
            ),
          ),

        const SizedBox(height: 16),

        // Bottom action row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.cyan),
                  foregroundColor: AppColors.cyan,
                ),
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Join with Code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage())).then((_) => _loadCommunities()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, minimumSize: const Size.fromHeight(42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                  icon: const Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  label: const Text('Create', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
                    if (result != null) _loadCommunities();
                  },
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCommunityEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.cyan.withValues(alpha: 0.06), AppColors.blue.withValues(alpha: 0.06)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.hub_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No communities yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text('Organize your groups under one community — office, family, college & more.', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context), height: 1.4)),
          ])),
        ]),
      ),
    );
  }

  Widget _buildCommunityMiniCard(Map<String, dynamic> c) {
    final id = (c['_id'] ?? '').toString();
    final name = (c['name'] ?? 'Community').toString();
    final color = _communityParseColor(c['color']);
    final members = (c['members'] as List?)?.length ?? 0;
    final groups = (c['groups'] as List?)?.length ?? 0;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'C';
    final imgUrl = id.isNotEmpty ? '${ApiConfig.baseUrl}/api/communities/$id/image' : null;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage())).then((_) => _loadCommunities()),
      child: Container(
        width: 148,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.surfaceBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppThemeColors.border(context)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Color top bar with avatar
          Container(
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Center(
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: imgUrl != null
                      ? Image.network(imgUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))))
                      : Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                ),
              ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppThemeColors.primaryText(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.folder_shared_rounded, size: 11, color: AppThemeColors.mutedText(context)),
                const SizedBox(width: 3),
                Text('$groups grp', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
                const SizedBox(width: 8),
                Icon(Icons.people_rounded, size: 11, color: AppThemeColors.mutedText(context)),
                const SizedBox(width: 3),
                Text('$members', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildCreateCommunityCard() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCommunityPage()));
        if (result != null) _loadCommunities();
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25), style: BorderStyle.solid),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 10),
          Text('Create', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.cyan)),
          const SizedBox(height: 2),
          Text('Community', style: TextStyle(fontSize: 11, color: AppThemeColors.secondaryText(context))),
        ]),
      ),
    );
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

  Widget _buildSavingsGoalsCard(BuildContext context) {
    final active = _savingsGoals.where((g) => g['isCompleted'] != true).toList();
    const cardColor = Color(0xFF7C3AED);

    void goToGoalsTab() {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const BudgetPlanningPage(initialTabIndex: 3)))
          .then((_) => _fetchSavingsGoals());
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppThemeColors.tinted(context,
              light: const Color(0xFFF5F0FF), dark: const Color(0xFF140C24)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // â”€â”€ Header row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Row(children: [
            const Icon(Icons.savings_rounded, color: cardColor, size: 20),
            const SizedBox(width: 8),
            Text(t('savings_goals_title'), style: TextStyle(
              fontSize: context.sp(16),
              fontWeight: FontWeight.bold,
              color: cardColor,
            )),
            const Spacer(),
            if (active.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cardColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t('active_goals_label').replaceAll('{count}', active.length.toString()),
                  style: TextStyle(fontSize: context.sp(11), color: cardColor, fontWeight: FontWeight.w700),
                ),
              ),
          ]),
          const SizedBox(height: 12),

          // â”€â”€ Empty state â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (active.isEmpty)
            GestureDetector(
              onTap: goToGoalsTab,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppThemeColors.tinted(context,
                      light: Colors.white, dark: const Color(0xFF1C1236)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cardColor.withValues(alpha: 0.20)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.savings_outlined, size: 36,
                      color: cardColor.withValues(alpha: 0.45)),
                  const SizedBox(height: 8),
                  Text('No savings goals yet',
                      style: TextStyle(fontSize: context.sp(13),
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text('Tap to add a goal',
                      style: TextStyle(fontSize: context.sp(11),
                          color: cardColor)),
                ]),
              ),
            )

          // â”€â”€ Goal cards â€” horizontal scroll â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          else
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: active.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final g = active[i];
                  final target = (g['targetAmount'] as num?)?.toDouble() ?? 1;
                  final saved  = (g['savedAmount']  as num?)?.toDouble() ?? 0;
                  final pct    = (saved / target).clamp(0.0, 1.0);
                  Color goalColor = cardColor;
                  try {
                    final hex = (g['color'] ?? '#7C3AED').toString();
                    goalColor = Color(int.parse(hex.replaceFirst('#', '0xff')));
                  } catch (_) {}
                  final daysLeft = g['deadline'] != null
                      ? DateTime.parse(g['deadline'].toString()).difference(DateTime.now()).inDays
                      : null;
                  return Container(
                    width: 165,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: Colors.white, dark: const Color(0xFF1C1236)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: goalColor.withValues(alpha: 0.30)),
                      boxShadow: [BoxShadow(color: goalColor.withValues(alpha: 0.08),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                      Row(children: [
                        Text(g['emoji']?.toString() ?? 'ðŸŽ¯',
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 5),
                        Expanded(child: Text(g['name']?.toString() ?? '',
                          style: TextStyle(fontSize: context.sp(12),
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.primaryText(context)),
                          overflow: TextOverflow.ellipsis, maxLines: 1)),
                      ]),
                      const SizedBox(height: 5),
                      Text('â‚¹${saved.toStringAsFixed(0)} / â‚¹${target.toStringAsFixed(0)}',
                          style: TextStyle(fontSize: context.sp(11),
                              color: goalColor, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct, minHeight: 5,
                          backgroundColor: AppThemeColors.border(context),
                          valueColor: AlwaysStoppedAnimation<Color>(goalColor),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text(t('percent_saved_label').replaceAll('{pct}', (pct * 100).toStringAsFixed(0)),
                            style: TextStyle(fontSize: context.sp(9),
                                color: AppThemeColors.secondaryText(context))),
                        const Spacer(),
                        if (daysLeft != null)
                          Text(t('days_left_short_label').replaceAll('{count}', daysLeft.toString()),
                              style: TextStyle(fontSize: context.sp(9),
                                  color: daysLeft < 7 ? Colors.red.shade600
                                      : AppThemeColors.secondaryText(context),
                                  fontWeight: daysLeft < 7 ? FontWeight.bold : FontWeight.normal)),
                      ]),
                    ]),
                  );
                },
              ),
            ),
        ]),
      ),
    );
  }

  void _openQrScanner() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.orange, Colors.white, Colors.green]),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(t('scan_and_pay_title'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
            const SizedBox(height: 16),
            ListTile(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScannerPage()));
              },
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.cyan),
              ),
              title: Text(t('scan_qr_code_label'), style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
              subtitle: Text(t('scan_qr_code_desc'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            const SizedBox(height: 6),
            ListTile(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LendenWalletPage(autoOpenPayUser: true)),
                );
              },
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF2E7D32).withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.person_rounded, color: Color(0xFF2E7D32)),
              ),
              title: Text(t('pay_user_label'), style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
              subtitle: Text(t('pay_user_desc'), style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            const SizedBox(height: 6),
            ListTile(
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const UserQrPage()));
              },
              leading: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFF6A0DAD).withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.qr_code_rounded, color: Color(0xFF6A0DAD)),
              ),
              title: Text('My QR Code', style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx))),
              subtitle: Text('Show your QR so others can pay you instantly', style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navBarItem(IconData icon, String label, VoidCallback onTap,
      {Color? accent}) {
    final Color base = accent ?? AppColors.cyan;
    final Color dark = Color.lerp(base, const Color(0xFF001A2E), 0.4)!;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
      message: label,
      // Outer tricolor ring â€” identical to profile pic border
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
    ));
  }

}

