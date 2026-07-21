import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class MaintenanceScreen extends StatelessWidget {
  final VoidCallback onRetry;
  const MaintenanceScreen({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.build_circle_outlined,
                  size: 80, color: AppColors.cyan.withValues(alpha: 0.7)),
              const SizedBox(height: 24),
              Text(
                t('maintenance_title'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                t('maintenance_message'),
                style: TextStyle(
                  fontSize: 15,
                  color: AppThemeColors.secondaryText(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: Text(t('retry'),
                    style: const TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.cyan,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
