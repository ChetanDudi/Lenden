import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'dart:async';
import '../otp_input.dart';
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../login/google_auth_service.dart';
import '../widgets/google_logo_icon.dart';
import '../widgets/wave_widget.dart' show ScaledDeepTopWaveClipper;
import '../widgets/login_illustration.dart';

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
  final _referralCodeController = TextEditingController();
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
  Timer? _otpTimer;
  // double _rating = 0.0; // Rating removed

  // Uniqueness check state
  bool _isUsernameUnique = true;
  bool _isEmailUnique = true;
  bool _checkingUsername = false;
  bool _checkingEmail = false;
  // true when the check request failed (timeout/network) — don't block registration
  bool _usernameCheckFailed = false;
  bool _emailCheckFailed = false;

  // Only enforce length; strength is shown as a visual meter
  bool get _isPasswordValid =>
      _passwordController.text.length >= 8 &&
      _passwordController.text.length <= 30;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget ping to wake Render before user finishes filling the form
    ApiClient.get('/', timeout: const Duration(seconds: 90)).then<void>((_) {}, onError: (_) {});
  }

  @override
  void dispose() {
    _otpTimer?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _referralCodeController.dispose();
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
        _errorMessage = 'Password must be 8–30 characters.';
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
    if (_selectedGender == null) {
      setState(() {
        _errorMessage = 'Please select your gender.';
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
      if (_referralCodeController.text.trim().isNotEmpty)
        'referralCode': _referralCodeController.text.trim(),
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
    _otpTimer?.cancel();
    setState(() => _otpSecondsLeft = 120);
    _otpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_otpSecondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _otpSecondsLeft = 0);
        return;
      }
      setState(() => _otpSecondsLeft--);
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
        backgroundColor: AppThemeColors.tinted(context,
            light: const Color(0xFFE0F7FA), dark: const Color(0xFF173238)),
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
          style: TextStyle(
              fontSize: context.sp(15),
              color: AppThemeColors.primaryText(context)),
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
                color: AppThemeColors.cardBg(context),
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
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  SizedBox(height: context.sh(12)),
                  Text(
                    'You can now log in with your new account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: context.sp(15),
                        color: AppThemeColors.primaryText(context)),
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

  Widget _profileStyleField({
    required IconData icon,
    required Widget child,
    bool enabled = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: enabled ? AppThemeColors.cardBg(context) : AppThemeColors.scaffoldBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: enabled
              ? AppThemeColors.border(context)
              : AppThemeColors.border(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(children: [
        const SizedBox(width: 14),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.cyan.withValues(alpha: 0.10)
                : AppThemeColors.border(context).withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: enabled ? AppColors.cyan : AppThemeColors.secondaryText(context), size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: child),
        const SizedBox(width: 8),
      ]),
    );
  }

  // Strength meter replaces the old requirement-checklist.
  Widget _buildStrengthMeter() =>
      PasswordStrengthMeter(password: _passwordController.text);

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
      body: Stack(
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
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: context.hPadding, vertical: context.vPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: context.sh(18)),
                    Text(t('register'),
                        style: TextStyle(
                            fontSize: context.sp(28),
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Hello Welcome :)',
                        style: TextStyle(
                            fontSize: context.sp(15),
                            color: AppThemeColors.primaryText(context)),
                        textAlign: TextAlign.center),
                    SizedBox(height: context.sh(28)),
                    LoginIllustration(height: context.sh(160)),
                    const SizedBox(height: 24),
                    _profileStyleField(
                      icon: Icons.person,
                      enabled: !_detailsLocked,
                      child: TextField(
                        controller: _nameController,
                        enabled: !_detailsLocked,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.alternate_email,
                      enabled: !_detailsLocked,
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.transgender,
                      enabled: !_detailsLocked,
                      child: DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: const InputDecoration(
                          labelText: 'Gender',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(value: 'Female', child: Text('Female')),
                          DropdownMenuItem(value: 'Other', child: Text('Other')),
                        ],
                        onChanged: _detailsLocked
                            ? null
                            : (val) => setState(() => _selectedGender = val),
                        validator: (val) =>
                            val == null ? 'Please select gender' : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.email_outlined,
                      enabled: !_detailsLocked,
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
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.lock_outline,
                      enabled: !_detailsLocked,
                      child: TextField(
                        controller: _passwordController,
                        enabled: !_detailsLocked,
                        obscureText: _obscurePassword,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                    _buildStrengthMeter(),
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.lock_rounded,
                      enabled: !_detailsLocked,
                      child: TextField(
                        controller: _confirmPasswordController,
                        enabled: !_detailsLocked,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          labelStyle: const TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                    const SizedBox(height: 14),
                    _profileStyleField(
                      icon: Icons.card_giftcard_outlined,
                      child: TextField(
                        controller: _referralCodeController,
                        enabled: !_detailsLocked,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Referral Code (optional)',
                          labelStyle: TextStyle(color: Colors.grey),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
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
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFE0F7FA),
                              dark: const Color(0xFF173238)),
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
                        enabled: true,
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
                        Expanded(
                            child:
                                Divider(color: AppThemeColors.divider(context))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(t('or'),
                              style: TextStyle(
                                  fontSize: context.sp(13),
                                  color: AppThemeColors.secondaryText(context))),
                        ),
                        Expanded(
                            child:
                                Divider(color: AppThemeColors.divider(context))),
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
                          side: BorderSide(color: AppThemeColors.border(context)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isGoogleLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppThemeColors.secondaryText(context)),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const GoogleLogoIcon(size: 18),
                                  const SizedBox(width: 10),
                                  Text('Sign up with Google',
                                      style: TextStyle(
                                          fontSize: context.sp(15),
                                          fontWeight: FontWeight.w600,
                                          color: AppThemeColors.primaryText(
                                              context))),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${t('already_have_account')} ',
                            style: TextStyle(
                                fontSize: context.sp(13),
                                color: AppThemeColors.primaryText(context))),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/login'),
                          child: Text(t('login'),
                              style: TextStyle(
                                  color: AppThemeColors.primaryText(context),
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
