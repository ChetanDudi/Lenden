import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../otp_input.dart';
import '../services/wallet_service.dart';

/// Set, change, or remove the 6-digit wallet transaction PIN.
///
/// Three distinct paths — each requires only ONE form of verification:
///
///   Set (first time) → Email OTP only → enter new PIN
///   Change (knows PIN) → Current PIN only → enter new PIN
///   Forgot PIN → Email OTP only → enter new PIN   (no current PIN)
///   Remove → Current PIN only
class SetWalletPinPage extends StatefulWidget {
  const SetWalletPinPage({super.key});

  @override
  State<SetWalletPinPage> createState() => _SetWalletPinPageState();
}

enum _Mode { loading, noPin, hasPin, setNew, change, forgotPin, remove }

class _SetWalletPinPageState extends State<SetWalletPinPage> {
  _Mode _mode = _Mode.loading;
  bool _submitting = false;
  String? _error;

  // PIN inputs
  String _currentPin = '';
  String _newPin = '';
  String _confirmPin = '';

  // Email OTP (used by first-time set + forgot-PIN paths)
  String _otp = '';
  String? _verifiedOtp;
  bool _sendingOtp = false;
  bool _verifyingOtp = false;
  bool _otpSent = false;
  bool _otpConfirmed =
      false; // set only after a successful server-side OTP verification
  String _otpEmail = '';
  int _timeRemaining = 0;
  Timer? _timer;

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPinStatus() async {
    try {
      final data = await WalletService.getPinStatus();
      if (!mounted) return;
      setState(() =>
          _mode = (data['hasPin'] == true) ? _Mode.hasPin : _Mode.noPin);
    } catch (_) {
      if (mounted) setState(() => _mode = _Mode.noPin);
    }
  }

  // ── Email OTP helpers (first-time set + forgot-PIN) ─────────────────────

  Future<void> _sendOtp() async {
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      final data = await WalletService.sendPinOtp();
      if (!mounted) return;
      setState(() {
        _sendingOtp = false;
        _verifyingOtp = false;
        _otpSent = true;
        _otpConfirmed = false;
        _otpEmail = (data['email'] ?? '').toString();
        _timeRemaining = 60;
        _otp = '';
      });
      _startTimer();
    } catch (e) {
      if (mounted) setState(() { _sendingOtp = false; _error = '$e'; });
    }
  }

  Future<void> _verifyOtpCode() async {
    if (_otp.length != 6) {
      _timer?.cancel();
      setState(() {
        _otp = '';
        _timeRemaining = 0;
        _error = t('otp_required');
      });
      return;
    }

    setState(() {
      _verifyingOtp = true;
      _error = null;
    });
    try {
      await WalletService.verifyPinOtp(_otp);
      if (!mounted) return;
      setState(() {
        _otpConfirmed = true;
        _verifyingOtp = false;
        _error = null;
        _timeRemaining = 0;
        _verifiedOtp = _otp;
      });
      _timer?.cancel();
    } catch (e) {
      _timer?.cancel();
      if (!mounted) return;
      setState(() {
        _verifyingOtp = false;
        _otp = '';
        _verifiedOtp = null;
        _timeRemaining = 0;
        if (e is ServiceException) {
          _otpConfirmed = false;
          _error = e.message.isEmpty ? t('invalid_otp') : e.message;
        } else {
          _otpSent = false;
          _error = 'Unable to verify OTP. Please request a new OTP.';
        }
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_timeRemaining > 0) {
          _timeRemaining--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String _fmt(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  // ── Submission ────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _error = null;
    });

    // Validate
    if (_mode == _Mode.setNew || _mode == _Mode.noPin) {
      if (!_otpConfirmed) {
        setState(() => _error =
            'Please confirm the OTP sent to your email before setting your PIN.');
        return;
      }
      if (_newPin.length != 6 || _confirmPin.length != 6) {
        setState(() =>
            _error = 'Please enter a complete 6-digit PIN in both fields.');
        return;
      }
      if (_newPin != _confirmPin) {
        setState(() => _error = 'PINs do not match. Please try again.');
        return;
      }
    }

    if (_mode == _Mode.change) {
      if (_currentPin.length != 6) {
        setState(() => _error = 'Please enter your current PIN.');
        return;
      }
      if (_newPin.length != 6 || _confirmPin.length != 6) {
        setState(() => _error = 'Please complete both new PIN fields.');
        return;
      }
      if (_newPin != _confirmPin) {
        setState(() => _error = 'New PINs do not match.');
        return;
      }
    }

    if (_mode == _Mode.forgotPin) {
      if (!_otpConfirmed) {
        setState(() => _error =
            'Please confirm the OTP sent to your email before resetting your PIN.');
        return;
      }
      if (_newPin.length != 6 || _confirmPin.length != 6) {
        setState(() => _error = 'Please complete both new PIN fields.');
        return;
      }
      if (_newPin != _confirmPin) {
        setState(() => _error = 'New PINs do not match.');
        return;
      }
    }

    if (_mode == _Mode.remove) {
      if (_currentPin.length != 6) {
        setState(() => _error = 'Please enter your current PIN.');
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      if (_mode == _Mode.remove) {
        await WalletService.removePin(_currentPin);
        if (!mounted) return;
        _timer?.cancel();
        showSnack(context, t('pin_removed_message'));
        _resetAndLoad();
      } else {
        // set, change, or forgot — all go to /pin/set; payload differs
        final body = <String, dynamic>{'newPin': _newPin};
        if (_mode == _Mode.change) body['currentPin'] = _currentPin;
        if (_mode == _Mode.setNew ||
            _mode == _Mode.noPin ||
            _mode == _Mode.forgotPin) {
          body['otp'] = _verifiedOtp ?? _otp;
        }
        await WalletService.setPin(body);
        if (!mounted) return;
        _timer?.cancel();
        final msg = _mode == _Mode.change || _mode == _Mode.forgotPin
            ? t('pin_changed_successfully_message')
            : t('pin_set_successfully_message');
        showSnack(context, msg);
        _resetAndLoad();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  void _resetAndLoad() {
    _timer?.cancel();
    setState(() {
      _currentPin = '';
      _newPin = '';
      _confirmPin = '';
      _otp = '';
      _verifiedOtp = null;
      _otpSent = false;
      _otpConfirmed = false;
      _otpEmail = '';
      _timeRemaining = 0;
      _verifyingOtp = false;
      _error = null;
      _mode = _Mode.loading;
    });
    _loadPinStatus();
  }

  void _enterMode(_Mode m) {
    _timer?.cancel();
    setState(() {
      _mode = m;
      _error = null;
      _currentPin = '';
      _newPin = '';
      _confirmPin = '';
      _otp = '';
      _verifiedOtp = null;
      _otpSent = false;
      _otpConfirmed = false;
      _otpEmail = '';
      _timeRemaining = 0;
      _verifyingOtp = false;
    });
  }

  // ── Shared UI pieces ──────────────────────────────────────────────────────

  Widget _errBox() => _error == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 16),
            const SizedBox(width: 8),
            Flexible(
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red, fontSize: 13))),
          ]),
        );

  Widget _pinField(String label, void Function(String) onChanged,
          {bool autoFocus = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppThemeColors.secondaryText(context))),
        const SizedBox(height: 10),
        Center(
            child: OtpInput(
          onChanged: (code) {
            onChanged(code);
            setState(() => _error = null);
          },
          enabled: !_submitting,
          autoFocus: autoFocus,
          obscureText: true,
          showVisibilityToggle: true,
        )),
      ]);

  /// OTP section for first-time set and forgot-PIN paths.
  Widget _otpSection() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.tinted(context,
              light: const Color(0xFFF0F7FF), dark: const Color(0xFF16323A)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.email_outlined, color: AppColors.cyan, size: 16),
            const SizedBox(width: 8),
            const Text('Verify your email',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 6),
          Text(
            _otpSent
                ? 'OTP sent to $_otpEmail'
                : 'We\'ll send a one-time code to your registered email.',
            style: TextStyle(
                fontSize: 12, color: AppThemeColors.secondaryText(context)),
          ),
          if (_otpSent) ...[
            if (_otpConfirmed) ...[
              // Already confirmed — show success badge
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  const Text('Email verified ✓',
                      style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _otpConfirmed = false;
                      _otp = '';
                    }),
                    child: const Text('Change',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 14),
              Center(
                  child: OtpInput(
                onChanged: (code) => setState(() {
                  _otp = code;
                  _otpConfirmed = false;
                  _error = null;
                }),
                enabled: !_submitting && !_verifyingOtp,
                autoFocus: false,
              )),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_timeRemaining > 30 ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            (_timeRemaining > 30 ? Colors.green : Colors.orange)
                                .withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer,
                        size: 13,
                        color:
                            _timeRemaining > 30 ? Colors.green : Colors.orange),
                    const SizedBox(width: 4),
                    Text(_fmt(_timeRemaining),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _timeRemaining > 30
                                ? Colors.green
                                : Colors.orange)),
                  ]),
                ),
                TextButton(
                  onPressed: _sendingOtp ? null : _sendOtp,
                  child: Text(t('resend_otp'),
                      style: TextStyle(
                        color: _sendingOtp ? Colors.grey : AppColors.cyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      )),
                ),
              ]),
              const SizedBox(height: 10),
              if (_error != null) ...[
                _errBox(),
                const SizedBox(height: 10),
              ],
              // Confirm button — validates the entered OTP code
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _verifyingOtp
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline,
                          color: Colors.white, size: 16),
                  label: Text(
                      _verifyingOtp
                          ? t('verifying_otp_label')
                          : t('verify_otp'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  onPressed: _otp.length == 6 && !_verifyingOtp
                      ? _verifyOtpCode
                      : null,
                ),
              ),
            ],
          ] else ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.cyan,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                icon: _sendingOtp
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 14),
                label: Text(
                  t('send_otp_label'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                ),
                onPressed: _sendingOtp ? null : _sendOtp,
              ),
            ),
          ],
        ]),
      );

  Widget _statusCard() {
    final bool hasPin =
        _mode == _Mode.hasPin || _mode == _Mode.change || _mode == _Mode.remove;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasPin
            ? AppColors.cyan.withValues(alpha: 0.08)
            : AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: hasPin
                ? AppColors.cyan.withValues(alpha: 0.3)
                : AppColors.cyan.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasPin
                  ? AppColors.cyan.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              hasPin ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
              color: hasPin ? AppColors.cyan : Colors.orange,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPin ? 'Wallet PIN is active' : 'No wallet PIN yet',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  hasPin
                      ? 'Use the masked PIN below for quick wallet approvals. You can change or remove it anytime.'
                      : 'Set a 6-digit PIN to authorize wallet payments without waiting for email OTP.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppThemeColors.secondaryText(context)),
                ),
                if (hasPin) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text('●●●●●●',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitBtn(String label, {Color? color}) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? AppColors.cyan,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white)),
        ),
      );

  Widget _optionTile(
      {required IconData icon,
      required String label,
      VoidCallback? onTap,
      Color? color}) {
    final c = color ?? AppColors.cyan;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: c)),
          const Spacer(),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 14, color: AppThemeColors.mutedText(context)),
        ]),
      ),
    );
  }

  Widget _backBtn({_Mode backTo = _Mode.hasPin}) => Center(
          child: TextButton(
        onPressed: () => _enterMode(backTo),
        child: Text(t('cancel'),
            style: TextStyle(color: AppThemeColors.secondaryText(context))),
      ));

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appBarTitle = switch (_mode) {
      _Mode.change => t('change_pin_title'),
      _Mode.forgotPin => 'Reset PIN',
      _Mode.remove => t('remove_pin_title'),
      _ => t('wallet_transaction_pin_label'),
    };

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        title: Text(appBarTitle,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
      ),
      body: _mode == _Mode.loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.cyan))
          : SafeArea(
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── No PIN set → set first time (email OTP + new PIN) ──────
                    if (_mode == _Mode.noPin || _mode == _Mode.setNew) ...[
                      _infoBox(
                          'Set a 6-digit PIN to authorize payments instantly — no email OTP wait.'),
                      const SizedBox(height: 16),
                      _otpSection(),
                      _statusCard(),
                      if (_otpConfirmed) ...[
                        const SizedBox(height: 20),
                        _pinField(t('enter_new_pin_label'), (v) => _newPin = v,
                            autoFocus: true),
                        const SizedBox(height: 20),
                        _pinField(
                            t('confirm_new_pin_label'), (v) => _confirmPin = v),
                        _errBox(),
                        const SizedBox(height: 24),
                        _submitBtn(t('set_pin_title')),
                      ],
                    ],

                    // ── Has PIN → options ────────────────────────────────────────
                    if (_mode == _Mode.hasPin) ...[
                      _infoBox('Your wallet PIN is active.'),
                      const SizedBox(height: 16),
                      _statusCard(),
                      _optionTile(
                          icon: Icons.edit_rounded,
                          label: t('change_pin_title'),
                          onTap: () => _enterMode(_Mode.change)),
                      const SizedBox(height: 12),
                      _optionTile(
                          icon: Icons.delete_outline_rounded,
                          label: t('remove_pin_title'),
                          color: Colors.red,
                          onTap: () => _enterMode(_Mode.remove)),
                    ],

                    // ── Change PIN — current PIN only, no OTP ────────────────────
                    if (_mode == _Mode.change) ...[
                      _infoBox(
                          'Enter your current PIN to change it. If you\'ve forgotten it, use "Forgot PIN" below.'),
                      const SizedBox(height: 16),
                      _statusCard(),
                      const SizedBox(height: 4),
                      _pinField(
                          t('enter_current_pin_label'), (v) => _currentPin = v,
                          autoFocus: true),
                      const SizedBox(height: 20),
                      _pinField(t('enter_new_pin_label'), (v) => _newPin = v),
                      const SizedBox(height: 20),
                      _pinField(
                          t('confirm_new_pin_label'), (v) => _confirmPin = v),
                      _errBox(),
                      const SizedBox(height: 24),
                      _submitBtn(t('change_pin_title')),
                      const SizedBox(height: 12),
                      // Forgot PIN escape hatch
                      Center(
                          child: TextButton.icon(
                        icon: const Icon(Icons.lock_reset_rounded, size: 16),
                        label:
                            const Text('Forgot PIN? Verify via Email instead'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppColors.cyan),
                        onPressed: () => _enterMode(_Mode.forgotPin),
                      )),
                      _backBtn(),
                    ],

                    // ── Forgot PIN — email OTP only, no current PIN ──────────────
                    if (_mode == _Mode.forgotPin) ...[
                      _infoBox(
                          'Verify your email to reset your PIN — no current PIN needed.'),
                      const SizedBox(height: 16),
                      _otpSection(),
                      _statusCard(),
                      if (_otpConfirmed) ...[
                        const SizedBox(height: 20),
                        _pinField(t('enter_new_pin_label'), (v) => _newPin = v,
                            autoFocus: true),
                        const SizedBox(height: 20),
                        _pinField(
                            t('confirm_new_pin_label'), (v) => _confirmPin = v),
                        _errBox(),
                        const SizedBox(height: 24),
                        _submitBtn('Reset PIN'),
                      ],
                      if (!_otpConfirmed) const SizedBox(height: 12),
                      _backBtn(),
                    ],

                    // ── Remove PIN — current PIN only, no OTP ────────────────────
                    if (_mode == _Mode.remove) ...[
                      _infoBox('Enter your current PIN to remove it.'),
                      const SizedBox(height: 16),
                      _statusCard(),
                      const SizedBox(height: 4),
                      _pinField(
                          t('enter_current_pin_label'), (v) => _currentPin = v,
                          autoFocus: true),
                      _errBox(),
                      const SizedBox(height: 24),
                      _submitBtn(t('remove_pin_title'), color: Colors.red),
                      const SizedBox(height: 12),
                      _backBtn(),
                    ],
                  ]),
            )),
    );
  }

  Widget _infoBox(String text) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.cyan.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          const Icon(Icons.dialpad_rounded, color: AppColors.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: AppThemeColors.secondaryText(context)))),
        ]),
      );
}
