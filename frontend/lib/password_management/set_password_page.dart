import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../utils/api_client.dart';
import '../otp_input.dart';
import '../settings/custom_warning_widget.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';

class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({super.key});

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  // ── auth mode ──────────────────────────────────────────────────────────────
  bool _hasPinSet = false;
  bool _usePinMode = false; // false = email OTP, true = wallet PIN

  // ── OTP state ──────────────────────────────────────────────────────────────
  bool _otpSent = false;
  bool _isSending = false;
  String _otp = '';
  int _otpKey = 0;
  int _secondsLeft = 0;
  Timer? _timer;

  // ── PIN state ──────────────────────────────────────────────────────────────
  String _pin = '';
  int _pinKey = 0;

  // ── verification ───────────────────────────────────────────────────────────
  bool _verified = false; // true = identity confirmed, password fields enabled
  bool _verifying = false;

  // ── password ───────────────────────────────────────────────────────────────
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _loadPinStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadPinStatus() async {
    try {
      final res = await ApiClient.get('/api/wallet/pin/status');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _hasPinSet = data['hasPin'] == true);
      }
    } catch (_) {}
  }

  // ── OTP flow ────────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    setState(() => _isSending = true);
    try {
      final res = await ApiClient.post('/api/users/set-password/send-otp');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _otpSent = true;
          _otp = '';
          _otpKey++;
        });
        _startTimer();
        CustomWarningWidget.showAnimatedSuccess(context, 'OTP sent to your email.');
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? 'Failed to send OTP.');
      }
    } catch (_) {
      if (mounted) _showErr('Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 120);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) { t.cancel(); setState(() => _secondsLeft = 0); return; }
      setState(() => _secondsLeft--);
    });
  }

  // ── verify identity ─────────────────────────────────────────────────────────
  Future<void> _verifyIdentity() async {
    setState(() => _verifying = true);
    try {
      final body = _usePinMode ? {'pin': _pin} : {'otp': _otp};
      final res = await ApiClient.post(
        '/api/users/set-password/verify-identity',
        body: body,
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        _timer?.cancel();
        setState(() {
          _verified = true;
          _verifying = false;
        });
        CustomWarningWidget.showAnimatedSuccess(context, 'Identity verified! Set your password below.');
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? 'Verification failed.');
        setState(() => _verifying = false);
      }
    } catch (_) {
      if (mounted) {
        _showErr('Network error. Please try again.');
        setState(() => _verifying = false);
      }
    }
  }

  // ── submit password ─────────────────────────────────────────────────────────
  Future<void> _setPassword() async {
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;
    if (newPw.length < 8 || newPw.length > 30) {
      _showErr('Password must be 8–30 characters.');
      return;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(newPw) || !RegExp(r'[0-9]').hasMatch(newPw)) {
      _showErr('Password must contain at least one letter and one number.');
      return;
    }
    if (newPw != confirmPw) {
      _showErr('Passwords do not match.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final res = await ApiClient.post(
        '/api/users/set-password/confirm',
        body: {'newPassword': newPw},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.refreshUserProfile();
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(context, 'Password set successfully!');
          Navigator.pop(context);
        }
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? 'Failed to set password.');
      }
    } catch (_) {
      if (mounted) _showErr('Network error. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showErr(String msg) {
    if (mounted) CustomWarningWidget.showAnimatedError(context, msg);
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final email = session.user?['email']?.toString() ?? '';
    final newPwd = _newPasswordController.text;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: 'Set Password'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            _card(
              child: Column(
                children: [
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lock_person_rounded, size: 34, color: AppColors.cyan),
                  ),
                  const SizedBox(height: 12),
                  Text('Set Your Password',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 6),
                  Text(
                    'Verify your identity first, then choose a strong password.',
                    style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Step 1: Identity verification ────────────────────────────
            _sectionLabel('Step 1 — Verify Identity', done: _verified),
            const SizedBox(height: 8),

            if (!_verified) ...[
              // Email display row
              _card(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 18, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(email,
                          style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Auth mode tabs (show PIN tab only if user has one)
              if (_hasPinSet)
                Row(
                  children: [
                    _modeTab('Email OTP', Icons.email_outlined, !_usePinMode,
                        () => setState(() { _usePinMode = false; })),
                    const SizedBox(width: 8),
                    _modeTab('Wallet PIN', Icons.dialpad_rounded, _usePinMode,
                        () => setState(() { _usePinMode = true; })),
                  ],
                ),

              if (_hasPinSet) const SizedBox(height: 14),

              // OTP path
              if (!_usePinMode) ...[
                if (!_otpSent)
                  _primaryButton(
                    label: _isSending ? 'Sending…' : 'Send OTP to Email',
                    icon: _isSending ? null : Icons.send_rounded,
                    loading: _isSending,
                    onPressed: _isSending ? null : _sendOtp,
                  )
                else ...[
                  OtpInput(
                    key: ValueKey(_otpKey),
                    onChanged: (v) => setState(() => _otp = v),
                    enabled: true,
                    autoFocus: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_secondsLeft > 0) ...[
                        const Icon(Icons.timer_outlined, size: 14, color: AppColors.cyan),
                        const SizedBox(width: 4),
                        Text(
                          '${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      TextButton.icon(
                        onPressed: _secondsLeft == 0 && !_isSending ? _sendOtp : null,
                        icon: Icon(Icons.refresh_rounded, size: 14,
                            color: _secondsLeft == 0 ? AppColors.cyan : AppThemeColors.mutedText(context)),
                        label: Text('Resend OTP',
                            style: TextStyle(
                                fontSize: 12,
                                color: _secondsLeft == 0 ? AppColors.cyan : AppThemeColors.mutedText(context))),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _primaryButton(
                    label: _verifying ? 'Verifying…' : 'Verify OTP',
                    icon: _verifying ? null : Icons.verified_user_outlined,
                    loading: _verifying,
                    onPressed: _otp.length == 6 && !_verifying ? _verifyIdentity : null,
                  ),
                ],
              ],

              // PIN path
              if (_usePinMode) ...[
                Text('Enter your 6-digit Wallet PIN',
                    style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
                const SizedBox(height: 10),
                OtpInput(
                  key: ValueKey('pin_$_pinKey'),
                  onChanged: (v) => setState(() => _pin = v),
                  enabled: true,
                  autoFocus: true,
                ),
                const SizedBox(height: 14),
                _primaryButton(
                  label: _verifying ? 'Verifying…' : 'Verify PIN',
                  icon: _verifying ? null : Icons.dialpad_rounded,
                  loading: _verifying,
                  onPressed: _pin.length == 6 && !_verifying ? _verifyIdentity : null,
                ),
              ],
            ] else ...[
              // Verified badge
              _card(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 10),
                    Text('Identity verified',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: AppThemeColors.primaryText(context))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // ── Step 2: Set password ──────────────────────────────────────
            _sectionLabel('Step 2 — Set Password', done: false),
            const SizedBox(height: 8),

            _buildPasswordField(
              controller: _newPasswordController,
              label: 'New Password',
              hint: 'At least 8 characters, mix of letters & numbers',
              obscure: _obscureNew,
              enabled: _verified,
              onToggle: () => setState(() => _obscureNew = !_obscureNew),
            ),

            if (_verified && newPwd.isNotEmpty) ...[
              const SizedBox(height: 10),
              PasswordStrengthMeter(password: newPwd),
            ],

            const SizedBox(height: 14),

            _buildPasswordField(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              hint: 'Re-enter your password',
              obscure: _obscureConfirm,
              enabled: _verified,
              onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),

            const SizedBox(height: 24),

            _primaryButton(
              label: _isSubmitting ? 'Setting…' : 'Set Password',
              icon: _isSubmitting ? null : Icons.lock_rounded,
              loading: _isSubmitting,
              onPressed: _verified && !_isSubmitting ? _setPassword : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionLabel(String text, {required bool done}) {
    return Row(
      children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16, color: done ? Colors.green : AppColors.cyan),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold,
                color: done ? Colors.green : AppThemeColors.primaryText(context))),
      ],
    );
  }

  Widget _modeTab(String label, IconData icon, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.cyan : AppThemeColors.surfaceBg(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.cyan : AppThemeColors.divider(context)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : AppThemeColors.secondaryText(context)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppThemeColors.secondaryText(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    IconData? icon,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon ?? Icons.check, size: 18, color: Colors.white),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyan,
          disabledBackgroundColor: AppThemeColors.divider(context),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required bool enabled,
    required VoidCallback onToggle,
  }) {
    return tricolorBorder(
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          filled: true,
          fillColor: enabled
              ? AppThemeColors.cardBg(context)
              : AppThemeColors.surfaceBg(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                color: enabled
                    ? AppThemeColors.secondaryText(context)
                    : AppThemeColors.mutedText(context)),
            onPressed: enabled ? onToggle : null,
          ),
        ),
      ),
    );
  }
}
