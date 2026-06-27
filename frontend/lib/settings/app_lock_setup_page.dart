import 'package:flutter/material.dart';
import '../utils/app_lock_service.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AppLockSetupPage extends StatefulWidget {
  const AppLockSetupPage({super.key});

  @override
  State<AppLockSetupPage> createState() => _AppLockSetupPageState();
}

class _AppLockSetupPageState extends State<AppLockSetupPage> {
  bool _loading = true;
  bool _enabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AppLockService.isEnabled();
    final bioAvailable = await AppLockService.isBiometricAvailable();
    final bioEnabled = await AppLockService.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _biometricAvailable = bioAvailable;
      _biometricEnabled = bioEnabled;
      _loading = false;
    });
  }

  Future<void> _setupPin() async {
    final t = AppLocalizations.of(context).t;
    final pin = await _showPinDialog(t('set_a_pin_title'));
    if (pin == null || pin.length < 4) return;
    final confirm = await _showPinDialog(t('confirm_your_pin_title'));
    if (confirm != pin) {
      showSnack(context, t('pins_did_not_match'), isError: true);
      return;
    }
    await AppLockService.setPin(pin);
    showSnack(context, t('app_lock_enabled_msg'));
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
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
        content: Text(t('disable_app_lock_confirm'),
            style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel')),
          ),
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
    showSnack(context, t('app_lock_disabled_msg'));
    _load();
  }

  Future<String?> _showPinDialog(String title) async {
    final controller = TextEditingController();
    final t = AppLocalizations.of(context).t;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          style: TextStyle(color: AppThemeColors.primaryText(ctx)),
          decoration: InputDecoration(
            hintText: t('pin_hint_4_6_digit'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.cyan),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(t('ok'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('app_lock'),
            style: TextStyle(
                color: AppThemeColors.primaryText(context),
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                tricolorBorder(
                  child: Container(
                    color: AppThemeColors.cardBg(context),
                    child: SwitchListTile(
                      title: Text(t('pin_app_lock'),
                          style: TextStyle(color: AppThemeColors.primaryText(context))),
                      subtitle: Text(
                        _enabled
                            ? t('app_lock_enabled_subtitle')
                            : t('require_pin_subtitle'),
                        style: TextStyle(color: AppThemeColors.secondaryText(context)),
                      ),
                      value: _enabled,
                      activeColor: AppColors.cyan,
                      onChanged: (v) {
                        if (v) {
                          _setupPin();
                        } else {
                          _disableLock();
                        }
                      },
                    ),
                  ),
                ),
                if (_enabled) ...[
                  const SizedBox(height: 12),
                  tricolorBorder(
                    child: Container(
                      color: AppThemeColors.cardBg(context),
                      child: Column(
                        children: [
                          ListTile(
                            title: Text(t('change_pin'),
                                style: TextStyle(color: AppThemeColors.primaryText(context))),
                            leading: const Icon(Icons.pin_outlined, color: AppColors.cyan),
                            onTap: _setupPin,
                          ),
                          if (_biometricAvailable)
                            SwitchListTile(
                              title: Text(t('biometric_unlock_title'),
                                  style: TextStyle(color: AppThemeColors.primaryText(context))),
                              subtitle: Text(t('biometric_unlock_subtitle'),
                                  style: TextStyle(color: AppThemeColors.secondaryText(context))),
                              value: _biometricEnabled,
                              activeColor: AppColors.cyan,
                              onChanged: (v) async {
                                await AppLockService.setBiometricEnabled(v);
                                setState(() => _biometricEnabled = v);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
