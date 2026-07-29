import 'package:flutter/material.dart';
import '../utils/app_lock_service.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../otp_input.dart';

enum _AppLockState { idle, enteringPin, confirmingPin }

class AppLockSetupPage extends StatefulWidget {
  const AppLockSetupPage({super.key});

  @override
  State<AppLockSetupPage> createState() => _AppLockSetupPageState();
}

class _AppLockSetupPageState extends State<AppLockSetupPage> {
  bool _loading = true;
  bool _enabled = false;
  _AppLockState _state = _AppLockState.idle;
  String _firstPin = '';
  String _currentPin = '';
  int _pinKey = 0;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AppLockService.isEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
      _state = _AppLockState.idle;
      _message = null;
    });
  }

  void _startSetup() {
    setState(() {
      _state = _AppLockState.enteringPin;
      _firstPin = '';
      _currentPin = '';
      _pinKey++;
      _message = null;
    });
  }

  void _onPinEntered(String pin) => setState(() => _currentPin = pin);

  void _submitFirstPin() {
    if (_currentPin.length != 6) {
      _setMsg('Please enter all 6 digits.', error: true);
      return;
    }
    setState(() {
      _firstPin = _currentPin;
      _currentPin = '';
      _state = _AppLockState.confirmingPin;
      _pinKey++;
      _message = null;
    });
  }

  Future<void> _submitConfirmPin() async {
    if (_currentPin.length != 6) {
      _setMsg('Please enter all 6 digits.', error: true);
      return;
    }
    if (_currentPin != _firstPin) {
      _setMsg('PINs did not match. Please start over.', error: true);
      setState(() {
        _state = _AppLockState.enteringPin;
        _firstPin = '';
        _currentPin = '';
        _pinKey++;
      });
      return;
    }
    await AppLockService.setPin(_currentPin);
    if (!mounted) return;
    _setMsg('App lock enabled successfully.', error: false);
    _load();
  }

  Future<void> _disableLock() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(t('disable_app_lock_title'),
            style: TextStyle(fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
        content: Text(t('disable_app_lock_confirm'),
            style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t('disable'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLockService.disable();
    if (!mounted) return;
    _setMsg('App lock has been disabled.', error: false);
    _load();
  }

  void _cancelSetup() {
    setState(() {
      _state = _AppLockState.idle;
      _firstPin = '';
      _currentPin = '';
      _message = null;
    });
  }

  void _setMsg(String msg, {required bool error}) {
    if (mounted) setState(() { _message = msg; _isError = error; });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('app_lock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 32),
                  _buildHeroSection(t),
                  const SizedBox(height: 28),
                  _buildStatusCard(t),
                  const SizedBox(height: 20),
                  if (_message != null) _buildMessageBanner(),
                  if (_state == _AppLockState.idle) _buildIdleActions(t),
                  if (_state == _AppLockState.enteringPin) _buildPinEntry(t),
                  if (_state == _AppLockState.confirmingPin) _buildPinConfirm(t),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroSection(String Function(String) t) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _enabled
                  ? [AppColors.cyan, const Color(0xFF0077B6)]
                  : [Colors.grey.shade400, Colors.grey.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: (_enabled ? AppColors.cyan : Colors.grey).withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            _enabled ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t('app_lock'),
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppThemeColors.primaryText(context)),
        ),
        const SizedBox(height: 8),
        Text(
          'Protect your LenDen wallet and transactions with a 6-digit PIN. '
          'You\'ll be asked for it each time you open the app.',
          style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context), height: 1.5),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusCard(String Function(String) t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _enabled
              ? Colors.green.withValues(alpha: 0.4)
              : AppThemeColors.divider(context),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _enabled ? Icons.verified_user_rounded : Icons.gpp_maybe_outlined,
            color: _enabled ? Colors.green : AppThemeColors.mutedText(context),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _enabled ? 'App Lock is ON' : 'App Lock is OFF',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _enabled ? Colors.green : AppThemeColors.primaryText(context)),
                ),
                const SizedBox(height: 2),
                Text(
                  _enabled
                      ? 'A 6-digit PIN is required to open the app.'
                      : 'Anyone with your phone can access your wallet.',
                  style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _enabled
                  ? Colors.green.withValues(alpha: 0.12)
                  : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _enabled ? 'Active' : 'Inactive',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _enabled ? Colors.green : Colors.orange.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isError
              ? Colors.red.withValues(alpha: 0.08)
              : Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isError
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.green.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              _isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color: _isError ? Colors.red : Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _message!,
                style: TextStyle(
                    fontSize: 13,
                    color: _isError ? Colors.red.shade700 : Colors.green.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleActions(String Function(String) t) {
    if (!_enabled) {
      return Column(
        children: [
          _actionButton(
            label: 'Enable App Lock',
            icon: Icons.lock_rounded,
            onPressed: _startSetup,
          ),
        ],
      );
    }
    return Column(
      children: [
        _actionButton(
          label: t('change_pin'),
          icon: Icons.edit_rounded,
          onPressed: _startSetup,
          outlined: true,
        ),
        const SizedBox(height: 12),
        _actionButton(
          label: t('disable'),
          icon: Icons.lock_open_rounded,
          onPressed: _disableLock,
          danger: true,
          outlined: true,
        ),
      ],
    );
  }

  Widget _buildPinEntry(String Function(String) t) {
    return Column(
      children: [
        _stepLabel('Step 1 of 2 — Enter your new PIN'),
        const SizedBox(height: 6),
        Text(
          'Choose a 6-digit PIN you\'ll remember. Do not share it with anyone.',
          style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OtpInput(
          key: ValueKey(_pinKey),
          onChanged: _onPinEntered,
          enabled: true,
          autoFocus: true,
          obscureText: true,
          showVisibilityToggle: true,
        ),
        const SizedBox(height: 20),
        _actionButton(
          label: 'Next',
          icon: Icons.arrow_forward_rounded,
          onPressed: _currentPin.length == 6 ? _submitFirstPin : null,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _cancelSetup,
          child: const Text('Cancel', style: TextStyle(color: AppColors.cyan)),
        ),
      ],
    );
  }

  Widget _buildPinConfirm(String Function(String) t) {
    return Column(
      children: [
        _stepLabel('Step 2 of 2 — Confirm your PIN'),
        const SizedBox(height: 6),
        Text(
          'Re-enter the same PIN to confirm. This ensures you typed it correctly.',
          style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        OtpInput(
          key: ValueKey(_pinKey),
          onChanged: _onPinEntered,
          enabled: true,
          autoFocus: true,
          obscureText: true,
          showVisibilityToggle: true,
        ),
        const SizedBox(height: 20),
        _actionButton(
          label: 'Set PIN & Enable',
          icon: Icons.lock_rounded,
          onPressed: _currentPin.length == 6 ? _submitConfirmPin : null,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _cancelSetup,
          child: const Text('Cancel', style: TextStyle(color: AppColors.cyan)),
        ),
      ],
    );
  }

  Widget _stepLabel(String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.radio_button_checked_rounded, size: 15, color: AppColors.cyan),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(context))),
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool outlined = false,
    bool danger = false,
  }) {
    final color = danger ? Colors.red : AppColors.cyan;
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: color),
              label: Text(label,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: onPressed != null ? color : AppThemeColors.divider(context)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: Colors.white),
              label: Text(label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: onPressed != null ? color : AppThemeColors.divider(context),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
    );
  }
}
