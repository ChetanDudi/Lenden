import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart' show PasswordStrengthMeter;
import 'dart:convert';
import '../otp_input.dart';
import '../utils/api_client.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../widgets/wave_widget.dart' show DeepTopWaveClipper, AltBottomWaveClipper;

class UserForgotPasswordPage extends StatefulWidget {
  final String? prefillEmail;
  const UserForgotPasswordPage({super.key, this.prefillEmail});

  @override
  State<UserForgotPasswordPage> createState() => _UserForgotPasswordPageState();
}

class _UserForgotPasswordPageState extends State<UserForgotPasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _otpSent = false;
  bool _otpVerified = false;
  bool _isVerifyingOtp = false;
  bool _isResetting = false;
  String? _errorMessage;
  String? _userType; // 'user' or 'admin'
  int _secondsLeft = 0;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  late final FocusNode _otpFocusNode;
  late final FocusNode _newPasswordFocusNode;
  late final FocusNode _confirmPasswordFocusNode;
  String _forgotOtp = '';
  int _otpKey = 0;

  @override
  void initState() {
    super.initState();
    _otpFocusNode = FocusNode();
    _newPasswordFocusNode = FocusNode();
    _confirmPasswordFocusNode = FocusNode();
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _otpFocusNode.dispose();
    _newPasswordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  void _sendOtp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/send-reset-otp', {
      'email': _emailController.text,
    });
    if (res['status'] == 200) {
      setState(() {
        _otpSent = true;
        _userType = res['data']['userType'];
        _secondsLeft = 120;
        _errorMessage = null;
      });
      _startTimer();
      FocusScope.of(context).requestFocus(_otpFocusNode);
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? AppLocalizations.of(context).t('failed_to_send_otp');
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  void _startTimer() {
    _secondsLeft = 120;
    Future.doWhile(() async {
      if (_secondsLeft > 0 && mounted && !_otpVerified) {
        await Future.delayed(const Duration(seconds: 1));
        setState(() {
          _secondsLeft--;
        });
        return true;
      }
      return false;
    });
  }

  void _resendOtp() {
    _sendOtp();
    _otpController.clear();
    setState(() {
      _otpVerified = false;
    });
  }

  void _resetPassword() async {
    setState(() {
      _isResetting = true;
      _errorMessage = null;
    });
    if (_newPasswordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = AppLocalizations.of(context).t('passwords_do_not_match');
        _isResetting = false;
      });
      return;
    }
    final res = await _post('/api/users/reset-password', {
      'email': _emailController.text,
      'userType': _userType,
      'newPassword': _newPasswordController.text,
    });
    if (res['status'] == 200) {
      setState(() {
        _errorMessage = null;
      });
      final t = AppLocalizations.of(context).t;
      _showSuccessDialog(
          t('password_reset_successful'), t('password_reset_successful_message'));
    } else {
      setState(() {
        _errorMessage =
            res['data']['error'] ?? AppLocalizations.of(context).t('failed_to_reset_password');
      });
    }
    setState(() {
      _isResetting = false;
    });
  }

  void _verifyOtpWithOtp(String otp) async {
    setState(() {
      _isVerifyingOtp = true;
      _errorMessage = null;
    });
    final res = await _post('/api/users/verify-reset-otp', {
      'email': _emailController.text,
      'otp': otp,
    });
    if (res['status'] == 200) {
      setState(() {
        _otpVerified = true;
        _errorMessage = null;
      });
      FocusScope.of(context).requestFocus(_newPasswordFocusNode);
    } else {
      setState(() {
        _errorMessage = res['data']['error'] ?? AppLocalizations.of(context).t('otp_verification_failed');
        _forgotOtp = '';
        _otpKey++;
      });
    }
    setState(() { _isVerifyingOtp = false; });
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final response = await ApiClient.post(path, body: body)
          .timeout(const Duration(minutes: 2));
      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      print('❌ API call error: $e');
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

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) {
        final t = AppLocalizations.of(ctx).t;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: AppThemeColors.tinted(ctx,
              light: const Color(0xFFE0F7FA), dark: const Color(0xFF173238)),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: AppColors.cyan, size: 60),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      color: Color(0xFF0077B5),
                      fontWeight: FontWeight.bold,
                      fontSize: 22),
                  textAlign: TextAlign.center),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(fontSize: 16, color: AppThemeColors.primaryText(ctx)),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.pushReplacementNamed(ctx, '/login');
              },
              child: Text(t('login'),
                  style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ],
        );
      },
    );
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

  int get _currentStep => _otpVerified ? 2 : (_otpSent ? 1 : 0);

  Widget _buildPage(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top wave — decoration only, no interactive children inside ClipPath
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const DeepTopWaveClipper(),
              child: Container(
                height: context.sh(200),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // Back button + lock icon overlaid ABOVE the ClipPath so touch events are never clipped
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).canPop()
                        ? Navigator.of(context).pop()
                        : Navigator.pushReplacementNamed(context, '/'),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 34),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom wave
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: const AltBottomWaveClipper(),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: context.sh(115)),

                  // Title
                  Text(
                    t('forgot_password'),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('reset_your_password_securely'),
                    style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Step indicator
                  _buildStepIndicator(context),
                  const SizedBox(height: 28),

                  // Main card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // ── Step 0: Email ──────────────────────────────────
                        if (!_otpSent) ...[
                          _stepHeader(
                            context,
                            icon: Icons.email_outlined,
                            color: AppColors.cyan,
                            title: 'Enter your email',
                            subtitle: "We'll send a 6-digit code to verify it's you.",
                          ),
                          const SizedBox(height: 20),
                          _styledField(
                            context,
                            controller: _emailController,
                            label: t('email'),
                            icon: Icons.alternate_email_rounded,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 20),
                          _primaryButton(
                            context,
                            label: t('send_otp'),
                            icon: Icons.send_rounded,
                            loading: _isLoading,
                            onPressed: _sendOtp,
                          ),
                          const SizedBox(height: 16),
                          _infoTip(context, '🔒', 'We never share your email with third parties.'),
                        ],

                        // ── Step 1: OTP ────────────────────────────────────
                        if (_otpSent && !_otpVerified) ...[
                          _stepHeader(
                            context,
                            icon: Icons.mark_email_read_outlined,
                            color: Colors.orange,
                            title: 'Check your inbox',
                            subtitle: 'Enter the 6-digit code sent to\n${_emailController.text}',
                          ),
                          const SizedBox(height: 24),
                          OtpInput(
                            key: ValueKey(_otpKey),
                            onChanged: (val) => setState(() => _forgotOtp = val),
                            enabled: true,
                            autoFocus: true,
                          ),
                          const SizedBox(height: 14),
                          // Inline error — shown right below OTP boxes
                          if (_errorMessage != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.red, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                              ]),
                            ),
                          // Resend row — always visible; disabled while countdown is active
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_secondsLeft > 0) ...[
                                const Icon(Icons.timer_outlined, size: 14, color: AppColors.cyan),
                                const SizedBox(width: 4),
                                Text(
                                  '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppThemeColors.secondaryText(context)),
                                ),
                                const SizedBox(width: 10),
                              ],
                              TextButton.icon(
                                onPressed: _secondsLeft == 0 ? _resendOtp : null,
                                icon: Icon(Icons.refresh_rounded, size: 15,
                                    color: _secondsLeft == 0 ? AppColors.cyan : AppThemeColors.mutedText(context)),
                                label: Text(
                                  t('resend_otp'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _secondsLeft == 0 ? AppColors.cyan : AppThemeColors.mutedText(context),
                                  ),
                                ),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _primaryButton(
                            context,
                            label: t('verify_otp'),
                            icon: Icons.verified_user_outlined,
                            loading: _isVerifyingOtp,
                            onPressed: _forgotOtp.length == 6 ? () => _verifyOtpWithOtp(_forgotOtp) : null,
                          ),
                          const SizedBox(height: 12),
                          _infoTip(context, '📬', "Didn't receive it? Check your spam folder."),
                        ],

                        // ── Step 2: New Password ───────────────────────────
                        if (_otpVerified) ...[
                          _stepHeader(
                            context,
                            icon: Icons.lock_outline_rounded,
                            color: Colors.green,
                            title: 'Set new password',
                            subtitle: 'Choose a strong password you haven\'t used before.',
                          ),
                          const SizedBox(height: 20),
                          _styledField(
                            context,
                            controller: _newPasswordController,
                            focusNode: _newPasswordFocusNode,
                            label: t('new_password'),
                            icon: Icons.lock_outlined,
                            obscure: _obscureNewPassword,
                            onToggleObscure: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                          ),
                          const SizedBox(height: 12),
                          _styledField(
                            context,
                            controller: _confirmPasswordController,
                            focusNode: _confirmPasswordFocusNode,
                            label: t('confirm_password'),
                            icon: Icons.lock_person_outlined,
                            obscure: _obscureConfirmPassword,
                            onToggleObscure: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                          const SizedBox(height: 16),
                          // Live password strength meter
                          PasswordStrengthMeter(
                              password: _newPasswordController.text),
                          const SizedBox(height: 20),
                          _primaryButton(
                            context,
                            label: t('change_password'),
                            icon: Icons.check_circle_outline_rounded,
                            loading: _isResetting,
                            onPressed: _resetPassword,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Error banner for steps 0 and 2 (step 1 shows inline above)
                  if (_errorMessage != null && !(_otpSent && !_otpVerified)) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    const steps = ['Email', 'Verify', 'Reset'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepIndex = i ~/ 2;
          final done = _currentStep > stepIndex;
          return Expanded(
            child: Container(
              height: 2,
              color: done ? AppColors.cyan : AppThemeColors.divider(context),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final active = _currentStep == stepIndex;
        final done = _currentStep > stepIndex;
        return Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (active || done) ? AppColors.cyan : AppThemeColors.divider(context),
              ),
              child: Center(
                child: done
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text('${stepIndex + 1}', style: TextStyle(
                        color: active ? Colors.white : AppThemeColors.mutedText(context),
                        fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 4),
            Text(steps[stepIndex],
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: (active || done) ? AppColors.cyan : AppThemeColors.mutedText(context),
              )),
          ],
        );
      }),
    );
  }

  Widget _stepHeader(BuildContext context, {required IconData icon, required Color color, required String title, required String subtitle}) {
    return Column(
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context))),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(context)), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _styledField(BuildContext context, {
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: AppThemeColors.primaryText(context)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.cyan, size: 20),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: onToggleObscure,
              )
            : null,
        filled: true,
        fillColor: AppThemeColors.surfaceBg(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _primaryButton(BuildContext context, {required String label, required IconData icon, required bool loading, required VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          disabledBackgroundColor: AppColors.cyan.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _infoTip(BuildContext context, String emoji, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
      ],
    );
  }
}

