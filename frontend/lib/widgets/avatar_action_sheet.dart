import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_helper.dart';

/// Full-screen, pinch-zoomable preview of a profile picture with a close button.
Future<void> showProfilePicturePreview(
  BuildContext context,
  ImageProvider imageProvider,
) {
  final t = AppLocalizations.of(context).t;
  return showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.topRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: InteractiveViewer(
              child: Image(image: imageProvider, fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: t('close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Bottom sheet shown when tapping a dashboard avatar: choose between viewing
/// the full profile/details page, or just previewing the profile picture.
Future<void> showAvatarActionSheet(
  BuildContext context, {
  required ImageProvider avatarImage,
  required VoidCallback onViewDetails,
}) {
  final t = AppLocalizations.of(context).t;
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppThemeColors.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColors.divider(sheetContext),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.person_outline,
                  color: AppThemeColors.primaryText(sheetContext)),
              title: Text(t('view_details'),
                  style:
                      TextStyle(color: AppThemeColors.primaryText(sheetContext))),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onViewDetails();
              },
            ),
            ListTile(
              leading: Icon(Icons.image_outlined,
                  color: AppThemeColors.primaryText(sheetContext)),
              title: Text(t('view_profile_picture_label'),
                  style:
                      TextStyle(color: AppThemeColors.primaryText(sheetContext))),
              onTap: () {
                Navigator.of(sheetContext).pop();
                showProfilePicturePreview(context, avatarImage);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
