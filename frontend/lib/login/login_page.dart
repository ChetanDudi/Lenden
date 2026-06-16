import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import '../otp_input.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'email_password_login.dart';
import 'username_password_login.dart';
import 'email_otp_login.dart';
import 'package:uuid/uuid.dart';
import '../widgets/tricolor_border_text_field.dart';
import 'dart:ui' as ui;
import '../utils/api_client.dart';
import '../utils/http_interceptor.dart';
import '../utils/responsive.dart';

class UserLoginPage extends StatefulWidget {
  const UserLoginPage({super.key});

  @override
  State<UserLoginPage> createState() => _UserLoginPageState();
}

class _UserLoginPageState extends State<UserLoginPage> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _isDeactivated = false;
  Map<String, dynamic>? _recoverInfo;

  // Login method selection
  String _loginMethod = 'Email + Password';
  final List<String> _loginMethods = [
    'Email + Password',
    'Email + OTP',
    'Username + Password',
  ];

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
        if (error == 'Incorrect password') {
          _showIncorrectPasswordDialog();
        } else {
          _showUserNotFoundDialog();
        }
      }
    } catch (e) {
      _showErrorDialog('Login failed. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
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
            style: TextStyle(fontSize: context.sp(13), color: Colors.black87),
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
      _showErrorDialog('Failed to recover account. Please try again.');
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

  void _showIncorrectPasswordDialog() {
    if (_loginMethod == 'Email + Password') {
      EmailPasswordLogin.showIncorrectPasswordDialog(context);
    } else if (_loginMethod == 'Username + Password') {
      UsernamePasswordLogin.showIncorrectPasswordDialog(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
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
                clipper: TopWaveClipper(),
                child: Container(
                  height: context.sh(110),
                  color: AppColors.cyan,
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
                      Text('Login',
                          style: TextStyle(
                              fontSize: context.sp(28),
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('Hello Welcome Back',
                          style: TextStyle(fontSize: context.sp(15), color: Colors.black),
                          textAlign: TextAlign.center),
                      SizedBox(height: context.sh(28)),
                      LoginIllustration(height: context.sh(160)),
                      const SizedBox(height: 24),
                      if (_isDeactivated) _buildDeactivatedAccountWidget(),
                      // Dropdown for login method
                      TricolorBorderTextField(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          child: DropdownButton<String>(
                            value: _loginMethod,
                            isExpanded: true,
                            underline: const SizedBox(),
                            items: _loginMethods.map((method) {
                              return DropdownMenuItem<String>(
                                value: method,
                                child: Text(method),
                              );
                            }).toList(),
                            onChanged: _isSubmitting
                                ? null
                                : (value) {
                                    setState(() {
                                      _loginMethod = value!;
                                    });
                                  },
                          ),
                        ),
                      ),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("I Don\'t Have an Account ? ",
                              style: TextStyle(fontSize: context.sp(13))),
                          GestureDetector(
                            onTap: _isSubmitting
                                ? null
                                : () =>
                                    Navigator.pushNamed(context, '/register'),
                            child: Text(
                              'Register',
                              style: TextStyle(
                                color: Colors.black,
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
                clipper: BottomWaveClipper(),
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

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    // Start at top-left
    path.lineTo(0, size.height * 0.525); // 0.7 × ¾ = 0.525

    // First curve
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.75, // 1.0 × ¾ = 0.75
      size.width * 0.5,
      size.height * 0.525,
    );

    // Second curve
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3, // 0.4 × ¾ = 0.3
      size.width,
      size.height * 0.525,
    );

    // Close path at top-right
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class LoginIllustration extends StatelessWidget {
  final double height;

  const LoginIllustration({
    Key? key,
    this.height = 220,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: LoginIllustrationPainter(),
        child: Container(),
      ),
    );
  }
}

class LoginIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Responsive base values
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Convenience function for scaled lengths
    double sw(double fraction) => w * fraction;
    double sh(double fraction) => h * fraction;

    // Background light circle / blob behind illustration
    final bgPaint = Paint()..color = const Color(0xFFF3F6FA);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - sh(0.05)),
        width: sw(0.9),
        height: sh(0.95),
      ),
      bgPaint,
    );

    // Large decorative circle behind phone
    final decorPaint = Paint()..color = const Color(0xFFEEF6F9);
    canvas.drawCircle(
        Offset(cx - sw(0.18), cy - sh(0.18)), sw(0.28), decorPaint);

    // Rounded rectangle "paper" behind person (like a panel)
    final panelPaint = Paint()..color = const Color(0xFFF6FBFD);
    final panelRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx + sw(0.22), cy + sh(0.05)),
            width: sw(0.52),
            height: sh(0.7)),
        Radius.circular(18));
    canvas.drawRRect(panelRect, panelPaint);

    // Subtle horizontal lines on left behind phone (to mimic lined background)
    final linePaint = Paint()..color = const Color(0xFFEFF7F8);
    for (var i = -2; i <= 3; i++) {
      final y = cy - sh(0.35) + i * sh(0.08);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - sw(0.5), y, sw(0.4), sh(0.01)),
            Radius.circular(6),
          ),
          linePaint);
    }

    // --- PHONE (left side) ---
    final phoneCenter = Offset(cx - sw(0.18), cy - sh(0.08));
    final phoneW = sw(0.22);
    final phoneH = sh(0.44);
    final phoneRadius = 14.0;

    final phoneOuterPaint = Paint()..color = const Color(0xFF2E3A49);
    final phoneOuter = RRect.fromRectAndRadius(
      Rect.fromCenter(center: phoneCenter, width: phoneW, height: phoneH),
      Radius.circular(phoneRadius),
    );
    canvas.drawRRect(phoneOuter, phoneOuterPaint);

    // Phone inner screen
    final screenInset = 6.0;
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        phoneCenter.dx - phoneW / 2 + screenInset,
        phoneCenter.dy - phoneH / 2 + screenInset,
        phoneW - screenInset * 2,
        phoneH - screenInset * 2,
      ),
      Radius.circular(10),
    );
    final screenPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(screenRect.left, screenRect.top),
        Offset(screenRect.left, screenRect.bottom),
        [const Color(0xFFECF8FF), const Color(0xFFD9F0FF)],
      );
    canvas.drawRRect(screenRect, screenPaint);

    // Phone notch and top icons
    final notchPaint = Paint()
      ..color = const Color(0xFFEAF7FF).withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(phoneCenter.dx, phoneCenter.dy - phoneH / 2 + 20),
            width: phoneW * 0.28,
            height: 8),
        Radius.circular(6),
      ),
      notchPaint,
    );

    // Phone screen content: top shield icon
    final shieldPaint = Paint()
      ..color = const Color(0xFF2B8BC6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final shieldCenter = Offset(phoneCenter.dx, phoneCenter.dy - phoneH * 0.18);
    canvas.drawCircle(shieldCenter, sw(0.02), shieldPaint);
    // small check mark inside
    final tickPath = Path();
    tickPath.moveTo(shieldCenter.dx - sw(0.01), shieldCenter.dy);
    tickPath.lineTo(shieldCenter.dx - sw(0.002), shieldCenter.dy + sh(0.01));
    tickPath.lineTo(shieldCenter.dx + sw(0.013), shieldCenter.dy - sh(0.008));
    final tickPaint = Paint()
      ..color = const Color(0xFF2B8BC6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(tickPath, tickPaint);

    // Login fields on phone
    final fieldPaint = Paint()..color = Colors.white;
    final fieldRadius = 8.0;
    double yStart = phoneCenter.dy - phoneH * 0.07;
    for (int i = 0; i < 3; i++) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          phoneCenter.dx - phoneW * 0.34 / 2 + screenInset + 6,
          yStart + i * sh(0.06),
          phoneW * 0.34,
          sh(0.04),
        ),
        Radius.circular(fieldRadius),
      );
      // slight inner shadow effect
      canvas.drawRRect(r, fieldPaint);
      final stroke = Paint()
        ..color = const Color(0xFFE2F0F6)
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(r, stroke);

      // small icon at left of field
      final iconCenter = Offset(r.left + 12, r.center.dy);
      canvas.drawCircle(
          iconCenter, 6, Paint()..color = const Color(0xFFB6DCEB));
    }

    // Phone small "sign in" button
    final btnRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneCenter.dx - phoneW * 0.14,
          phoneCenter.dy + phoneH * 0.12, phoneW * 0.28, sh(0.05)),
      Radius.circular(10),
    );
    final btnPaint = Paint()
      ..shader = ui.Gradient.linear(
        // Replace invalid getters with manually computed points
        Offset(btnRect.left, (btnRect.top + btnRect.bottom) / 2),
        Offset(btnRect.right, (btnRect.top + btnRect.bottom) / 2),
        [
          const Color(0xFF386FA4),
          const Color(0xFF2B7DB8),
        ],
      );

// Draw the rounded rectangle button
    canvas.drawRRect(btnRect, btnPaint);

    // Phone tiny speaker & camera dots
    canvas.drawCircle(
        Offset(phoneCenter.dx + phoneW * 0.26 / 2,
            phoneCenter.dy - phoneH / 2 + 8),
        2,
        Paint()..color = const Color(0xFF1C2A32));
    canvas.drawCircle(
        Offset(phoneCenter.dx - phoneW * 0.26 / 2,
            phoneCenter.dy - phoneH / 2 + 8),
        2,
        Paint()..color = const Color(0xFF1C2A32));

    // --- PLANT (left bottom) ---
    final plantBase = Offset(cx - sw(0.36), cy + sh(0.24));
    final potPaint = Paint()..color = const Color(0xFFD9EDF5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: plantBase, width: sw(0.12), height: sh(0.06)),
          Radius.circular(8)),
      potPaint,
    );

    final leafPaint = Paint()..color = const Color(0xFF6ABF9B);
    // 3 leaves
    for (int i = 0; i < 3; i++) {
      final path = Path();
      final lx = plantBase.dx - 6 + i * 10.0;
      final ly = plantBase.dy - sh(0.02) - i * 6;
      path.moveTo(lx, ly);
      path.quadraticBezierTo(lx - 12, ly - 20, lx + 4, ly - 34 - i * 4);
      path.quadraticBezierTo(lx + 16, ly - 20, lx + 4, ly - 8);
      path.close();
      canvas.drawPath(path, leafPaint);
    }

    // --- ENVELOPE (top-right) ---
    final envCenter = Offset(cx + sw(0.38), cy - sh(0.26));
    final envW = sw(0.14);
    final envH = sh(0.08);
    final envRect =
        Rect.fromCenter(center: envCenter, width: envW, height: envH);
    final envPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(envRect, Radius.circular(8)), envPaint);
    // flap lines
    final flap = Path();
    flap.moveTo(envRect.left + 8, envRect.top + 8);
    flap.lineTo(envRect.center.dx, envRect.bottom - 6);
    flap.lineTo(envRect.right - 8, envRect.top + 8);
    final flapPaint = Paint()
      ..color = const Color(0xFFDFEAF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(flap, flapPaint);

    // small mail shadow
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            envRect.shift(Offset(3, 4)), Radius.circular(8)),
        Paint()..color = const Color(0xFFD7E6EA));

    // --- PERSON (right side, seated) ---
    // Shadow under person
    final groundShadow = Paint()..color = Colors.black.withValues(alpha: 0.08);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + sw(0.2), cy + sh(0.30)),
            width: sw(0.28),
            height: sh(0.05)),
        groundShadow);

    // Pants (deep navy)
    final pantsPaint = Paint()..color = const Color(0xFF2C3E50);
    final pantsPath = Path();
    final px = cx + sw(0.18);
    final py = cy + sh(0.04);
    pantsPath.moveTo(px - sw(0.06), py + sh(0.05));
    pantsPath.quadraticBezierTo(
        px - sw(0.09), py + sh(0.15), px - sw(0.02), py + sh(0.20));
    pantsPath.lineTo(px + sw(0.08), py + sh(0.20));
    pantsPath.quadraticBezierTo(
        px + sw(0.12), py + sh(0.13), px + sw(0.06), py + sh(0.05));
    pantsPath.close();
    canvas.drawPath(pantsPath, pantsPaint);

    // Shoes
    final shoePaint = Paint()..color = const Color(0xFF172829);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(px - sw(0.03), py + sh(0.22)),
                width: sw(0.09),
                height: sh(0.03)),
            Radius.circular(6)),
        shoePaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(px + sw(0.06), py + sh(0.22)),
                width: sw(0.09),
                height: sh(0.03)),
            Radius.circular(6)),
        shoePaint);

    // Torso (shirt) with subtle gradient
    final torsoRect = Rect.fromCenter(
        center: Offset(px + sw(0.02), py - sh(0.02)),
        width: sw(0.22),
        height: sh(0.18));
    final torsoPaint = Paint()
      ..shader = ui.Gradient.linear(torsoRect.topLeft, torsoRect.bottomRight,
          [const Color(0xFFFFB07A), const Color(0xFFFF7A3F)]);
    canvas.drawRRect(
        RRect.fromRectAndRadius(torsoRect, Radius.circular(12)), torsoPaint);

    // Neck & head (skin tone)
    final neckRect = Rect.fromCenter(
        center: Offset(px - sw(0.02), py - sh(0.12)),
        width: sw(0.07),
        height: sh(0.06));
    final skinPaint = Paint()..color = const Color(0xFFFFDAB3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(neckRect, Radius.circular(6)), skinPaint);

    // Head
    final headCenter = Offset(px - sw(0.02), py - sh(0.20));
    final headRadius = sw(0.085);
    // head shading radial
    final headPaint = Paint()
      ..shader = ui.Gradient.radial(headCenter, headRadius,
          [const Color(0xFFFFE6CC), const Color(0xFFFFD4A8)]);
    canvas.drawCircle(headCenter, headRadius, headPaint);

    // Hair (dark)
    final hairPaint = Paint()..color = const Color(0xFF2E1E1A);
    final hairPath = Path();
    hairPath.moveTo(
        headCenter.dx - headRadius * 0.9, headCenter.dy - headRadius * 0.25);
    hairPath.quadraticBezierTo(headCenter.dx, headCenter.dy - headRadius * 1.05,
        headCenter.dx + headRadius * 0.9, headCenter.dy - headRadius * 0.25);
    hairPath.arcToPoint(
        Offset(headCenter.dx - headRadius * 0.9,
            headCenter.dy - headRadius * 0.25),
        radius: Radius.circular(headRadius),
        clockwise: false);
    hairPath.close();
    canvas.drawPath(hairPath, hairPaint);

    // Eyes
    final eyeWhite = Paint()..color = Colors.white;
    final eyeIris = Paint()..color = const Color(0xFF2F7D8E);
    final eyePupil = Paint()..color = Colors.black;
    final eyeYOffset = sh(0.012);
    canvas.drawOval(
        Rect.fromCenter(
            center:
                Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
            width: sw(0.04),
            height: sh(0.02)),
        eyeWhite);
    canvas.drawOval(
        Rect.fromCenter(
            center:
                Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
            width: sw(0.04),
            height: sh(0.02)),
        eyeWhite);
    canvas.drawCircle(
        Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.01),
        eyeIris);
    canvas.drawCircle(
        Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.01),
        eyeIris);
    canvas.drawCircle(
        Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.005),
        eyePupil);
    canvas.drawCircle(
        Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.005),
        eyePupil);

    // Smile
    final smilePaint = Paint()
      ..color = const Color(0xFFB84A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final smile = Path();
    smile.moveTo(headCenter.dx - sw(0.035), headCenter.dy + sh(0.01));
    smile.quadraticBezierTo(headCenter.dx, headCenter.dy + sh(0.03),
        headCenter.dx + sw(0.035), headCenter.dy + sh(0.01));
    canvas.drawPath(smile, smilePaint);

    // Cheeks (blush)
    final blush = Paint()..color = const Color(0xFFFFB3BA).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(headCenter.dx - sw(0.06), headCenter.dy + sh(0.0)),
        sw(0.015), blush);
    canvas.drawCircle(Offset(headCenter.dx + sw(0.06), headCenter.dy + sh(0.0)),
        sw(0.015), blush);

    // Left arm (reaching to phone) - sleeve uses same gradient as torso
    final leftArm = Path();
    leftArm.moveTo(px - sw(0.02), py - sh(0.03));
    leftArm.quadraticBezierTo(
        px - sw(0.12), py - sh(0.08), px - sw(0.18), py - sh(0.14));
    leftArm.quadraticBezierTo(
        px - sw(0.16), py - sh(0.10), px - sw(0.08), py - sh(0.02));
    leftArm.close();
    canvas.drawPath(leftArm, torsoPaint);

    // Left hand (holding phone) - small circle for hand skin tone
    final leftHandCenter = Offset(px - sw(0.18), py - sh(0.14));
    canvas.drawCircle(leftHandCenter, sw(0.025), skinPaint);

    // Right arm (resting)
    final rightArm = Path();
    rightArm.moveTo(px + sw(0.06), py - sh(0.0));
    rightArm.quadraticBezierTo(
        px + sw(0.14), py + sh(0.03), px + sw(0.18), py + sh(0.06));
    rightArm.quadraticBezierTo(
        px + sw(0.14), py + sh(0.05), px + sw(0.06), py - sh(0.0));
    rightArm.close();
    canvas.drawPath(rightArm, torsoPaint);

    // Small book / paper near person (to match image)
    final paperRect = Rect.fromCenter(
        center: Offset(px + sw(0.28), py + sh(0.02)),
        width: sw(0.12),
        height: sh(0.07));
    canvas.drawRRect(RRect.fromRectAndRadius(paperRect, Radius.circular(6)),
        Paint()..color = const Color(0xFFF6F9FB));
    canvas.drawRect(
        paperRect.deflate(6), Paint()..color = const Color(0xFFEFF6F8));

    // dotted lines on paper
    for (int i = 0; i < 3; i++) {
      final dy = paperRect.top + 10 + i * 14;
      canvas.drawLine(
          Offset(paperRect.left + 8, dy),
          Offset(paperRect.right - 8, dy),
          Paint()
            ..color = const Color(0xFFE1EEF2)
            ..strokeWidth = 1);
    }

    // small envelope shadow near top-right (already drawn)
    // Add more subtle details on phone: small list bullets
    final bulletPaint = Paint()..color = const Color(0xFF5BA8D6);
    for (int i = 0; i < 3; i++) {
      final yy = phoneCenter.dy - phoneH * 0.02 + i * sh(0.06);
      canvas.drawCircle(
          Offset(phoneCenter.dx - phoneW * 0.14 + 18, yy), 4, bulletPaint);
    }

    // Overall tiny accents: rounded rectangle at bottom "Sign In" under whole illustration (mimic page CTA)
    final bottomBtn = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy + sh(0.38)),
            width: sw(0.36),
            height: sh(0.07)),
        Radius.circular(24));
    final bottomBtnPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(bottomBtn.left, (bottomBtn.top + bottomBtn.bottom) / 2),
        Offset(bottomBtn.right, (bottomBtn.top + bottomBtn.bottom) / 2),
        [
          const Color(0xFF1D6D9F),
          const Color(0xFF154F78),
        ],
      );

    canvas.drawRRect(bottomBtn, bottomBtnPaint);

    // button text stroke (simple line to indicate)
    canvas.drawLine(
        Offset(bottomBtn.left + 24, bottomBtn.center.dy),
        Offset(bottomBtn.right - 24, bottomBtn.center.dy),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 12);

    // final small signature lines (mimic text under 'Login' heading)
    final titleY = cy - sh(0.4);
    canvas.drawRect(Rect.fromLTWH(cx - sw(0.35), titleY, sw(0.26), sh(0.02)),
        Paint()..color = const Color(0xFF2C3E50));
    canvas.drawRect(
        Rect.fromLTWH(cx - sw(0.35), titleY + sh(0.03), sw(0.18), sh(0.015)),
        Paint()..color = const Color(0xFF9FB9C8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
