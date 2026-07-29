import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../utils/api_client.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isSending = false;
  bool _otpSent = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 120);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _sendOtp() async {
    setState(() => _isSending = true);
    try {
      final response = await ApiClient.post('/api/users/set-password/send-otp');
      if (!mounted) return;
      if (response.statusCode == 200) {
        setState(() => _otpSent = true);
        _startTimer();
        CustomWarningWidget.showAnimatedSuccess(context, 'OTP sent to your email.');
      } else {
        final data = json.decode(response.body);
        CustomWarningWidget.showAnimatedError(
            context, data['message'] ?? 'Failed to send OTP.');
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _confirmSetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.post(
        '/api/users/set-password/confirm',
        body: {
          'otp': _otpController.text.trim(),
          'newPassword': _newPasswordController.text,
        },
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        // Refresh session so hasPassword is updated
        final session = Provider.of<SessionProvider>(context, listen: false);
        await session.refreshUserProfile();
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, 'Password set successfully!');
          Navigator.pop(context);
        }
      } else {
        final data = json.decode(response.body);
        CustomWarningWidget.showAnimatedError(
            context, data['message'] ?? 'Failed to set password.');
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final email = session.user?['email'] as String? ?? '';
    final newPwd = _newPasswordController.text;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: 'Set Password'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 1,
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock_person_rounded,
                          size: 34, color: AppColors.cyan),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Set Your Password',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Verify your identity via a one-time code sent to your email, then choose a password.',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppThemeColors.secondaryText(context)),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Email display
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.cyan.withValues(alpha: 0.35), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined,
                        size: 18, color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        email,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                    if (_otpSent)
                      const Icon(Icons.check_circle_outline,
                          size: 16, color: Colors.green),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Send OTP button (step 1) or resend link (step 2)
              if (!_otpSent)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _sendOtp,
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded,
                            size: 18, color: Colors.white),
                    label: Text(
                      _isSending ? 'Sending…' : 'Send OTP to Email',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

              if (_otpSent) ...[
                // OTP field
                tricolorBorder(
                  child: TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8),
                    decoration: InputDecoration(
                      labelText: 'Enter 6-digit OTP',
                      hintText: '• • • • • •',
                      border: InputBorder.none,
                      filled: true,
                      fillColor: AppThemeColors.cardBg(context),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                    validator: (v) {
                      if (v == null || v.length != 6) {
                        return 'Please enter the 6-digit OTP.';
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: 8),

                // Timer / resend row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_secondsLeft > 0)
                      Text(
                        'Resend in $_secondsLeft s',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppThemeColors.secondaryText(context)),
                      )
                    else
                      TextButton.icon(
                        onPressed: _isSending ? null : _sendOtp,
                        icon: const Icon(Icons.refresh_rounded,
                            size: 15, color: AppColors.cyan),
                        label: const Text('Resend OTP',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.cyan)),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // New password
                _buildPasswordField(
                  controller: _newPasswordController,
                  label: 'New Password',
                  hint: 'At least 8 characters',
                  obscure: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Please enter a password.';
                    if (v.length < 8) return 'Password must be at least 8 characters.';
                    if (v.length > 30) return 'Password must be at most 30 characters.';
                    return null;
                  },
                ),

                if (newPwd.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PasswordStrengthMeter(password: newPwd),
                ],

                const SizedBox(height: 16),

                // Confirm password
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  hint: 'Re-enter your password',
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please confirm your password.';
                    }
                    if (v != _newPasswordController.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 32),

                // Submit
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _confirmSetPassword,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white)),
                          )
                        : const Text(
                            'Set Password',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return tricolorBorder(
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: InputBorder.none,
          filled: true,
          fillColor: AppThemeColors.cardBg(context),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              color: AppThemeColors.secondaryText(context),
            ),
            onPressed: onToggle,
          ),
        ),
      ),
    );
  }
}
