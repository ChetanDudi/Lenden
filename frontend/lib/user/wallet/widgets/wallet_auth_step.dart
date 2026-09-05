import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/api_client.dart';
import '../../../otp_input.dart';
import '../../../settings/set_wallet_pin_page.dart';
import '../../../l10n/app_localizations.dart';

// Reusable wallet authentication step — shows a PIN/OTP toggle tab.
// Used inside Pay-to-User, Withdraw, QR-Pay and other sheets that
// require wallet auth before committing a payment.
class WalletAuthStep extends StatefulWidget {
  final bool hasPinSet;
  final bool paying;
  final void Function(String authField, String credential) onAuthenticated;
  final VoidCallback onBack;
  /// Override the OTP send endpoint. Defaults to the generic wallet-auth OTP.
  final String otpEndpoint;

  const WalletAuthStep({
    super.key,
    required this.hasPinSet,
    required this.onAuthenticated,
    required this.onBack,
    this.paying = false,
    this.otpEndpoint = '/api/wallet/auth/send-otp',
  });

  @override
  State<WalletAuthStep> createState() => _WalletAuthStepState();
}

class _WalletAuthStepState extends State<WalletAuthStep> {
  bool _usePinMode = true;
  String _code = '';
  bool _sendingOtp = false;
  bool _otpSent = false;
  String _otpEmail = '';
  int _timeRemaining = 120;
  Timer? _timer;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usePinMode = widget.hasPinSet;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String t(String key) => AppLocalizations.of(context).t(key);

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

  String _formatTime(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  Future<void> _sendOtp() async {
    setState(() {
      _sendingOtp = true;
      _error = null;
    });
    try {
      final res = await ApiClient.post(widget.otpEndpoint, body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _sendingOtp = false;
          _otpSent = true;
          _otpEmail = (data['email'] ?? '').toString();
          _timeRemaining = 120;
          _code = '';
        });
        _startTimer();
      } else {
        final err = jsonDecode(res.body);
        setState(() {
          _sendingOtp = false;
          _error = err['error'] ?? t('failed_to_send_otp_retry');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sendingOtp = false;
          _error = '$e';
        });
      }
    }
  }

  void _confirm() {
    if (_code.length != 6) {
      setState(() => _error = t('please_enter_valid_6_digit_otp'));
      return;
    }
    // Don't cancel the timer here — if auth fails the sheet stays open and
    // the timer must keep counting down. Timer is cancelled on success via dispose().
    widget.onAuthenticated(_usePinMode ? 'authPin' : 'authOtp', _code);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _sendingOtp || widget.paying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          _modeTab(t('use_pin_label'), Icons.dialpad_rounded, true),
          const SizedBox(width: 8),
          _modeTab(t('use_email_otp_label'), Icons.email_outlined, false),
        ]),
        const SizedBox(height: 16),

        if (_usePinMode) ...[
          if (!widget.hasPinSet) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(t('pin_not_set_message'),
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500))),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.dialpad_rounded,
                            color: Colors.white, size: 16),
                        label: Text(t('set_pin_title'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const SetWalletPinPage()));
                        },
                      ),
                    ),
                  ]),
            ),
          ] else ...[
            Text(t('enter_wallet_pin_label'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.secondaryText(context))),
            const SizedBox(height: 10),
            Center(
                child: OtpInput(
              onChanged: (code) => setState(() {
                _code = code;
                _error = null;
              }),
              enabled: !busy,
              autoFocus: true,
              obscureText: true,
              showVisibilityToggle: true,
            )),
          ],
        ],

        if (!_usePinMode) ...[
          if (!_otpSent) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _sendingOtp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.email_outlined, color: Colors.white),
                label: Text(
                    _sendingOtp ? t('sending_otp_label') : t('send_otp_label'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: busy ? null : _sendOtp,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: const Color(0xFFF0F7FF),
                    dark: const Color(0xFF16323A)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('otp_sent_to_email_desc'),
                        style: TextStyle(
                            fontSize: 12.5,
                            color: AppThemeColors.secondaryText(context))),
                    const SizedBox(height: 3),
                    Text(_otpEmail,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan,
                            fontSize: 13)),
                  ]),
            ),
            Center(
                child: OtpInput(
              onChanged: (code) => setState(() {
                _code = code;
                _error = null;
              }),
              enabled: !busy,
              autoFocus: true,
            )),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                      size: 14,
                      color:
                          _timeRemaining > 30 ? Colors.green : Colors.orange),
                  const SizedBox(width: 4),
                  Text(_formatTime(_timeRemaining),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _timeRemaining > 30
                              ? Colors.green
                              : Colors.orange)),
                ]),
              ),
              TextButton(
                onPressed: (_timeRemaining == 0 && !busy) ? _sendOtp : null,
                child: Text(t('resend_otp'),
                    style: TextStyle(
                      color: (_timeRemaining == 0 && !busy)
                          ? AppColors.cyan
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    )),
              ),
            ]),
          ],
        ],

        if (_error != null) ...[
          const SizedBox(height: 10),
          Container(
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
          ),
        ],
        const SizedBox(height: 16),

        if ((_usePinMode && widget.hasPinSet) || _otpSent)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.cyan,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: widget.paying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified_user_rounded,
                      color: Colors.white),
              label: Text(
                  widget.paying
                      ? t('processing_ellipsis_label')
                      : t('verify_and_pay_label'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white)),
              onPressed: busy ? null : _confirm,
            ),
          ),
        const SizedBox(height: 8),
        Center(
            child: TextButton(
          onPressed: busy ? null : widget.onBack,
          child: Text(t('cancel'),
              style: TextStyle(color: AppThemeColors.secondaryText(context))),
        )),
      ],
    );
  }

  Widget _modeTab(String label, IconData icon, bool isPinMode) {
    final selected = _usePinMode == isPinMode;
    return Expanded(
        child: GestureDetector(
      onTap: () => setState(() {
        _usePinMode = isPinMode;
        _code = '';
        _error = null;
        _otpSent = false;
        _timer?.cancel();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  selected ? AppColors.cyan : AppThemeColors.divider(context)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon,
              size: 15,
              color: selected
                  ? Colors.white
                  : AppThemeColors.secondaryText(context)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : AppThemeColors.secondaryText(context))),
        ]),
      ),
    ));
  }
}
