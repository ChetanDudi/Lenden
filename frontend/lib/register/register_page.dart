import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'dart:async';
import '../otp_input.dart';
import '../widgets/tricolor_border_text_field.dart';
import 'dart:ui' as ui;
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../login/google_auth_service.dart';

class UserRegisterPage extends StatefulWidget {
  const UserRegisterPage({super.key});

  @override
  State<UserRegisterPage> createState() => _UserRegisterPageState();
}

class _UserRegisterPageState extends State<UserRegisterPage> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _otpSent = false;
  bool _isVerifyingOtp = false;
  int _otpSecondsLeft = 0;
  String _registerOtp = '';
  String? _selectedGender;
  bool _detailsLocked = false;
  // double _rating = 0.0; // Rating removed

  // Uniqueness check state
  bool _isUsernameUnique = true;
  bool _isEmailUnique = true;
  bool _checkingUsername = false;
  bool _checkingEmail = false;
  // true when the check request failed (timeout/network) — don't block registration
  bool _usernameCheckFailed = false;
  bool _emailCheckFailed = false;

  // Password validation
  bool get _hasUpper => RegExp(r'[A-Z]').hasMatch(_passwordController.text);
  bool get _hasLower => RegExp(r'[a-z]').hasMatch(_passwordController.text);
  bool get _hasSpecial =>
      RegExp(r'[^A-Za-z0-9]').hasMatch(_passwordController.text);
  bool get _hasLength =>
      _passwordController.text.length >= 8 &&
      _passwordController.text.length <= 30;
  bool get _isPasswordValid =>
      _hasUpper && _hasLower && _hasSpecial && _hasLength;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget ping to wake Render before user finishes filling the form
    ApiClient.get('/', timeout: const Duration(seconds: 90)).then<void>((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _checkUsernameUnique(String username) async {
    setState(() { _checkingUsername = true; });
    final res = await _post(
      '/api/users/check-username',
      {'username': username},
      timeout: const Duration(seconds: 20),
    );
    setState(() {
      if (res['status'] == 200) {
        _isUsernameUnique = res['data']['unique'] == true;
        _usernameCheckFailed = false;
      } else {
        // Timeout or network error — don't block the user; server will validate on submit
        _isUsernameUnique = true;
        _usernameCheckFailed = true;
      }
      _checkingUsername = false;
    });
  }

  Future<void> _checkEmailUnique(String email) async {
    setState(() { _checkingEmail = true; });
    final res = await _post(
      '/api/users/check-email',
      {'email': email},
      timeout: const Duration(seconds: 20),
    );
    setState(() {
      if (res['status'] == 200) {
        _isEmailUnique = res['data']['unique'] == true;
        _emailCheckFailed = false;
      } else {
        _isEmailUnique = true;
        _emailCheckFailed = true;
      }
      _checkingEmail = false;
    });
  }

  void _register() async {
    if (!_isPasswordValid) {
      setState(() {
        _errorMessage = 'Password does not meet all requirements.';
      });
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match.';
      });
      return;
    }
    if (!_isUsernameUnique && !_usernameCheckFailed) {
      setState(() {
        _errorMessage = 'Username already exists.';
      });
      return;
    }
    if (!_isEmailUnique && !_emailCheckFailed) {
      setState(() {
        _errorMessage = 'Email already exists.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _detailsLocked = true; // Lock fields before sending OTP
    });

    // Send OTP — 120s timeout to survive Render cold start + email sending retries
    final res = await _post('/api/users/register', {
      'name': _nameController.text,
      'username': _usernameController.text,
      'email': _emailController.text,
      'password': _passwordController.text,
      'gender': _selectedGender,
    }, timeout: const Duration(seconds: 120));

    if (res['status'] == 200) {
      setState(() {
        _otpSent = true;
        _isLoading = false;
        _otpSecondsLeft = 120;
      });
      _showSnackBar('OTP sent to your email.');
      _startOtpTimer();
    } else {
      final raw = (res['data']['error'] ?? '').toString();
      final status = res['status'] as int;
      String errorMsg;
      if (status == 408 || raw.toLowerCase().contains('timeout') || raw.toLowerCase().contains('timed out')) {
        errorMsg = 'Server is starting up. Please wait a moment and try again.';
      } else if (status == 503 || raw.toLowerCase().contains('unavailable')) {
        errorMsg = 'Service temporarily unavailable. Please try again in a few seconds.';
      } else if (status == 0 || raw.toLowerCase().contains('internet') || raw.toLowerCase().contains('socket')) {
        errorMsg = 'No internet connection. Please check your network and try again.';
      } else {
        errorMsg = raw.isNotEmpty ? raw : 'Failed to send OTP. Please try again.';
      }
      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
        _detailsLocked = false;
      });
    }
  }

  void _registerWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await GoogleAuthService.loginWithGoogle();

      if (result['success'] == true) {
        final userOrAdmin = result['userOrAdmin'];
        final token = result['accessToken'] as String;
        final refreshToken = result['refreshToken'] as String;

        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.saveTokens(token, refreshToken);

        final userData = Map<String, dynamic>.from(userOrAdmin);
        userData['role'] = 'user';
        session.setUser(userData);
        await session.checkSubscriptionStatus();

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/user/dashboard');
        }
      } else if (result['cancelled'] != true) {
        setState(() {
          _errorMessage = result['error'] ?? 'Google sign-in failed.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Google sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
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

  void _verifyOtpWithOtp(String otp) async {
    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/verify-otp', {
      'email': _emailController.text,
      'otp': otp,
    }, timeout: const Duration(seconds: 30));
    if (res['status'] == 201) {
      setState(() {
        _isVerifyingOtp = false;
      });
      _showRegistrationSuccessDialog();
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? 'OTP verification failed.';
        _isVerifyingOtp = false;
        _otpSecondsLeft = 0;
      });
    }
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body, {Duration? timeout}) async {
    try {
      final response = await ApiClient.post(path, body: body, timeout: timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return {'status': response.statusCode, 'data': data};
      } else {
        final data = jsonDecode(response.body);
        return {'status': response.statusCode, 'data': data};
      }
    } on TimeoutException catch (_) {
      return {
        'status': 408,
        'data': {'error': 'The request timed out. Please try again.'}
      };
    } catch (e) {
      if (e.toString().contains('SocketException')) {
        return {
          'status': 0,
          'data': {'error': 'No internet connection'}
        };
      } else if (e.toString().contains('HandshakeException')) {
        return {
          'status': 0,
          'data': {'error': 'SSL/TLS connection failed'}
        };
      } else {
        return {
          'status': 500,
          'data': {'error': e.toString()}
        };
      }
    }
  }

  void _showSnackBar(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFE0F7FA),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.email, color: AppColors.cyan, size: context.sp(52)),
            SizedBox(height: context.sh(10)),
            Text('OTP Sent!',
                style: TextStyle(
                    color: const Color(0xFF0077B5),
                    fontWeight: FontWeight.bold,
                    fontSize: context.sp(20)),
                textAlign: TextAlign.center),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: context.sp(15), color: Colors.black87),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK',
                style: TextStyle(
                    color: AppColors.cyan,
                    fontWeight: FontWeight.bold,
                    fontSize: context.sp(15))),
          ),
        ],
      ),
    );
  }

  void _showRegistrationSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Colors.orange, Colors.white, Colors.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: EdgeInsets.all(context.sw(22)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: context.sp(68)),
                  SizedBox(height: context.sh(20)),
                  Text(
                    'Registration Successful!',
                    style: TextStyle(
                      fontSize: context.sp(20),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: context.sh(12)),
                  Text(
                    'You can now log in with your new account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: context.sp(15)),
                  ),
                  SizedBox(height: context.sh(20)),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushReplacementNamed(context, '/login');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(
                          horizontal: context.sw(32), vertical: context.sh(10)),
                    ),
                    child: Text('Go to Login',
                        style: TextStyle(
                            fontSize: context.sp(15), color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildPasswordRules(BuildContext context) {
    final rules = <Map<String, bool>>[
      {'At least one uppercase letter': _hasUpper},
      {'At least one lowercase letter': _hasLower},
      {'At least one special character': _hasSpecial},
      {'8-30 characters': _hasLength},
    ];
    if (_passwordController.text.isEmpty || _isPasswordValid) return [];
    return rules
        .where((rule) => !rule.values.first)
        .map((rule) => Row(
              children: [
                Icon(Icons.cancel, color: Colors.red, size: context.sp(16)),
                const SizedBox(width: 6),
                Text(rule.keys.first,
                    style: TextStyle(color: Colors.red, fontSize: context.sp(12))),
              ],
            ))
        .toList();
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          // Top blue shape
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(78),
                color: AppColors.cyan,
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topLeft,
                    // Remove the IconButton with Icons.arrow_back from the top blue shape
                  ),
                ),
              ),
            ),
          ),
          // Bottom blue shape
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: BottomWaveClipper(),
              child: Container(
                height: context.sh(80),
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
                    Text('Register',
                        style: TextStyle(
                            fontSize: context.sp(28),
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Hello Welcome :)',
                        style: TextStyle(fontSize: context.sp(15), color: Colors.black),
                        textAlign: TextAlign.center),
                    SizedBox(height: context.sh(28)),
                    LoginIllustration(height: context.sh(160)),
                    const SizedBox(height: 24),
                    TricolorBorderTextField(
                      child: TextField(
                        controller: _nameController,
                        enabled: !_detailsLocked,
                        decoration: InputDecoration(
                          labelText: 'Name',
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
                        controller: _usernameController,
                        enabled: !_detailsLocked,
                        onChanged: (val) {
                          if (val.isNotEmpty) _checkUsernameUnique(val);
                        },
                        decoration: InputDecoration(
                          labelText: 'Username',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          suffixIcon: _checkingUsername
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : (!_isUsernameUnique && !_usernameCheckFailed)
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : null,
                        ),
                      ),
                    ),
                    if (!_isUsernameUnique && !_usernameCheckFailed)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Username already exists.',
                            style: TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    const SizedBox(height: 18),
                    TricolorBorderTextField(
                      child: DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                              value: 'Female', child: Text('Female')),
                          DropdownMenuItem(
                              value: 'Other', child: Text('Other')),
                        ],
                        onChanged: _detailsLocked
                            ? null
                            : (val) => setState(() => _selectedGender = val),
                        validator: (val) =>
                            val == null ? 'Please select gender' : null,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TricolorBorderTextField(
                      child: TextField(
                        controller: _emailController,
                        enabled: !_detailsLocked,
                        onChanged: (val) {
                          if (val.isNotEmpty) _checkEmailUnique(val);
                        },
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          suffixIcon: _checkingEmail
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : (!_isEmailUnique && !_emailCheckFailed)
                                  ? const Icon(Icons.error, color: Colors.red)
                                  : null,
                        ),
                      ),
                    ),
                    if (!_isEmailUnique && !_emailCheckFailed)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 4),
                        child: Text('Email already exists.',
                            style: TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    const SizedBox(height: 18),
                    TricolorBorderTextField(
                      child: TextField(
                        controller: _passwordController,
                        enabled: !_detailsLocked,
                        obscureText: _obscurePassword,
                        onChanged: (_) => setState(() {}),
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
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._buildPasswordRules(context),
                    const SizedBox(height: 18),
                    TricolorBorderTextField(
                      child: TextField(
                        controller: _confirmPasswordController,
                        enabled: !_detailsLocked,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 18),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (!_otpSent) ...[
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(_errorMessage!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppColors.cyan,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: _isLoading
                                  ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white)),
                                        const SizedBox(width: 12),
                                        Text('Sending OTP...',
                                            style: TextStyle(
                                                fontSize: context.sp(17),
                                                color: Colors.white)),
                                      ],
                                    )
                                  : Center(
                                      child: Text('Register',
                                          style: TextStyle(
                                              fontSize: context.sp(17),
                                              color: Colors.white)),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Text(_errorMessage!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0F7FA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.email, color: AppColors.cyan),
                            const SizedBox(width: 8),
                            Text('OTP sent to your email',
                                style: TextStyle(
                                    color: Color(0xFF0077B5),
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      OtpInput(
                        onChanged: (val) => setState(() => _registerOtp = val),
                        enabled: _otpSecondsLeft > 0,
                        autoFocus: true,
                      ),
                      const SizedBox(height: 10),
                      if (_otpSecondsLeft > 0)
                        Text(
                            'OTP expires in  ${_otpSecondsLeft ~/ 60}:${(_otpSecondsLeft % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.grey)),
                      if (_otpSecondsLeft == 0)
                        TextButton(
                          onPressed: _isVerifyingOtp
                              ? null
                              : () {
                                  setState(() {
                                    _otpSent = false;
                                    _registerOtp = '';
                                    _errorMessage = null;
                                    _detailsLocked = false;
                                  });
                                },
                          child: const Text('Resend OTP'),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isVerifyingOtp ||
                                  _registerOtp.length != 6 ||
                                  _otpSecondsLeft == 0
                              ? null
                              : () => _verifyOtpWithOtp(_registerOtp),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isVerifyingOtp
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white)),
                                    const SizedBox(width: 12),
                                    Text('Verifying OTP...',
                                        style: TextStyle(
                                            fontSize: context.sp(17),
                                            color: Colors.white)),
                                  ],
                                )
                              : Text('Verify OTP & Register',
                                  style: TextStyle(
                                      fontSize: context.sp(17),
                                      color: Colors.white)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: Colors.grey)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text('OR',
                              style: TextStyle(
                                  fontSize: context.sp(13),
                                  color: Colors.grey.shade600)),
                        ),
                        const Expanded(child: Divider(color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed:
                            (_isLoading || _isGoogleLoading || _otpSent)
                                ? null
                                : _registerWithGoogle,
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isGoogleLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black54),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const FaIcon(FontAwesomeIcons.google,
                                      size: 18, color: Color(0xFFEA4335)),
                                  const SizedBox(width: 10),
                                  Text('Sign up with Google',
                                      style: TextStyle(
                                          fontSize: context.sp(15),
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87)),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('I Have an Account ? ',
                            style: TextStyle(fontSize: context.sp(13))),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/login'),
                          child: Text('Login',
                              style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: context.sp(13))),
                        ),
                      ],
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
    path.lineTo(0, size.height * 0.7 * 0.75); // scaled down
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.75,
        size.width * 0.5, size.height * 0.7 * 0.75);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.4 * 0.75,
        size.width, size.height * 0.7 * 0.75);
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