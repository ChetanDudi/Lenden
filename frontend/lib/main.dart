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
import 'screens/maintenance_screen.dart';
import 'widgets/wave_widget.dart' show DeepTopWaveClipper;
import 'widgets/no_internet_banner.dart';
import 'user/digitise/subscriptions_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ConnectivityService().init();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exceptionAsString()}');
  };
  runZonedGuarded(
    () => runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SessionProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ],
        child: const AppInitializer(),
      ),
    ),
    (error, stack) => debugPrint('Uncaught error: $error\n$stack'),
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
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
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
      body: Stack(
        children: [
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
                            icon: Icon(Icons.menu, color: AppThemeColors.primaryText(context)),
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
                                        builder: (dlgCtx) {
                                          final dt = AppLocalizations.of(dlgCtx).t;
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
                                                        fontSize: context.sp(20))),
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
                                                  backgroundColor:
                                                      AppColors.cyan,
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
                                                          fontSize: context.sp(15))),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
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
                            t('landing_tagline'),
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
                            label: Text(t('get_started'),
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
                            label: Text(t('register'),
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
  final bool isPremium;
  const _FeatureCard(
      {required this.icon,
      required this.title,
      required this.description,
      this.isPremium = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: context.sw(170),
      margin: EdgeInsets.symmetric(horizontal: context.sw(8), vertical: context.sh(8)),
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        gradient: isPremium
            ? const LinearGradient(
                colors: [Color(0xFFFFB300), Color(0xFFFFF8E1), Color(0xFFFF8F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(15.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    color: isPremium ? const Color(0xFFFFB300) : AppColors.cyan,
                    size: context.sp(26)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber, width: 0.8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.workspace_premium, size: 9, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(isPremium ? 'Premium' : 'Free',
                        style: TextStyle(
                            fontSize: context.sp(8),
                            color: isPremium ? Colors.amber : Colors.teal,
                            fontWeight: FontWeight.bold)),
                  ]),
                ),
              ],
            ),
            SizedBox(height: context.sh(4)),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: context.sp(13),
                    color: AppThemeColors.primaryText(context))),
            SizedBox(height: context.sh(2)),
            Text(
              description,
              style: TextStyle(
                  color: AppThemeColors.secondaryText(context),
                  fontSize: context.sp(11)),
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
      'icon': Icons.flash_on_rounded,
      'title': 'Quick Transactions',
      'description': 'Lend & borrow instantly with one tap.'
    },
    {
      'icon': Icons.shield_rounded,
      'title': 'Secure Transactions',
      'description': 'OTP-verified lending with interest & repayment schedule.'
    },
    {
      'icon': Icons.groups_rounded,
      'title': 'Group Expenses',
      'description': 'Split bills and settle group expenses fairly.'
    },
    {
      'icon': Icons.account_balance_wallet_rounded,
      'title': 'LenDen Wallet',
      'description': 'In-app wallet for instant payments & withdrawals.'
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'title': 'QR Payments',
      'description': 'Scan a QR code to pay friends instantly.'
    },
    {
      'icon': Icons.savings_rounded,
      'title': 'Savings Goals',
      'description': 'Set targets, track progress & hit your goals.',
      'isPremium': true,
    },
    {
      'icon': Icons.pie_chart_rounded,
      'title': 'Budget Planning',
      'description': 'Monthly limits by type & category with alerts.',
      'isPremium': true,
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Smart Insights',
      'description': 'AI-powered spending analysis & predictions.',
      'isPremium': true,
    },
    {
      'icon': Icons.bar_chart_rounded,
      'title': 'Reports & Analytics',
      'description': 'Charts, trends & PDF export for any period.',
      'isPremium': true,
    },
    {
      'icon': Icons.grid_view_rounded,
      'title': 'Spending Heatmap',
      'description': '13-week visual calendar of your daily spending.',
      'isPremium': true,
    },
    {
      'icon': Icons.people_alt_rounded,
      'title': 'Friend Balances',
      'description': 'See exactly who owes you and what you owe.'
    },
    {
      'icon': Icons.monetization_on_rounded,
      'title': 'LenDen Coins',
      'description': 'Earn coins for activity & redeem rewards.'
    },
    {
      'icon': Icons.repeat_rounded,
      'title': 'Recurring Transactions',
      'description': 'Auto-schedule recurring payments & reminders.',
      'isPremium': true,
    },
    {
      'icon': Icons.pin_rounded,
      'title': 'Wallet PIN',
      'description': 'Secure every outgoing payment with a 6-digit PIN.'
    },
    {
      'icon': Icons.calendar_today_rounded,
      'title': 'Due Date Calendar',
      'description': 'Visual calendar of all upcoming due dates.'
    },
    {
      'icon': Icons.star_rounded,
      'title': 'Ratings',
      'description': 'Build trust by rating your counterparties.',
      'isPremium': true,
    },
    {
      'icon': Icons.local_offer_rounded,
      'title': 'Offers & Gifts',
      'description': 'Exclusive coin offers & gift card rewards.'
    },
    {
      'icon': Icons.support_agent_rounded,
      'title': '24/7 Support',
      'description': 'In-app help, disputes & live support queries.'
    },
    {
      'icon': Icons.workspace_premium_rounded,
      'title': 'Go Premium',
      'description': 'Unlock Insights, Budget, Reports, Goals & more.',
      'isPremium': true,
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
        final card = _FeatureCard(
          icon: feature['icon'],
          title: feature['title'],
          description: feature['description'],
          isPremium: (feature['isPremium'] as bool?) ?? false,
        );
        return Transform.scale(
          scale: isActive ? 1.08 : 0.92,
          child: Opacity(
            opacity: isActive ? 1 : 0.7,
            child: feature['title'] == 'Go Premium'
                ? GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
                    child: card,
                  )
                : card,
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


