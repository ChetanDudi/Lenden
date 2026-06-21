import 'dart:async';
import 'package:flutter/material.dart';
import 'widgets/app_colors.dart';
import 'package:provider/provider.dart';
import 'login/login_page.dart';
import 'register/register_page.dart';
import 'password_management/forgot_password_page.dart';
import 'user/dashboard/dashboard.dart';
import 'admin/dashboard/dashboard.dart';
import 'profile/profile_page.dart';
import 'session.dart';
import 'settings/settings_page.dart';
import 'settings/admin_settings_page.dart';
import 'user/support/contact_page.dart';
import 'admin/manage_users/user_management_page.dart';
import 'admin/transactions/manage_secure_transactions_page.dart';
import 'admin/transactions/manage_group_transactions_page.dart';
import 'splash_screen.dart';
import 'user/support/feedback.dart';
import 'admin/rating/admin_ratings_page.dart';
import 'admin/support/admin_feedbacks_page.dart';
import 'user/connections/counterparties_page.dart';
import 'widgets/notification_icon.dart';
import 'utils/auth_navigation.dart';
import 'utils/responsive.dart';
import 'settings/about_page.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SessionProvider()),
      ],
      child: const AppInitializer(),
    ),
  );
}

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer>
    with WidgetsBindingObserver {
  late Future<void> _bootstrapFuture;
  int? _pendingDailyRewardCoins;
  bool _dailyRewardDialogVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrapFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final startedAt = DateTime.now();
    await session.initSession();
    unawaited(_maybeQueueDailyReward(session));

    final elapsed = DateTime.now().difference(startedAt);
    const minimumSplash = Duration(milliseconds: 700);
    if (elapsed < minimumSplash) {
      await Future.delayed(minimumSplash - elapsed);
    }
  }

  Future<void> _maybeQueueDailyReward(SessionProvider session) async {
    final reward = await session.checkDailyLoginRewardOnAppOpen();
    if (!mounted) return;
    if (reward != null && reward['awarded'] == true) {
      _pendingDailyRewardCoins = (reward['coinsAwarded'] as num?)?.toInt() ?? 1;
      _showPendingDailyRewardIfNeeded();
    }
  }

  void _showPendingDailyRewardIfNeeded() {
    if (_dailyRewardDialogVisible || _pendingDailyRewardCoins == null || !mounted) {
      return;
    }

    final coins = _pendingDailyRewardCoins!;
    _dailyRewardDialogVisible = true;
    _pendingDailyRewardCoins = null;

    _showWhenNavigatorReady(coins);
  }

  void _showWhenNavigatorReady(int coins) {
    if (!mounted) return;
    if (appNavigatorKey.currentContext != null) {
      _showDailyLoginRewardDialog(coins).then((_) {
        if (!mounted) return;
        setState(() => _dailyRewardDialogVisible = false);
      });
    } else {
      // Navigator not mounted yet — retry next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWhenNavigatorReady(coins));
    }
  }

  Future<void> _showDailyLoginRewardDialog(int coins) {
    final navContext = appNavigatorKey.currentContext;
    if (navContext == null) return Future.value();
    return showDialog<void>(
      context: navContext,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: EdgeInsets.all(context.sw(24)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: context.sw(72),
                height: context.sw(72),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: Colors.white,
                  size: context.sp(36),
                ),
              ),
              SizedBox(height: context.sh(16)),
              Text(
                'Daily Bonus',
                style: TextStyle(
                  fontSize: context.sp(22),
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: context.sh(10)),
              Text(
                'You earned $coins LenDen Coin${coins > 1 ? 's' : ''} on your first app open today.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: context.sp(15), color: Colors.grey[800]),
              ),
              SizedBox(height: context.sh(20)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    padding: EdgeInsets.symmetric(vertical: context.sh(13)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Nice',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: context.sp(15),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final session = Provider.of<SessionProvider>(context, listen: false);
      if (session.token != null && session.user == null) {
        setState(() {
          _bootstrapFuture = _initializeApp();
        });
        return;
      }
      if (session.token != null && !session.isAdmin) {
        session.checkDailyLoginRewardOnAppOpen().then((reward) {
          if (!mounted || reward == null || reward['awarded'] != true) return;
          _pendingDailyRewardCoins = (reward['coinsAwarded'] as num?)?.toInt() ?? 1;
          _showPendingDailyRewardIfNeeded();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      title: 'Lenden App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFFF8F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
      ),
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SplashScreen(autoNavigate: false);
          }
          _showPendingDailyRewardIfNeeded();
          return const MyApp();
        },
      ),
      routes: {
        '/main': (context) => const MyApp(),
        '/login': (context) => const UserLoginPage(),
        '/register': (context) => const UserRegisterPage(),
        '/forgot-password': (context) => const UserForgotPasswordPage(),
        '/user/dashboard': (context) => const UserDashboardPage(),
        '/admin/dashboard': (context) => const AdminDashboardPage(),
        '/profile': (context) => const ProfilePage(),
        '/settings': (context) => const SettingsPage(),
        '/admin/settings': (context) => const AdminSettingsPage(),
        '/admin/manage-users': (context) => const UserManagementPage(),
        '/admin/manage-transactions': (context) => ManageTransactionsPage(),
        '/admin/manage-group-transactions': (context) =>
            ManageGroupTransactionsPage(),
        '/feedback': (context) => const FeedbackPage(),
        '/user/counterparties': (context) => const CounterpartiesPage(),
        '/admin/ratings': (context) => const AdminRatingsPage(),
        '/admin/feedbacks': (context) => const AdminFeedbacksPage(),
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage();
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF8F6FA),
      drawer: Drawer(
        width: context.sw(200),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.cyan,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/icon.png',
                      width: context.sw(48), height: context.sw(48)),
                  SizedBox(height: context.sh(8)),
                  Text('Lenden App',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: context.sp(20),
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('Home'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Login'),
              onTap: () {
                final session =
                    Provider.of<SessionProvider>(context, listen: false);
                if (session.token != null && session.user != null) {
                  if (session.isAdmin) {
                    Navigator.pushReplacementNamed(context, '/admin/dashboard');
                  } else {
                    Navigator.pushReplacementNamed(context, '/user/dashboard');
                  }
                } else {
                  Navigator.pushNamed(context, '/login');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Register'),
              onTap: () => Navigator.pushNamed(context, '/register'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.contact_mail),
              title: const Text('Contact'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContactPage()),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
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
          // Main content area (white card style)
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: context.hPadding, vertical: context.vPadding),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Menu icon (left)
                        Builder(
                          builder: (context) => IconButton(
                            icon: const Icon(Icons.menu, color: Colors.black),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                        // Right side: notification and profile
                        Row(
                          children: [
                            NotificationIcon(),
                            Consumer<SessionProvider>(
                              builder: (context, session, _) {
                                final user = session.user;
                                final profileImage = user != null &&
                                        user['profileImage'] != null &&
                                        user['profileImage']
                                            .toString()
                                            .isNotEmpty &&
                                        user['profileImage'] != 'null'
                                    ? NetworkImage(user['profileImage'])
                                    : null;
                                return GestureDetector(
                                  onTap: () {
                                    if (session.token != null &&
                                        session.user != null) {
                                      Navigator.pushNamed(context, '/profile');
                                    } else {
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(24),
                                          ),
                                          backgroundColor:
                                              const Color(0xFFF6F7FB),
                                          elevation: 12,
                                          title: Row(
                                            children: [
                                              Icon(Icons.lock_outline,
                                                  color: AppColors.cyan,
                                                  size: context.sp(26)),
                                              SizedBox(width: context.sw(8)),
                                              Text('Login Required',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: context.sp(20))),
                                            ],
                                          ),
                                          content: Text(
                                            'Please login to view your profile.',
                                            style: TextStyle(
                                                fontSize: context.sp(15),
                                                color: Colors.black87),
                                          ),
                                          actions: [
                                            TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                backgroundColor:
                                                    AppColors.cyan,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                    horizontal: context.sw(16),
                                                    vertical: context.sh(6)),
                                                child: Text('OK',
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: context.sp(15))),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.orange,
                                          Colors.white,
                                          Colors.green
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: context.sw(18),
                                      backgroundColor: AppColors.cyan,
                                      backgroundImage: profileImage,
                                      child: profileImage == null
                                          ? const Icon(Icons.person,
                                              color: Colors.white)
                                          : null,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: context.sh(20)),
                    // Feature cards (auto-scroll, horizontally swipeable)
                    SizedBox(
                      height: context.sh(200),
                      child: _FeatureCardCarousel(),
                    ),
                    SizedBox(height: context.sh(28)),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.orange, Colors.white, Colors.green],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(29),
                          ),
                          padding: EdgeInsets.all(context.sw(20)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/icon.png',
                              width: context.sw(110),
                              height: context.sw(110),
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.account_balance_wallet,
                                      size: context.sw(90),
                                      color: AppColors.cyan),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: context.sh(24)),
                    Center(
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFF0077B6), AppColors.cyan, Color(0xFF48CAE4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'Welcome to the',
                              style: TextStyle(
                                fontSize: context.sp(18),
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Color(0xFFFF9933), AppColors.cyan, Color(0xFF138808)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds),
                            child: Text(
                              'LenDen',
                              style: TextStyle(
                                fontSize: context.sp(42),
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2.5,
                                height: 1.0,
                              ),
                            ),
                          ),
                          SizedBox(height: context.sh(6)),
                          Text(
                            'Lend, borrow & manage money — together.',
                            style: TextStyle(
                              fontSize: context.sp(12),
                              color: Colors.grey.shade500,
                              letterSpacing: 0.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: context.sh(28)),
                    Consumer<SessionProvider>(
                      builder: (context, session, _) {
                        final notLoggedIn =
                            session.token == null || session.user == null;

                        final getStartedBtn = Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.white, Colors.green],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.cyan.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final s = Provider.of<SessionProvider>(context,
                                  listen: false);
                              if (s.token != null && s.user != null) {
                                if (s.isAdmin) {
                                  Navigator.pushNamed(context, '/admin/dashboard');
                                } else {
                                  Navigator.pushNamed(context, '/user/dashboard');
                                }
                              } else {
                                Navigator.pushNamed(context, '/login');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(21.5),
                              ),
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              padding: EdgeInsets.symmetric(
                                  vertical: context.sh(14),
                                  horizontal: context.sw(28)),
                            ),
                            icon: const Icon(Icons.arrow_forward,
                                color: Colors.white),
                            label: Text('Get Started',
                                style: TextStyle(
                                    fontSize: context.sp(17),
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                          ),
                        );

                        final registerBtn = Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.white, Colors.green],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: TextButton.icon(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/register'),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(21.5)),
                              padding: EdgeInsets.symmetric(
                                  vertical: context.sh(12),
                                  horizontal: context.sw(28)),
                            ),
                            icon: const Icon(Icons.arrow_forward,
                                color: AppColors.cyan),
                            label: Text('Register',
                                style: TextStyle(
                                    fontSize: context.sp(17),
                                    color: AppColors.cyan,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1)),
                          ),
                        );

                        return Column(
                          children: [
                            // When not logged in: Get Started at top, Register below.
                            // When logged in: invisible placeholder keeps spacing,
                            // Get Started appears at Register's position.
                            Visibility(
                              visible: notLoggedIn,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: getStartedBtn,
                            ),
                            SizedBox(height: context.sh(16)),
                            notLoggedIn ? registerBtn : getStartedBtn,
                            SizedBox(height: context.sh(28)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  const _FeatureCard(
      {required this.icon, required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.sw(170),
      margin: EdgeInsets.symmetric(horizontal: context.sw(8), vertical: context.sh(8)),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(context.sw(14)),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.cyan, size: context.sp(26)),
            SizedBox(height: context.sh(4)),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: context.sp(13))),
            SizedBox(height: context.sh(2)),
            Text(
              description,
              style: TextStyle(color: Colors.grey, fontSize: context.sp(11)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// Feature card carousel with auto-scroll and round effect
class _FeatureCardCarousel extends StatefulWidget {
  @override
  State<_FeatureCardCarousel> createState() => _FeatureCardCarouselState();
}

class _FeatureCardCarouselState extends State<_FeatureCardCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.6);
  int _currentPage = 0;
  final List<Map<String, dynamic>> _features = [
    {
      'icon': Icons.swap_horiz,
      'title': 'One-to-One',
      'description': 'Direct lending and borrowing between users.'
    },
    {
      'icon': Icons.groups,
      'title': 'Group Transactions',
      'description': 'Manage and settle group transactions easily.'
    },
    {
      'icon': Icons.event_note,
      'title': 'Activities',
      'description': 'Track all your lending and borrowing activities.'
    },
    {
      'icon': Icons.note,
      'title': 'Notes',
      'description': 'Add notes to your transactions for better tracking.'
    },
    {
      'icon': Icons.security,
      'title': 'Secure',
      'description': 'Your data is protected with top security.'
    },
    {
      'icon': Icons.flash_on,
      'title': 'Fast',
      'description': 'Quick transactions and instant notifications.'
    },
    {
      'icon': Icons.people,
      'title': 'Community',
      'description': 'Connect with trusted users.'
    },
    {
      'icon': Icons.support_agent,
      'title': 'Support',
      'description': '24/7 customer support.'
    },
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), _autoScroll);
  }

  void _autoScroll() {
    if (!mounted) return;
    int nextPage = _currentPage + 1;
    if (nextPage >= _features.length) nextPage = 0;
    _controller.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = nextPage);
    Future.delayed(const Duration(milliseconds: 1800), _autoScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: _features.length,
      onPageChanged: (i) => setState(() => _currentPage = i),
      itemBuilder: (context, i) {
        final feature = _features[i];
        final isActive = i == _currentPage;
        return Transform.scale(
          scale: isActive ? 1.08 : 0.92,
          child: Opacity(
            opacity: isActive ? 1 : 0.7,
            child: _FeatureCard(
              icon: feature['icon'],
              title: feature['title'],
              description: feature['description'],
            ),
          ),
        );
      },
    );
  }
}

class GoogleMenuIcon extends StatelessWidget {
  const GoogleMenuIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 3),
        ColoredBar(color: Color(0xFF4285F4)), // Blue
        SizedBox(height: 4),
        ColoredBar(color: Color(0xFFDB4437)), // Red
        SizedBox(height: 4),
        ColoredBar(color: Color(0xFFF4B400)), // Yellow
      ],
    );
  }
}

class ColoredBar extends StatelessWidget {
  final Color color;
  const ColoredBar({Key? key, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      width: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
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

