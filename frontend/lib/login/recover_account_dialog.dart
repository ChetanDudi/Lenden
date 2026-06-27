import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class RecoverAccountDialog extends StatelessWidget {
  final VoidCallback onRecover;

  const RecoverAccountDialog({super.key, required this.onRecover});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: contentBox(context),
    );
  }

  Widget contentBox(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Stack(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.only(
            left: 20,
            top: 65,
            right: 20,
            bottom: 20,
          ),
          margin: const EdgeInsets.only(top: 45),
          decoration: BoxDecoration(
            shape: BoxShape.rectangle,
            color: AppThemeColors.cardBg(context),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                offset: Offset(0, 10),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                t('account_deactivated'),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context)),
              ),
              const SizedBox(height: 15),
              Text(
                t('account_deactivated_message'),
                style: TextStyle(
                    fontSize: 14, color: AppThemeColors.secondaryText(context)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      t('cancel'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: onRecover,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      t('recover_and_login'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          child: CircleAvatar(
            backgroundColor: AppThemeColors.cardBg(context),
            radius: 45,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(45)),
              child: Icon(
                Icons.lock_outline,
                size: 50,
                color: AppColors.cyan,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
