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
import 'admin/manage_users/user_management_page.dart';
import 'admin/transactions/manage_secure_transactions_page.dart';
import 'admin/transactions/manage_group_transactions_page.dart';
import 'splash_screen.dart';
import 'user/support/feedback.dart';
import 'admin/rating/admin_ratings_page.dart';
import 'admin/support/admin_feedbacks_page.dart';
import 'user/connections/counterparties_page.dart';
import 'utils/auth_navigation.dart';
import 'utils/api_client.dart';
import 'utils/responsive.dart';
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
import 'home/home_page.dart';

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

    // App version check â€” force-update if server says current version is too old
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

    // Each user/admin keeps their own theme and language â€” scope the loaded
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
      // Navigator not mounted yet â€” retry next frame.
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

