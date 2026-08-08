import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/api_client.dart';
import '../settings/custom_warning_widget.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../otp_input.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  // ── normal flow ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // ── forgot-current-password flow ───────────────────────────────────────────
  bool _forgotMode = false;
  bool _hasPinSet = false;
  bool _usePinMode = false;

  // OTP state
  bool _otpSent = false;
  bool _isSending = false;
  String _otp = '';
  int _otpKey = 0;
  int _secondsLeft = 0;
  Timer? _timer;

  // PIN state
  String _pin = '';

  // verification
  bool _forgotVerified = false;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _loadPinStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _currentPasswordController.dispose();
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

  // ── normal change password ─────────────────────────────────────────────────
  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.post('/api/users/change-password', body: {
        'currentPassword': _currentPasswordController.text,
        'newPassword': _newPasswordController.text,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        CustomWarningWidget.showAnimatedSuccess(
            context, AppLocalizations.of(context).t('password_changed_successfully'));
        Navigator.pop(context);
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? AppLocalizations.of(context).t('failed_to_change_password'));
      }
    } catch (_) {
      if (mounted) _showErr(AppLocalizations.of(context).t('network_error_retry'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── forgot flow ────────────────────────────────────────────────────────────
  Future<void> _sendOtp() async {
    setState(() => _isSending = true);
    try {
      final res = await ApiClient.post('/api/users/change-password/send-otp');
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() { _otpSent = true; _otp = ''; _otpKey++; });
        _startTimer();
        CustomWarningWidget.showAnimatedSuccess(context, AppLocalizations.of(context).t('otp_sent_to_email'));
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? AppLocalizations.of(context).t('failed_to_send_otp'));
      }
    } catch (_) {
      if (mounted) _showErr(AppLocalizations.of(context).t('network_error_retry'));
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

  Future<void> _verifyIdentity() async {
    setState(() => _verifying = true);
    try {
      final body = _usePinMode ? {'pin': _pin} : {'otp': _otp};
      final res = await ApiClient.post('/api/users/change-password/verify-identity', body: body);
      if (!mounted) return;
      if (res.statusCode == 200) {
        _timer?.cancel();
        setState(() { _forgotVerified = true; _verifying = false; });
        CustomWarningWidget.showAnimatedSuccess(context, AppLocalizations.of(context).t('identity_verified_msg'));
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? AppLocalizations.of(context).t('verification_failed'));
        setState(() => _verifying = false);
      }
    } catch (_) {
      if (mounted) { _showErr(AppLocalizations.of(context).t('network_error_retry')); setState(() => _verifying = false); }
    }
  }

  Future<void> _changeForgotPassword() async {
    final newPw = _newPasswordController.text;
    final confirmPw = _confirmPasswordController.text;
    final t = AppLocalizations.of(context).t;
    if (newPw.length < 8) { _showErr(t('password_min_length_error')); return; }
    if (newPw.length > 30) { _showErr(t('password_max_length_error')); return; }
    if (newPw != confirmPw) { _showErr(t('passwords_do_not_match')); return; }

    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.post('/api/users/change-password', body: {
        'forgotMode': true,
        'newPassword': newPw,
      });
      if (!mounted) return;
      if (res.statusCode == 200) {
        CustomWarningWidget.showAnimatedSuccess(context, t('password_changed_successfully'));
        Navigator.pop(context);
      } else {
        final data = jsonDecode(res.body);
        _showErr(data['message'] ?? t('failed_to_change_password'));
      }
    } catch (_) {
      if (mounted) _showErr(AppLocalizations.of(context).t('network_error_retry'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErr(String msg) {
    if (mounted) CustomWarningWidget.showAnimatedError(context, msg);
  }

  // ── build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final newPwd = _newPasswordController.text;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('change_password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: _forgotMode ? _buildForgotFlow(t, newPwd) : _buildNormalFlow(t, newPwd),
      ),
    );
  }

  // ── normal flow UI ─────────────────────────────────────────────────────────
  Widget _buildNormalFlow(AppLocalTranslator t, String newPwd) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerCard(
            icon: Icons.lock_outline,
            title: t('change_your_password_title'),
            subtitle: t('enter_current_choose_new'),
          ),
          const SizedBox(height: 24),

          _buildPasswordField(
            controller: _currentPasswordController,
            label: t('current_password'),
            hint: t('enter_current_password'),
            obscure: _obscureCurrent,
            onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            validator: (v) => (v == null || v.isEmpty) ? t('please_enter_current_password') : null,
          ),

          // Forgot current password link
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() { _forgotMode = true; }),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: Text(t('forgot_current_password'),
                  style: const TextStyle(fontSize: 12, color: AppColors.cyan)),
            ),
          ),

          const SizedBox(height: 8),

          _buildPasswordField(
            controller: _newPasswordController,
            label: t('new_password'),
            hint: t('new_password_hint'),
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
            validator: (v) {
              if (v == null || v.isEmpty) return t('please_enter_new_password');
              if (v.length < 8) return t('password_min_length_error');
              if (v.length > 30) return t('password_max_length_error');
              return null;
            },
          ),

          if (newPwd.isNotEmpty) ...[
            const SizedBox(height: 10),
            PasswordStrengthMeter(password: newPwd),
          ],

          const SizedBox(height: 16),

          _buildPasswordField(
            controller: _confirmPasswordController,
            label: t('confirm_new_password'),
            hint: t('re_enter_new_password'),
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            validator: (v) {
              if (v == null || v.isEmpty) return t('please_confirm_new_password');
              if (v != _newPasswordController.text) return t('passwords_do_not_match');
              return null;
            },
          ),

          const SizedBox(height: 28),

          _submitButton(
            label: _isLoading ? t('changing_label') : t('change_password'),
            loading: _isLoading,
            onPressed: _isLoading ? null : _changePassword,
          ),
        ],
      ),
    );
  }

  // ── forgot flow UI ─────────────────────────────────────────────────────────
  Widget _buildForgotFlow(AppLocalTranslator t, String newPwd) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerCard(
          icon: Icons.lock_reset_rounded,
          title: t('forgot_current_password_title'),
          subtitle: t('forgot_current_password_subtitle'),
        ),

        const SizedBox(height: 8),

        // Back to normal flow
        TextButton.icon(
          onPressed: () => setState(() { _forgotMode = false; _forgotVerified = false; }),
          icon: const Icon(Icons.arrow_back, size: 14, color: AppColors.cyan),
          label: Text(t('back_i_remember_password'),
              style: const TextStyle(fontSize: 12, color: AppColors.cyan)),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),

        const SizedBox(height: 16),

        // ── Step 1: Verify identity ──────────────────────────────────────
        _stepLabel(t('step_verify_identity'), done: _forgotVerified),
        const SizedBox(height: 10),

        if (!_forgotVerified) ...[
          if (_hasPinSet) ...[
            Row(
              children: [
                _modeTab(t('mode_email_otp'), Icons.email_outlined, !_usePinMode,
                    () => setState(() { _usePinMode = false; })),
                const SizedBox(width: 8),
                _modeTab(t('mode_wallet_pin'), Icons.dialpad_rounded, _usePinMode,
                    () => setState(() { _usePinMode = true; })),
              ],
            ),
            const SizedBox(height: 14),
          ],

          if (!_usePinMode) ...[
            if (!_otpSent)
              _submitButton(
                label: _isSending ? t('sending_label') : t('send_otp_to_email'),
                loading: _isSending,
                onPressed: _isSending ? null : _sendOtp,
                icon: Icons.send_rounded,
              )
            else ...[
              OtpInput(
                key: ValueKey(_otpKey),
                onChanged: (v) => setState(() => _otp = v),
                enabled: true,
                autoFocus: true,
              ),
              const SizedBox(height: 8),
              _timerResendRow(),
              const SizedBox(height: 12),
              _submitButton(
                label: _verifying ? t('verifying_label') : t('verify_otp_button'),
                loading: _verifying,
                onPressed: _otp.length == 6 && !_verifying ? _verifyIdentity : null,
                icon: Icons.verified_user_outlined,
              ),
            ],
          ],

          if (_usePinMode) ...[
            Text(t('enter_wallet_pin_6digit'),
                style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 10),
            OtpInput(
              key: const ValueKey('forgot_pin'),
              onChanged: (v) => setState(() => _pin = v),
              enabled: true,
              autoFocus: true,
            ),
            const SizedBox(height: 14),
            _submitButton(
              label: _verifying ? t('verifying_label') : t('verify_pin_button'),
              loading: _verifying,
              onPressed: _pin.length == 6 && !_verifying ? _verifyIdentity : null,
              icon: Icons.dialpad_rounded,
            ),
          ],
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text(t('identity_verified_label'), style: const TextStyle(fontSize: 13, color: Colors.green, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // ── Step 2: New password ─────────────────────────────────────────
        _stepLabel(t('step_set_new_password'), done: false),
        const SizedBox(height: 10),

        _buildPasswordField(
          controller: _newPasswordController,
          label: t('new_password'),
          hint: t('new_password_hint_letters'),
          obscure: _obscureNew,
          enabled: _forgotVerified,
          onToggle: () => setState(() => _obscureNew = !_obscureNew),
        ),

        if (_forgotVerified && newPwd.isNotEmpty) ...[
          const SizedBox(height: 10),
          PasswordStrengthMeter(password: newPwd),
        ],

        const SizedBox(height: 14),

        _buildPasswordField(
          controller: _confirmPasswordController,
          label: t('confirm_new_password'),
          hint: t('re_enter_new_password'),
          obscure: _obscureConfirm,
          enabled: _forgotVerified,
          onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),

        const SizedBox(height: 24),

        _submitButton(
          label: _isLoading ? t('changing_label') : t('change_password'),
          loading: _isLoading,
          onPressed: _forgotVerified && !_isLoading ? _changeForgotPassword : null,
        ),
      ],
    );
  }

  Widget _timerResendRow() {
    return Row(
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
          label: Text(AppLocalizations.of(context).t('resend_otp_label'),
              style: TextStyle(fontSize: 12,
                  color: _secondsLeft == 0 ? AppColors.cyan : AppThemeColors.mutedText(context))),
          style: TextButton.styleFrom(
              padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        ),
      ],
    );
  }

  // ── shared helpers ──────────────────────────────────────────────────────────
  Widget _headerCard({required IconData icon, required String title, required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.grey.withValues(alpha: 0.1), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.cyan),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 8),
          Text(subtitle,
              style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _stepLabel(String text, {required bool done}) {
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
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                      color: active ? Colors.white : AppThemeColors.secondaryText(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _submitButton({
    required String label,
    required bool loading,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(icon ?? Icons.check_rounded, size: 18, color: Colors.white),
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
    bool enabled = true,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return tricolorBorder(
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          filled: true,
          fillColor: enabled ? AppThemeColors.cardBg(context) : AppThemeColors.surfaceBg(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                color: enabled ? AppThemeColors.secondaryText(context) : AppThemeColors.mutedText(context)),
            onPressed: enabled ? onToggle : null,
          ),
        ),
      ),
    );
  }
}

// Shorthand type for the translation function
typedef AppLocalTranslator = String Function(String);
