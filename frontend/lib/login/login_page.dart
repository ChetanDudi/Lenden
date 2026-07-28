import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'dart:io';
import '../otp_input.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'email_password_login.dart';
import 'username_password_login.dart';
import 'email_otp_login.dart';
import 'google_auth_service.dart';
import 'package:uuid/uuid.dart';
import '../widgets/tricolor_border_text_field.dart';
import '../widgets/google_logo_icon.dart';
import '../utils/api_client.dart';
import '../utils/http_interceptor.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../widgets/wave_widget.dart' show AltBottomWaveClipper, ScaledDeepTopWaveClipper;
import '../widgets/login_illustration.dart';

class UserLoginPage extends StatefulWidget {
  const UserLoginPage({super.key});

  @override
  State<UserLoginPage> createState() => _UserLoginPageState();
}

class _UserLoginPageState extends State<UserLoginPage> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isDeactivated = false;
  Map<String, dynamic>? _recoverInfo;
  // ignore: unused_field
  bool _requires2FA = false;
  // ignore: unused_field
  String _twoFAEmail = '';

  // Login method selection
  String _loginMethod = 'Email + Password';

  // Controllers for input fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _otpSent = false;
  bool _isVerifyingOtp = false;
  String _loginOtp = '';
  String? _otpErrorMessage;
  int _otpSecondsLeft = 0;
  String? _deviceId;

  bool get _isSubmitting => _isLoading || _isVerifyingOtp;

  @override
  void initState() {
    super.initState();
    _initDeviceId();
    // Fire-and-forget ping to wake Render before user clicks login
    ApiClient.get('/', timeout: const Duration(seconds: 90)).then<void>((_) {}, onError: (_) {});
  }

  Future<void> _initDeviceId() async {
    final session = Provider.of<SessionProvider>(context, listen: false);
    String? deviceId = await session.getDeviceId();
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await session.saveDeviceId(deviceId);
    }
    setState(() {
      _deviceId = deviceId;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _login() async {
    setState(() => _isLoading = true);
    String? error;
    dynamic userOrAdmin;
    String? userType;
    String? token;
    String? refreshToken;
    Map<String, dynamic>? dailyLoginReward;
    Map<String, dynamic>? recoverInfo;
    try {
      if (_loginMethod == 'Email + Password') {
        final result = await EmailPasswordLogin.login(
          email: _emailController.text,
          password: _passwordController.text,
          context: context,
          deviceId: _deviceId ?? '', // Pass non-null String
        );

        if (result['success']) {
          userOrAdmin = result['userOrAdmin'];
          userType = result['userType'];
          token = result['accessToken'];
          refreshToken = result['refreshToken'];
          dailyLoginReward =
              result['dailyLoginReward'] as Map<String, dynamic>?;
        } else if (result['requires2FA'] == true) {
          setState(() {
            _twoFAEmail = result['email'] as String;
            _requires2FA = true;
          });
          _show2FADialog(result['email'] as String);
          return;
        } else {
          error = result['error'];
          if (result['canRecover'] == true) {
            recoverInfo = result;
          }
        }
      } else if (_loginMethod == 'Username + Password') {
        final result = await UsernamePasswordLogin.login(
          username: _usernameController.text,
          password: _passwordController.text,
          context: context,
          deviceId: _deviceId ?? '',
        );

        if (result['success']) {
          userOrAdmin = result['data'];
          userType = result['userType'];
          token = result['accessToken'];
          refreshToken = result['refreshToken'];
          dailyLoginReward =
              result['dailyLoginReward'] as Map<String, dynamic>?;
        } else if (result['requires2FA'] == true) {
          setState(() {
            _twoFAEmail = result['email'] as String;
            _requires2FA = true;
          });
          _show2FADialog(result['email'] as String);
          return;
        } else {
          error = result['error'];
          if (result['canRecover'] == true) {
            recoverInfo = result;
          }
        }
      } else if (_loginMethod == 'Email + OTP') {
        if (!_otpSent) {
          setState(() => _isLoading = true);
          final result = await EmailOtpLogin.sendOtp(
            email: _emailController.text,
            context: context,
          );
          setState(() => _isLoading = false);

          if (result['success']) {
            setState(() {
              _otpSent = true;
              _otpErrorMessage = null;
              _otpSecondsLeft = 120;
            });
            _startOtpTimer();
            return; // Return early to wait for OTP input
          } else {
            setState(() {
              _otpErrorMessage = result['error'];
            });
            return; // Return early on error
          }
        } else if (_otpSecondsLeft > 0) {
          setState(() => _isVerifyingOtp = true);
          final result = await EmailOtpLogin.verifyOtp(
            email: _emailController.text,
            otp: _loginOtp,
            context: context,
            deviceId: _deviceId ?? '',
          );
          setState(() => _isVerifyingOtp = false);

          if (result['success']) {
            setState(() {
              _otpSent = false;
              _loginOtp = '';
              _otpErrorMessage = null;
              _otpSecondsLeft = 0;
            });
            userOrAdmin = result['userOrAdmin'];
            userType = result['userType'];
            token = result['accessToken'];
            refreshToken = result['refreshToken'];
            dailyLoginReward =
                result['dailyLoginReward'] as Map<String, dynamic>?;
          } else {
            setState(() {
              _otpErrorMessage = result['error'];
            });
            return; // Return early on error
          }
        }
      }

      // Save tokens and fetch user info
      if (token != null && refreshToken != null && userType != null) {
        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.saveTokens(token, refreshToken);

        // For Email + OTP, also fetch the complete profile to ensure all fields are present
        if (_loginMethod == 'Email + OTP' && userOrAdmin != null) {
          final userData = Map<String, dynamic>.from(userOrAdmin);

          if (!userData.containsKey('name') || userData['name'] == null) {
            userData['name'] = userData['username'] ?? 'User';
          }
          if (!userData.containsKey('email') || userData['email'] == null) {
            userData['email'] = _emailController.text;
          }
          if (!userData.containsKey('username') ||
              userData['username'] == null) {
            userData['username'] = userData['name'] ?? 'user';
          }

          userData['role'] = userType == 'admin' ? 'admin' : 'user';

          final profileRes = await _fetchProfile(token, userType);
          if (profileRes != null) {
            final completeUserData = Map<String, dynamic>.from(profileRes);
            completeUserData['role'] = userType == 'admin' ? 'admin' : 'user';
            session.setUser(completeUserData);
            await session.checkSubscriptionStatus();
          } else {
            session.setUser(userData);
            await session.checkSubscriptionStatus();
          }
        } else {
          // For other login methods, fetch profile
          final profileRes = await _fetchProfile(token, userType);
          if (profileRes != null) {
            profileRes['role'] = userType == 'admin' ? 'admin' : 'user';
            session.setUser(profileRes);
            await session.checkSubscriptionStatus();
          }
        }
      }

      if (userOrAdmin != null && userType != null) {
        // Show daily login reward notification if user earned coins today
        if (dailyLoginReward != null && dailyLoginReward['awarded'] == true) {
          final coins = dailyLoginReward['coinsAwarded'] ?? 1;
          if (mounted) {
            _showDailyLoginRewardNotification(coins);
          }
          // Add a small delay to ensure the animation is visible
          await Future.delayed(const Duration(seconds: 3));
        }

        // Navigate to dashboard
        if (userType == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin/dashboard');
        } else {
          Navigator.pushReplacementNamed(context, '/user/dashboard');
        }
      } else if (recoverInfo != null) {
        setState(() {
          _isDeactivated = true;
          _recoverInfo = recoverInfo;
        });
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(content: Text(error ?? 'This account is deactivated.')),
        // );
      } else if (error != null) {
        if (error == 'network_error') {
          _showGoogleNetworkErrorDialog();
        } else if (error == 'Incorrect password') {
          _showIncorrectPasswordDialog();
        } else {
          _showUserNotFoundDialog();
        }
      }
    } catch (e) {
      if (e is SocketException) {
        _showGoogleNetworkErrorDialog();
      } else {
        _showErrorDialog('Login failed. Please try again.');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loginWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await GoogleAuthService.loginWithGoogle(
        deviceId: _deviceId,
      );

      if (result['success'] == true) {
        final userOrAdmin = result['userOrAdmin'];
        final userType = result['userType'] as String;
        final token = result['accessToken'] as String;
        final refreshToken = result['refreshToken'] as String;
        final dailyLoginReward =
            result['dailyLoginReward'] as Map<String, dynamic>?;

        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.saveTokens(token, refreshToken);

        final profileRes = await _fetchProfile(token, userType);
        if (profileRes != null) {
          profileRes['role'] = userType == 'admin' ? 'admin' : 'user';
          session.setUser(profileRes);
        } else {
          final userData = Map<String, dynamic>.from(userOrAdmin);
          userData['role'] = userType == 'admin' ? 'admin' : 'user';
          session.setUser(userData);
        }
        await session.checkSubscriptionStatus();

        if (dailyLoginReward != null && dailyLoginReward['awarded'] == true) {
          final coins = dailyLoginReward['coinsAwarded'] ?? 1;
          if (mounted) {
            _showDailyLoginRewardNotification(coins);
          }
          await Future.delayed(const Duration(seconds: 3));
        }

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            userType == 'admin' ? '/admin/dashboard' : '/user/dashboard',
          );
        }
      } else if (result['requires2FA'] == true) {
        setState(() {
          _requires2FA = true;
          _twoFAEmail = result['email'] as String;
        });
        _show2FADialog(result['email'] as String);
      } else if (result['cancelled'] != true) {
        if (result['error'] == 'network_error') {
          _showGoogleNetworkErrorDialog();
        } else {
          _showErrorDialog(result['error'] ?? 'Google sign-in failed.');
        }
      }
    } catch (e) {
      _showErrorDialog('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Widget _buildLoginMethodSelector(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _methodChip(context, i)),
        ],
      ],
    );
  }

  Widget _methodChip(BuildContext context, int i) {
    final keys = ['Email + Password', 'Email + OTP', 'Username + Password'];
    final labels = ['Email\n& Password', 'Email\n& OTP', 'Username\n& Pass'];
    final icons = [Icons.email_outlined, Icons.mark_email_read_outlined, Icons.person_outline_rounded];
    final key = keys[i];
    final selected = _loginMethod == key;
    return GestureDetector(
      onTap: _isSubmitting ? null : () => setState(() => _loginMethod = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.cyan : AppThemeColors.divider(context),
            width: selected ? 0 : 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icons[i], size: 22, color: selected ? Colors.white : AppThemeColors.secondaryText(context)),
            const SizedBox(height: 6),
            Text(
              labels[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.3,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? Colors.white : AppThemeColors.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeactivatedAccountWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1),
      ),
      child: Column(
        children: [
          Text(
            'This account has been deactivated.',
            style: TextStyle(
                fontSize: context.sp(15), fontWeight: FontWeight.bold, color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Would you like to recover it and log in?',
            style: TextStyle(
                fontSize: context.sp(13),
                color: AppThemeColors.primaryText(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _recoverAccountAndLogin(_recoverInfo!),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              padding: EdgeInsets.symmetric(
                  vertical: context.sh(10), horizontal: context.sw(20)),
            ),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Text('Recovering...',
                          style: TextStyle(
                              fontSize: context.sp(15), color: Colors.white)),
                    ],
                  )
                : Text('Recover & Login',
                    style: TextStyle(
                        fontSize: context.sp(15), color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _recoverAccountAndLogin(Map<String, dynamic> recoverInfo) async {
    setState(() => _isLoading = true);
    try {
      final emailOrUsername = recoverInfo['email'] ?? recoverInfo['username'];
      final response = await HttpInterceptor.post(
        '/api/users/recover-account',
        body: {'emailOrUsername': emailOrUsername},
      );
      if (response.statusCode == 200) {
        // After recovery, try login again
        _login();
      } else {
        final errorData = json.decode(response.body);
        _showErrorDialog(errorData['error'] ?? 'Failed to recover account');
      }
    } catch (e) {
      if (e is SocketException) {
        _showGoogleNetworkErrorDialog();
      } else {
        _showErrorDialog('Failed to recover account. Please try again.');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile(
      String token, String userType) async {
    final path = userType == 'admin' ? '/api/admins/me' : '/api/users/me';
    try {
      final response = await HttpInterceptor.get(path);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  void _startOtpTimer() {
    _otpSecondsLeft = 120;
    Future.doWhile(() async {
      if (_otpSecondsLeft > 0 && mounted && _otpSent) {
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          _otpSecondsLeft--;
        });
        return true;
      }
      return false;
    });
  }

  void _show2FADialog(String email) {
    final secondsNotifier = ValueNotifier<int>(120);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (secondsNotifier.value > 0) {
        secondsNotifier.value--;
        return true;
      }
      return false;
    });

    String twoFACode = '';
    bool isVerifying = false;
    String? errorMsg;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            backgroundColor: AppThemeColors.cardBg(ctx2),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0077B6), AppColors.cyan],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.cyan.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Two-Factor Authentication',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(ctx2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code sent to\n$email',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.secondaryText(ctx2),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  OtpInput(
                    onChanged: (code) => setDialogState(() => twoFACode = code),
                    enabled: !isVerifying,
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<int>(
                    valueListenable: secondsNotifier,
                    builder: (_, secs, __) => Text(
                      secs > 0 ? 'Code expires in ${secs}s' : 'Code expired',
                      style: TextStyle(
                        fontSize: 12,
                        color: secs > 0
                            ? AppThemeColors.secondaryText(ctx2)
                            : Colors.red,
                      ),
                    ),
                  ),
                  if (errorMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isVerifying
                              ? null
                              : () {
                                  setState(() {
                                    _requires2FA = false;
                                    _twoFAEmail = '';
                                  });
                                  Navigator.of(ctx).pop();
                                },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppThemeColors.border(ctx2)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppThemeColors.secondaryText(ctx2),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (isVerifying || twoFACode.length < 6)
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isVerifying = true;
                                    errorMsg = null;
                                  });
                                  final result = await EmailOtpLogin.verifyOtp(
                                    email: email,
                                    otp: twoFACode,
                                    context: ctx2,
                                    deviceId: _deviceId ?? '',
                                  );
                                  if (result['success'] == true) {
                                    secondsNotifier.dispose();
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                    await _finalizeTwoFALogin(result);
                                  } else {
                                    setDialogState(() {
                                      isVerifying = false;
                                      errorMsg = result['error'] ?? 'Invalid code. Please try again.';
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: isVerifying
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Verify',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _finalizeTwoFALogin(Map<String, dynamic> result) async {
    if (!mounted) return;
    final token = result['accessToken'] as String?;
    final refreshToken = result['refreshToken'] as String?;
    final userType = result['userType'] as String?;
    final userOrAdmin = result['userOrAdmin'];
    final dailyLoginReward = result['dailyLoginReward'] as Map<String, dynamic>?;

    if (token == null || refreshToken == null || userType == null) return;

    final session = Provider.of<SessionProvider>(context, listen: false);
    await session.saveTokens(token, refreshToken);

    final profileRes = await _fetchProfile(token, userType);
    if (profileRes != null) {
      profileRes['role'] = userType == 'admin' ? 'admin' : 'user';
      session.setUser(profileRes);
    } else if (userOrAdmin != null) {
      final userData = Map<String, dynamic>.from(userOrAdmin as Map);
      userData['role'] = userType == 'admin' ? 'admin' : 'user';
      session.setUser(userData);
    }
    await session.checkSubscriptionStatus();

    if (!mounted) return;

    setState(() {
      _requires2FA = false;
      _twoFAEmail = '';
    });

    if (dailyLoginReward != null && dailyLoginReward['awarded'] == true) {
      final coins = dailyLoginReward['coinsAwarded'] ?? 1;
      _showDailyLoginRewardNotification(coins);
      await Future.delayed(const Duration(seconds: 3));
    }

    if (!mounted) return;

    if (userType == 'admin') {
      Navigator.pushReplacementNamed(context, '/admin/dashboard');
    } else {
      Navigator.pushReplacementNamed(context, '/user/dashboard');
    }
  }

  void _showIncorrectPasswordDialog() {
    if (_loginMethod == 'Email + Password') {
      EmailPasswordLogin.showIncorrectPasswordDialog(context);
    } else if (_loginMethod == 'Username + Password') {
      UsernamePasswordLogin.showIncorrectPasswordDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auth screens always render in English, regardless of the user's saved
    // app language — they're shown before any user/locale is established.
    return Localizations.override(
      context: context,
      locale: const Locale('en'),
      child: Builder(builder: _buildPage),
    );
  }

  Widget _buildPage(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: Stack(
          children: [
            // Top blue shape
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: const ScaledDeepTopWaveClipper(),
                child: Container(
                  height: context.sh(78),
                  color: AppThemeColors.waveSolid(context),
                ),
              ),
            ),
            SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.hPadding, vertical: context.vPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: context.sh(18)),
                      Text(t('login'),
                          style: TextStyle(
                              fontSize: context.sp(28),
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context)),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text(t('welcome_back'),
                          style: TextStyle(fontSize: context.sp(15), color: AppThemeColors.primaryText(context)),
                          textAlign: TextAlign.center),
                      SizedBox(height: context.sh(28)),
                      LoginIllustration(height: context.sh(160)),
                      const SizedBox(height: 24),
                      if (_isDeactivated) _buildDeactivatedAccountWidget(),
                      // Login method selector — styled icon chips
                      _buildLoginMethodSelector(context),
                      const SizedBox(height: 18),
                      // Dynamic input fields based on login method
                      if (_loginMethod == 'Email + Password') ...[
                        TricolorBorderTextField(
                          child: TextField(
                            controller: _emailController,
                            enabled: !_isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TricolorBorderTextField(
                          child: TextField(
                            controller: _passwordController,
                            enabled: !_isSubmitting,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 18),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: _isSubmitting
                                    ? null
                                    : () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                        ),
                      ] else if (_loginMethod == 'Username + Password') ...[
                        TricolorBorderTextField(
                          child: TextField(
                            controller: _usernameController,
                            enabled: !_isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Username',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TricolorBorderTextField(
                          child: TextField(
                            controller: _passwordController,
                            enabled: !_isSubmitting,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 18),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                onPressed: _isSubmitting
                                    ? null
                                    : () => setState(() =>
                                        _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                        ),
                      ] else if (_loginMethod == 'Email + OTP') ...[
                        TricolorBorderTextField(
                          child: TextField(
                            controller: _emailController,
                            enabled: !_otpSent && !_isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 18),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        if (!_otpSent) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Sending OTP...',
                                            style: TextStyle(
                                                fontSize: context.sp(17),
                                                color: Colors.white)),
                                      ],
                                    )
                                  : Text('Send OTP',
                                      style: TextStyle(
                                          fontSize: context.sp(17), color: Colors.white)),
                            ),
                          ),
                          if (_otpErrorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(_otpErrorMessage!,
                                  style: const TextStyle(color: Colors.red)),
                            ),
                        ] else ...[
                          OtpInput(
                            onChanged: _isSubmitting
                                ? (_) {}
                                : (val) => setState(() => _loginOtp = val),
                            enabled: _otpSecondsLeft > 0 && !_isSubmitting,
                            autoFocus: true,
                          ),
                          const SizedBox(height: 10),
                          if (_otpSecondsLeft > 0)
                            Text(
                                'OTP expires in  ${_otpSecondsLeft ~/ 60}:${(_otpSecondsLeft % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Colors.grey)),
                          if (_otpSecondsLeft == 0)
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() {
                                        _otpSent = false;
                                        _loginOtp = '';
                                        _otpErrorMessage = null;
                                      });
                                    },
                              child: const Text('Resend OTP'),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isSubmitting ||
                                      _loginOtp.length != 6 ||
                                      _otpSecondsLeft == 0
                                  ? null
                                  : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.cyan,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isVerifyingOtp
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        ),
                                        SizedBox(width: 10),
                                        Text('Verifying & Logging in...',
                                            style: TextStyle(
                                                fontSize: context.sp(17),
                                                color: Colors.white)),
                                      ],
                                    )
                                  : Text('Verify & Login',
                                      style: TextStyle(
                                          fontSize: context.sp(17), color: Colors.white)),
                            ),
                          ),
                          if (_otpErrorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(_otpErrorMessage!,
                                  style: const TextStyle(color: Colors.red)),
                            ),
                        ],
                      ],
                      const SizedBox(height: 10),
                      if (_loginMethod != 'Email + OTP')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : (_isDeactivated
                                    ? () =>
                                        _recoverAccountAndLogin(_recoverInfo!)
                                    : _login),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24)),
                              padding: EdgeInsets.zero,
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.cyan,
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: _isLoading
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
                                          ),
                                          SizedBox(width: 10),
                                          Text(
                                            _isDeactivated
                                                ? 'Recovering...'
                                                : 'Logging in...',
                                            style: TextStyle(
                                                fontSize: context.sp(17),
                                                color: Colors.white),
                                          ),
                                        ],
                                      )
                                    : Center(
                                        child: Text(
                                            _isDeactivated
                                                ? 'Recover & Login'
                                                : 'Login',
                                            style: TextStyle(
                                                fontSize: context.sp(17),
                                                color: Colors.white)),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                              child: Divider(
                                  color: AppThemeColors.divider(context))),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(t('or'),
                                style: TextStyle(
                                    fontSize: context.sp(13),
                                    color:
                                        AppThemeColors.secondaryText(context))),
                          ),
                          Expanded(
                              child: Divider(
                                  color: AppThemeColors.divider(context))),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TricolorBorderTextField(
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isSubmitting || _isGoogleLoading
                                ? null
                                : _loginWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _isGoogleLoading
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppThemeColors.primaryText(
                                            context)),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      const GoogleLogoIcon(size: 18),
                                      const SizedBox(width: 10),
                                      Text(t('sign_in_with_google'),
                                          style: TextStyle(
                                              fontSize: context.sp(15),
                                              fontWeight: FontWeight.w600,
                                              color: AppThemeColors
                                                  .primaryText(context))),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("I Don\'t Have an Account ? ",
                              style: TextStyle(
                                  fontSize: context.sp(13),
                                  color: AppThemeColors.primaryText(context))),
                          GestureDetector(
                            onTap: _isSubmitting
                                ? null
                                : () =>
                                    Navigator.pushNamed(context, '/register'),
                            child: Text(
                              'Register',
                              style: TextStyle(
                                color: AppColors.cyan,
                                fontWeight: FontWeight.bold,
                                fontSize: context.sp(13),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipPath(
                clipper: const AltBottomWaveClipper(),
                child: Container(
                  height: context.sh(75),
                  color: AppColors.cyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserNotFoundDialog() {
    if (_loginMethod == 'Email + Password') {
      EmailPasswordLogin.showUserNotFoundDialog(context);
    } else if (_loginMethod == 'Username + Password') {
      UsernamePasswordLogin.showUserNotFoundDialog(context);
    }
  }

  void _showErrorDialog(String message) {
    if (_loginMethod == 'Email + OTP') {
      EmailOtpLogin.showErrorDialog(context, message);
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  void _showGoogleNetworkErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_off_rounded, size: 34, color: Colors.orange),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Internet Connection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Login requires an active internet connection.\nPlease check your Wi-Fi or mobile data and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDailyLoginRewardNotification(int coins) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 16,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: EdgeInsets.all(context.sw(22)),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: context.sw(72),
                    height: context.sw(72),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.card_giftcard_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                SizedBox(height: context.sh(18)),
                Text(
                  'Daily Bonus! 🎉',
                  style: TextStyle(
                    fontSize: context.sp(22),
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: context.sh(10)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'You earned',
                      style: TextStyle(
                        fontSize: context.sp(15),
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFD700),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        '$coins LenDen Coin${coins > 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: context.sp(15),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.sh(10)),
                Text(
                  'Keep logging in daily to earn more coins!',
                  style: TextStyle(
                    fontSize: context.sp(12),
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: context.sh(20)),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      padding: EdgeInsets.symmetric(vertical: context.sh(12)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      'Awesome!',
                      style: TextStyle(
                        fontSize: context.sp(15),
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      // Ensure the dialog is fully closed before navigation
      if (mounted) {
        setState(() {});
      }
    });
  }
}

class SocialIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const SocialIconButton(
      {required this.icon,
      required this.color,
      required this.onTap,
      super.key});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: FaIcon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
