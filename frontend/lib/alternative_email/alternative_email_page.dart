import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:async';
import '../session.dart';
import '../otp_input.dart';
import '../settings/custom_warning_widget.dart';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AlternativeEmailPage extends StatefulWidget {
  const AlternativeEmailPage({super.key});

  @override
  State<AlternativeEmailPage> createState() => _AlternativeEmailPageState();
}

class _AlternativeEmailPageState extends State<AlternativeEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _showOtpInput = false;
  String? _currentAltEmail;
  String _otpCode = '';
  int _timeRemaining = 120; // 2 minutes in seconds
  Timer? _timer;
  String _targetEmail = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentAltEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCurrentAltEmail() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/users/me');

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        setState(() {
          _currentAltEmail = userData['altEmail'];
          if (_currentAltEmail != null && _currentAltEmail!.isNotEmpty) {
            _emailController.text = _currentAltEmail!;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context,
            '${AppLocalizations.of(context).t('error_loading_current_email')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSendingOtp = true;
    });

    try {
      final response = await ApiClient.post(
        '/api/users/alternative-email/send-otp',
        body: {'altEmail': _emailController.text.trim()},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, AppLocalizations.of(context).t('otp_sent_check_email'));
          setState(() {
            _showOtpInput = true;
            _targetEmail = _emailController.text.trim();
            _timeRemaining = 120;
            _otpCode = '';
          });
          _startTimer();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(context,
              errorData['message'] ?? AppLocalizations.of(context).t('failed_to_send_otp_retry'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, '${AppLocalizations.of(context).t('error_prefix')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingOtp = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    if (_otpCode.length != 6) {
      CustomWarningWidget.showAnimatedError(
          context, AppLocalizations.of(context).t('please_enter_valid_6_digit_otp'));
      return;
    }

    setState(() {
      _isVerifyingOtp = true;
    });

    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.post(
        '/api/users/alternative-email/verify-otp',
        body: {'altEmail': _targetEmail, 'otp': _otpCode},
      );

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, AppLocalizations.of(context).t('alt_email_verified_added'));
          _timer?.cancel();
          setState(() {
            _currentAltEmail = _targetEmail;
            _showOtpInput = false;
            _otpCode = '';
            _timeRemaining = 120;
          });
          // Refresh user profile
          await session.refreshUserProfile();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(context,
              errorData['message'] ?? AppLocalizations.of(context).t('failed_to_verify_otp'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, '${AppLocalizations.of(context).t('error_prefix')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = false;
        });
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_timeRemaining > 0) {
            _timeRemaining--;
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  void _resendOtp() {
    _timer?.cancel();
    _sendOtp();
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Future<void> _removeAlternativeEmail() async {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final t = AppLocalizations.of(dialogContext).t;
        return AlertDialog(
          backgroundColor: AppThemeColors.cardBg(dialogContext),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            t('remove_alternative_email'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(dialogContext),
            ),
          ),
          content: Text(
            t('remove_alt_email_confirm'),
            style: TextStyle(color: AppThemeColors.secondaryText(dialogContext)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                t('cancel'),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _performRemoveAlternativeEmail();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                t('remove'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performRemoveAlternativeEmail() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.delete('/api/users/alternative-email');

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, AppLocalizations.of(context).t('alt_email_removed_successfully'));
          setState(() {
            _currentAltEmail = null;
            _emailController.clear();
            _showOtpInput = false;
            _otpCode = '';
            _timeRemaining = 120;
          });
          _timer?.cancel();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(context,
              errorData['message'] ?? AppLocalizations.of(context).t('failed_to_remove_alt_email'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, '${AppLocalizations.of(context).t('error_prefix')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('alternative_email')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
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
                          const Icon(
                            Icons.email_outlined,
                            size: 48,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t('alternative_email'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('alt_email_backup_desc'),
                            style: TextStyle(
                              fontSize: 14,
                              color: AppThemeColors.secondaryText(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Current Alternative Email Display
                    if (_currentAltEmail != null &&
                        _currentAltEmail!.isNotEmpty &&
                        !_showOtpInput)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: Colors.green.withValues(alpha: 0.1),
                              dark: const Color(0xFF18301F)),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('current_alternative_email'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _currentAltEmail!,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_currentAltEmail != null &&
                        _currentAltEmail!.isNotEmpty &&
                        !_showOtpInput)
                      const SizedBox(height: 16),

                    // Email Input Field (only show when not verifying OTP)
                    if (!_showOtpInput)
                      tricolorBorder(
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return t('please_enter_email_address');
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                .hasMatch(value)) {
                              return t('please_enter_valid_email_address');
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            labelText: t('alternative_email'),
                            hintText: t('enter_alt_email_hint'),
                            border: InputBorder.none,
                            filled: true,
                            fillColor: AppThemeColors.cardBg(context),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                            prefixIcon: const Icon(Icons.email_outlined,
                                color: AppColors.cyan),
                          ),
                        ),
                      ),

                    // OTP Verification Section
                    if (_showOtpInput) ...[
                      const SizedBox(height: 24),

                      // Target Email Display
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: Colors.blue.withValues(alpha: 0.1),
                              dark: const Color(0xFF1A2733)),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('verifying_email_label'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _targetEmail,
                              style: TextStyle(
                                fontSize: 16,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // OTP Input
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
                            Text(
                              t('enter_verification_code'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t('otp_sent_to_email_desc'),
                              style: TextStyle(
                                fontSize: 14,
                                color: AppThemeColors.secondaryText(context),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),

                            // OTP Input Widget
                            OtpInput(
                              onChanged: (code) {
                                setState(() {
                                  _otpCode = code;
                                });
                              },
                              enabled: !_isVerifyingOtp,
                              autoFocus: true,
                            ),

                            const SizedBox(height: 24),

                            // Timer and Resend
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Timer
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _timeRemaining > 30
                                        ? Colors.green.withValues(alpha: 0.1)
                                        : Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _timeRemaining > 30
                                          ? Colors.green.withValues(alpha: 0.3)
                                          : Colors.orange.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.timer,
                                        size: 16,
                                        color: _timeRemaining > 30
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatTime(_timeRemaining),
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _timeRemaining > 30
                                              ? Colors.green
                                              : Colors.orange,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Resend Button
                                TextButton(
                                  onPressed:
                                      _timeRemaining == 0 && !_isSendingOtp
                                          ? _resendOtp
                                          : null,
                                  child: Text(
                                    t('resend_otp'),
                                    style: TextStyle(
                                      color:
                                          _timeRemaining == 0 && !_isSendingOtp
                                              ? AppColors.cyan
                                              : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Verify Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _otpCode.length == 6 && !_isVerifyingOtp
                                        ? _verifyOtp
                                        : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyan,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: _isVerifyingOtp
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Text(
                                        t('verify_otp'),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Cancel Button
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _isVerifyingOtp
                                    ? null
                                    : () {
                                        _timer?.cancel();
                                        setState(() {
                                          _showOtpInput = false;
                                          _otpCode = '';
                                          _timeRemaining = 120;
                                        });
                                      },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.grey, width: 1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text(
                                  t('cancel'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons (only show when not verifying OTP)
                    if (!_showOtpInput) ...[
                      if (_currentAltEmail != null &&
                          _currentAltEmail!.isNotEmpty)
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSendingOtp ? null : _sendOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.cyan,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: _isSendingOtp
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  Colors.white),
                                        ),
                                      )
                                    : Text(
                                        t('update_alternative_email'),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed:
                                    _isLoading ? null : _removeAlternativeEmail,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Colors.red, width: 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                ),
                                child: Text(
                                  t('remove_alternative_email'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSendingOtp ? null : _sendOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: _isSendingOtp
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : Text(
                                    t('send_verification_code'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                    ],

                    const SizedBox(height: 24),

                    // Information Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppThemeColors.tinted(context,
                            light: Colors.blue.withValues(alpha: 0.1),
                            dark: const Color(0xFF1A2733)),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('why_add_alt_email'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('alt_email_benefits_list'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
