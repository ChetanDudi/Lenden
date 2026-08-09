import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import 'utils/api_client.dart';
import 'utils/responsive.dart';
import 'settings/about_page.dart';
import 'utils/app_lock_service.dart';
import 'widgets/app_lock_screen.dart';
import 'utils/theme_provider.dart';
import 'utils/locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'utils/theme_helper.dart';
import 'utils/connectivity_service.dart';
import 'services/firebase_service.dart';
import 'screens/maintenance_screen.dart';
import 'widgets/no_internet_banner.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await ConnectivityService().init();
    await FirebaseService.initialize();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Flutter error: ${details.exceptionAsString()}');
    };
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SessionProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const AppInitializer(),
      ),
    );
  }, (error, stack) => debugPrint('Uncaught error: $error\n$stack'));
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
  bool _locked = false;
  bool _wasBackgrounded = false;
  bool _forceUpdate = false;
  bool _inMaintenance = false;
  String? _activeUserId;
  SessionProvider? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = Provider.of<SessionProvider>(context, listen: false);
    _session!.addListener(_onSessionUserChanged);
    _bootstrapFuture = _initializeApp();
  }

  Future<void> _initializeApp() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    ApiClient.onAuthFailed = () => session.clearTokens();
    ApiClient.onMaintenance = () {
      if (mounted) setState(() => _inMaintenance = true);
    };
    final startedAt = DateTime.now();
    await session.initSession();
    // Upload FCM token now if the user is already logged in (cold start / token persisted)
    if (session.token != null && !session.isAdmin) {
      unawaited(FirebaseService.uploadToken());
    }
    unawaited(_maybeQueueDailyReward(session));

    // App version check — force-update if server says current version is too old
    try {
      final info = await PackageInfo.fromPlatform();
      final versionResp = await ApiClient.get('/api/app-version');
      if (versionResp.statusCode == 200) {
        final data = json.decode(versionResp.body) as Map<String, dynamic>;
        final minVersion = (data['minVersion'] as String?) ?? '1.0.0';
        final forceUpdate = (data['forceUpdate'] as bool?) ?? false;
        if (forceUpdate || _isVersionLower(info.version, minVersion)) {
          _forceUpdate = true;
        }
      }
    } catch (_) {}

    // Each user/admin keeps their own theme and language — scope the loaded
    // preferences to whoever is currently logged in (or the guest slot).
    _activeUserId = session.user?['_id']?.toString();
    unawaited(themeProvider.loadThemeMode(_activeUserId));
    unawaited(localeProvider.loadLocale(_activeUserId));

    if (session.token != null && await AppLockService.isEnabled()) {
      _locked = true;
    }

    final elapsed = DateTime.now().difference(startedAt);
    const minimumSplash = Duration(milliseconds: 700);
    if (elapsed < minimumSplash) {
      await Future.delayed(minimumSplash - elapsed);
    }
  }

  bool _isVersionLower(String current, String minimum) {
    final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final m = minimum.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < m.length; i++) {
      final cv = i < c.length ? c[i] : 0;
      final mv = m[i];
      if (cv < mv) return true;
      if (cv > mv) return false;
    }
    return false;
  }

  Widget _buildUpdateRequiredScreen(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.system_update_alt_rounded,
                  size: 80, color: AppColors.cyan.withValues(alpha: 0.8)),
              const SizedBox(height: 24),
              Text(t('update_required_title'),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(t('update_required_message'),
                  style: TextStyle(
                      fontSize: 15,
                      color: AppThemeColors.secondaryText(context)),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: Text(t('update_now_label'),
                    style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Re-scopes theme/language storage whenever the logged-in account changes
  // (login, logout, or switching accounts) so settings never leak between
  // different users or admins sharing the same device.
  void _onSessionUserChanged() {
    final newUserId = _session?.user?['_id']?.toString();
    if (newUserId == _activeUserId) return;
    _activeUserId = newUserId;
    Provider.of<ThemeProvider>(context, listen: false).loadThemeMode(newUserId);
    Provider.of<LocaleProvider>(context, listen: false).loadLocale(newUserId);
    // Upload FCM token on login, delete it on logout
    final isUser = _session?.isAdmin == false;
    if (newUserId != null && isUser) {
      FirebaseService.uploadToken();
    } else if (newUserId == null) {
      FirebaseService.deleteToken();
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
      builder: (context) {
        final t = AppLocalizations.of(context).t;
        final bodyKey = coins > 1 ? 'daily_bonus_body_plural' : 'daily_bonus_body';
        final body = t(bodyKey).replaceFirst('{coins}', '$coins');
        return Dialog(
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
                  t('daily_bonus_title'),
                  style: TextStyle(
                    fontSize: context.sp(22),
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: context.sh(10)),
                Text(
                  body,
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
                      t('nice_label'),
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
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _wasBackgrounded = true;
    }
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() {});
      if (_wasBackgrounded) {
        _wasBackgrounded = false;
        final session = Provider.of<SessionProvider>(context, listen: false);
        if (session.token != null) {
          AppLockService.isEnabled().then((enabled) {
            if (enabled && mounted && !_locked) setState(() => _locked = true);
          });
        }
      }
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
    _session?.removeListener(_onSessionUserChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;
    final locale = context.watch<LocaleProvider>().locale;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      title: 'Lenden App',
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFFF8F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.cyan,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: NoInternetBanner(
        child: FutureBuilder<void>(
          future: _bootstrapFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SplashScreen(autoNavigate: false);
            }
            if (_inMaintenance) {
              return MaintenanceScreen(onRetry: () => setState(() {
                _inMaintenance = false;
                _bootstrapFuture = _initializeApp();
              }));
            }
            if (_forceUpdate) {
              return _buildUpdateRequiredScreen(context);
            }
            if (_locked) {
              return AppLockScreen(
                onUnlocked: () => setState(() => _locked = false),
              );
            }
            _showPendingDailyRewardIfNeeded();
            return const MyApp();
          },
        ),
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
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      drawer: Drawer(
        width: context.sw(200),
        backgroundColor: AppThemeColors.cardBg(context),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: AppThemeColors.waveSolid(context),
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
              title: Text(t('home')),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(t('login')),
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
              title: Text(t('register')),
              onTap: () => Navigator.pushNamed(context, '/register'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('about')),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.contact_mail),
              title: Text(t('contact')),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContactPage()),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Light-blue header panel (title + tabs) ────────────
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFBEE3F0),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.sw(20), context.sh(6),
                    context.sw(20), context.sh(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  // Icon row: menu | spacer | notification + profile
                  Row(
                    children: [
                      Builder(
                        builder: (ctx) => GestureDetector(
                          onTap: () => Scaffold.of(ctx).openDrawer(),
                          child: Icon(Icons.menu,
                              color: Colors.black87,
                              size: context.sp(26)),
                        ),
                      ),
                      const Spacer(),
                      NotificationIcon(),
                      SizedBox(width: context.sw(8)),
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
                                  builder: (dlgCtx) {
                                    final dt =
                                        AppLocalizations.of(dlgCtx).t;
                                    return AlertDialog(
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
                                          Text(dt('login_required'),
                                              style: TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  fontSize:
                                                      context.sp(20))),
                                        ],
                                      ),
                                      content: Text(
                                        dt('please_login_to_view_profile'),
                                        style: TextStyle(
                                            fontSize: context.sp(15),
                                            color: Colors.black87),
                                      ),
                                      actions: [
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            backgroundColor: AppColors.cyan,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.of(dlgCtx).pop(),
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: context.sw(16),
                                                vertical: context.sh(6)),
                                            child: Text(dt('ok'),
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize:
                                                        context.sp(15))),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              }
                            },
                            child: CircleAvatar(
                              radius: context.sw(17),
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: profileImage,
                              child: profileImage == null
                                  ? Icon(Icons.person,
                                      color: Colors.grey.shade600,
                                      size: context.sp(18))
                                  : null,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  SizedBox(height: context.sh(18)),
                  // Large page title
                  Text(
                    'My Transactions',
                    style: TextStyle(
                      fontSize: context.sp(30),
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: context.sh(16)),
                  // Minimal tabs with dot indicator
                  _LandingTabBar(),
                  SizedBox(height: context.sh(2)),
                ],
              ),
            ),
          ),
        ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.sw(20), vertical: context.sh(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AppHighlightCard(),
                  SizedBox(height: context.sh(18)),
                  _LenDenShowcaseCard(),
                  SizedBox(height: context.sh(16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.sw(8), vertical: context.sh(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _LandingNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: true,
                onTap: () {
                  final session =
                      Provider.of<SessionProvider>(context, listen: false);
                  if (session.token != null && session.user != null) {
                    if (session.isAdmin) {
                      Navigator.pushNamed(context, '/admin/dashboard');
                    } else {
                      Navigator.pushNamed(context, '/user/dashboard');
                    }
                  } else {
                    Navigator.pushNamed(context, '/login');
                  }
                },
              ),
              _LandingNavItem(
                icon: Icons.person_add_rounded,
                label: 'Register',
                onTap: () => Navigator.pushNamed(context, '/register'),
              ),
              _LandingNavItem(
                icon: Icons.info_outline_rounded,
                label: 'About',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutPage())),
              ),
              _LandingNavItem(
                icon: Icons.contact_mail_rounded,
                label: 'Contact',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ContactPage())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── QUICK / SECURE / GROUPS tab bar ─────────────────────────────────────────
class _LandingTabBar extends StatefulWidget {
  @override
  State<_LandingTabBar> createState() => _LandingTabBarState();
}

class _LandingTabBarState extends State<_LandingTabBar> {
  int _selected = 0;
  static const _tabs = ['QUICK', 'SECURE', 'GROUPS'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_tabs.length, (i) {
        final selected = i == _selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selected = i),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _tabs[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.black87 : Colors.black45,
                    fontSize: context.sp(12),
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.6,
                  ),
                ),
                SizedBox(height: context.sh(5)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.black87
                        : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ── Rotating app highlight cards ─────────────────────────────────────────────
class _AppHighlightCard extends StatefulWidget {
  @override
  State<_AppHighlightCard> createState() => _AppHighlightCardState();
}

class _AppHighlightCardState extends State<_AppHighlightCard> {
  int _current = 0;
  Timer? _timer;

  static const _cards = [
    {
      'icon': Icons.flash_on_rounded,
      'title': 'Quick Transactions',
      'body': 'Lend & borrow money instantly with a single tap — no delays.',
      'color': Color(0xFF0077B6),
    },
    {
      'icon': Icons.shield_rounded,
      'title': 'Secure Transactions',
      'body': 'OTP-verified lending with interest calculation & repayment schedule.',
      'color': Color(0xFF00B4D8),
    },
    {
      'icon': Icons.groups_rounded,
      'title': 'Group Expenses',
      'body': 'Split bills fairly among friends and settle group expenses easily.',
      'color': Color(0xFF0096C7),
    },
    {
      'icon': Icons.account_balance_wallet_rounded,
      'title': 'LenDen Wallet',
      'body': 'In-app wallet for instant payments, top-ups & withdrawals.',
      'color': Color(0xFF023E8A),
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'title': 'QR Payments',
      'body': 'Scan a QR code to pay friends or receive money instantly.',
      'color': Color(0xFF0077B6),
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Smart Insights',
      'body': 'AI-powered spending analysis and personalized money tips.',
      'color': Color(0xFF00B4D8),
    },
    {
      'icon': Icons.savings_rounded,
      'title': 'Savings Goals',
      'body': 'Set financial targets, track progress and celebrate milestones.',
      'color': Color(0xFF0096C7),
    },
    {
      'icon': Icons.monetization_on_rounded,
      'title': 'LenDen Coins',
      'body': 'Earn coins for every activity and redeem them for rewards.',
      'color': Color(0xFF023E8A),
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _current = (_current + 1) % _cards.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = _cards[_current];
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Container(
            key: ValueKey(_current),
            width: double.infinity,
            padding: EdgeInsets.all(context.sw(18)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About this app',
                  style: TextStyle(
                    fontSize: context.sp(11),
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: context.sh(8)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      card['icon'] as IconData,
                      color: Colors.black87,
                      size: context.sp(20),
                    ),
                    SizedBox(width: context.sw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['title'] as String,
                            style: TextStyle(
                              fontSize: context.sp(15),
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: context.sh(5)),
                          Text(
                            card['body'] as String,
                            style: TextStyle(
                              fontSize: context.sp(13),
                              color: Colors.black54,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.sh(8)),
        // Page dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_cards.length, (i) {
            final active = i == _current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: active ? 16 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: active ? Colors.black54 : Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Avatar cluster ────────────────────────────────────────────────────────────
class _AvatarCluster extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF0077B6),
      Color(0xFF00B4D8),
      Color(0xFF48CAE4),
    ];
    const icons = [Icons.person, Icons.face, Icons.account_circle];
    return SizedBox(
      width: context.sw(68),
      height: context.sw(28),
      child: Stack(
        children: List.generate(3, (i) {
          return Positioned(
            left: i * context.sw(18),
            child: CircleAvatar(
              radius: context.sw(14),
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: context.sw(12),
                backgroundColor: colors[i],
                child: Icon(icons[i], color: Colors.white, size: context.sp(13)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── LenDen showcase card (Exotic Bali style) ──────────────────────────────────
class _LenDenShowcaseCard extends StatefulWidget {
  @override
  State<_LenDenShowcaseCard> createState() => _LenDenShowcaseCardState();
}

class _LenDenShowcaseCardState extends State<_LenDenShowcaseCard> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    // Sage green — matches the warm muted green of "Exotic Bali" in the reference
    const sageGreen = Color(0xFFC8CBBA);
    const darkText = Color(0xFF1A1A1A);

    return Container(
      decoration: BoxDecoration(
        color: sageGreen,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(context.sw(18), context.sh(18),
                context.sw(14), context.sh(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LenDen',
                        style: TextStyle(
                          fontSize: context.sp(26),
                          fontWeight: FontWeight.w800,
                          color: darkText,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: context.sh(2)),
                      Text(
                        'Smart Money Management',
                        style: TextStyle(
                          fontSize: context.sp(12),
                          color: darkText.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  child: Container(
                    padding: EdgeInsets.all(context.sw(8)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: darkText,
                      size: context.sp(18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Avatar + Get Started ──────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
            child: Row(
              children: [
                _AvatarCluster(),
                SizedBox(width: context.sw(12)),
                Consumer<SessionProvider>(
                  builder: (context, session, _) => GestureDetector(
                    onTap: () {
                      if (session.token != null && session.user != null) {
                        if (session.isAdmin) {
                          Navigator.pushNamed(context, '/admin/dashboard');
                        } else {
                          Navigator.pushNamed(context, '/user/dashboard');
                        }
                      } else {
                        Navigator.pushNamed(context, '/login');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.sw(14),
                          vertical: context.sh(7)),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      child: Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: context.sp(12),
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.sh(14)),
          // ── Feature row ───────────────────────────────────────
          _ShowcaseRow(
            icon: Icons.location_on_rounded,
            label: 'Quick • Secure • Group Transactions',
            darkText: darkText,
          ),
          SizedBox(height: context.sh(12)),
          // ── Two action buttons ────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
            child: Row(
              children: [
                // About button
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutPage())),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: context.sw(20),
                        vertical: context.sh(8)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    child: Text(
                      'About',
                      style: TextStyle(
                        fontSize: context.sp(13),
                        fontWeight: FontWeight.w600,
                        color: darkText,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Explore button
                Consumer<SessionProvider>(
                  builder: (context, session, _) => GestureDetector(
                    onTap: () {
                      if (session.token != null && session.user != null) {
                        if (session.isAdmin) {
                          Navigator.pushNamed(context, '/admin/dashboard');
                        } else {
                          Navigator.pushNamed(context, '/user/dashboard');
                        }
                      } else {
                        Navigator.pushNamed(context, '/login');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.sw(20),
                          vertical: context.sh(8)),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: context.sp(13),
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Collapsed: sub-items ─────────────────────────────
          if (!_collapsed) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: darkText.withValues(alpha: 0.12),
              indent: context.sw(18),
              endIndent: context.sw(18),
            ),
            SizedBox(height: context.sh(12)),
            // Sub-items: all app features
            ...[
              (Icons.flash_on_rounded,          'Quick Transactions',    'Lend & borrow instantly with one tap'),
              (Icons.shield_rounded,             'Secure Transactions',   'OTP-verified lending with interest & repayment'),
              (Icons.groups_rounded,             'Group Expenses',        'Split bills & settle group expenses fairly'),
              (Icons.account_balance_wallet_rounded, 'LenDen Wallet',    'In-app wallet for instant payments & withdrawals'),
              (Icons.qr_code_scanner_rounded,    'QR Payments',          'Scan a QR code to pay friends instantly'),
              (Icons.people_alt_rounded,         'Friend Balances',       'See exactly who owes you & what you owe'),
              (Icons.pin_rounded,                'Wallet PIN',            'Secure every payment with a 6-digit PIN'),
              (Icons.monetization_on_rounded,    'LenDen Coins',         'Earn coins for activity & redeem rewards'),
              (Icons.calendar_today_rounded,     'Due Date Calendar',     'Visual calendar of all upcoming due dates'),
              (Icons.local_offer_rounded,        'Offers & Gifts',        'Exclusive coin offers & gift card rewards'),
              (Icons.support_agent_rounded,      '24/7 Support',          'In-app help, disputes & live chat'),
              (Icons.repeat_rounded,             'Recurring Payments',    'Auto-schedule recurring payments & reminders'),
              (Icons.savings_rounded,            'Savings Goals',         'Set targets, track progress & hit milestones'),
              (Icons.pie_chart_rounded,          'Budget Planning',       'Monthly limits by category with alerts'),
              (Icons.auto_awesome_rounded,       'Smart Insights',        'AI-powered spending analysis & predictions'),
              (Icons.bar_chart_rounded,          'Reports & Analytics',   'Charts, trends & PDF export for any period'),
              (Icons.grid_view_rounded,          'Spending Heatmap',      '13-week visual calendar of daily spending'),
              (Icons.star_rounded,               'Ratings',               'Build trust by rating your counterparties'),
              (Icons.workspace_premium_rounded,  'Go Premium',            'Unlock Insights, Budget, Reports, Goals & more'),
            ].map(
              (item) => Padding(
                padding: EdgeInsets.fromLTRB(
                    context.sw(18), 0, context.sw(18), context.sh(10)),
                child: Row(
                  children: [
                    Container(
                      width: context.sw(42),
                      height: context.sw(42),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.$1,
                          color: darkText, size: context.sp(20)),
                    ),
                    SizedBox(width: context.sw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: TextStyle(
                              fontSize: context.sp(13),
                              fontWeight: FontWeight.w600,
                              color: darkText,
                            ),
                          ),
                          Text(
                            item.$3,
                            style: TextStyle(
                              fontSize: context.sp(11),
                              color: darkText.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // small image-like colored block (top-right thumbnail in reference)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/icon.png',
                        width: context.sw(40),
                        height: context.sw(40),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: context.sw(40),
                          height: context.sw(40),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.$1,
                              color: darkText.withValues(alpha: 0.5),
                              size: context.sp(18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: context.sh(4)),
          ],
        ],
      ),
    );
  }
}

class _ShowcaseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color darkText;
  const _ShowcaseRow(
      {required this.icon, required this.label, required this.darkText});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
      child: Row(
        children: [
          Icon(icon,
              size: context.sp(15),
              color: darkText.withValues(alpha: 0.6)),
          SizedBox(width: context.sw(8)),
          Text(
            label,
            style: TextStyle(
              fontSize: context.sp(13),
              color: darkText.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom navigation item ────────────────────────────────────────────────────
class _LandingNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _LandingNavItem(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.black87 : Colors.grey.shade500;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.sw(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: context.sp(22)),
            SizedBox(height: context.sh(3)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.sp(10),
                color: color,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            SizedBox(height: context.sh(3)),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: active ? Colors.black87 : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
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


