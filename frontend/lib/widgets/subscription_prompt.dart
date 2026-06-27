import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../user/digitise/subscriptions_page.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

void showSubscriptionPrompt(BuildContext context) {
  final t = AppLocalizations.of(context).t;
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return SubscriptionPrompt(
        title: t('go_premium'),
        subtitle: t('go_premium_subtitle'),
        showUseCoins: false,
      );
    },
  );
}

class SubscriptionPrompt extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool showUseCoins;

  const SubscriptionPrompt({
    Key? key,
    required this.title,
    required this.subtitle,
    this.showUseCoins = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return AlertDialog(
      backgroundColor: AppThemeColors.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: EdgeInsets.zero,
      content: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeColors.tinted(context,
                light: const Color(0xFFFCE4EC), dark: const Color(0xFF332530)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.cyan,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
              ),
              const SizedBox(height: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    child: Text(t('cancel')),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    child: Text(t('subscribe')),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SubscriptionsPage(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                    ),
                  ),
                  if (showUseCoins) ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      child: Text(t('use_coins')),
                      onPressed: () {
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
