import 'package:flutter/material.dart';
import '../utils/app_lock_service.dart';
import 'app_colors.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  String? _error;

  void _onDigit(String digit) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) {
      _verify();
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    final ok = await AppLockService.verifyPin(_pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = AppLocalizations.of(context).t('incorrect_pin');
        _pin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan,
              ),
              child: const Icon(Icons.lock_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 20),
            Text(t('enter_pin'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 8),
            Text(_error ?? t('enter_pin_subtitle'),
                style: TextStyle(
                    fontSize: 13,
                    color: _error != null
                        ? Colors.red
                        : AppThemeColors.secondaryText(context))),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.cyan : AppThemeColors.divider(context),
                  ),
                );
              }),
            ),
            const Spacer(),
            _buildKeypad(context),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];
    return SizedBox(
      width: 280,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: keys.length,
        itemBuilder: (context, index) {
          final key = keys[index];
          if (key.isEmpty) return const SizedBox.shrink();
          if (key == 'back') {
            return IconButton(
              onPressed: _onBackspace,
              icon: Icon(Icons.backspace_outlined,
                  color: AppThemeColors.primaryText(context)),
            );
          }
          return InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: () => _onDigit(key),
            child: Center(
              child: Text(key,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColors.primaryText(context))),
            ),
          );
        },
      ),
    );
  }
}
