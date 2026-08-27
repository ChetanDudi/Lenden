import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/app_colors.dart';
import 'theme_helper.dart';
import 'image_crop_page.dart';

typedef PickedImage = ({XFile file, Uint8List bytes});

class ImagePickerUtils {
  static final _picker = ImagePicker();

  static Future<bool> _requestPermission(
      BuildContext context, ImageSource source) async {
    if (kIsWeb) return true;

    final permission = source == ImageSource.camera
        ? Permission.camera
        : Permission.photos;

    var status = await permission.status;
    if (status.isGranted) return true;

    // Always re-request if not yet granted — so each attempt prompts the user
    status = await permission.request();
    if (status.isGranted) return true;

    // Only if the OS has permanently blocked it do we need Settings
    if (status.isPermanentlyDenied && context.mounted) {
      final open = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppThemeColors.cardBg(ctx),
          title: Text(
            source == ImageSource.camera
                ? 'Camera Access Required'
                : 'Photo Access Required',
            style: TextStyle(color: AppThemeColors.primaryText(ctx)),
          ),
          content: Text(
            source == ImageSource.camera
                ? 'Camera access was denied. Open Settings to enable it and try again.'
                : 'Photo library access was denied. Open Settings to enable it and try again.',
            style: TextStyle(color: AppThemeColors.secondaryText(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: AppThemeColors.secondaryText(ctx))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings',
                  style: TextStyle(color: AppColors.cyan)),
            ),
          ],
        ),
      );
      if (open == true) await openAppSettings();
    }
    return false;
  }

  /// Shows camera/gallery source sheet, then picks + crops. Returns null if cancelled.
  static Future<PickedImage?> pickWithSheet(BuildContext context) async {
    final source = await _showSourceSheet(context);
    if (source == null) return null;
    return pickAndCrop(context, source: source);
  }

  static Future<ImageSource?> _showSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppThemeColors.divider(ctx),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.cyan),
              title: Text('Take Photo',
                  style:
                      TextStyle(color: AppThemeColors.primaryText(ctx))),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.cyan),
              title: Text('Choose from Gallery',
                  style:
                      TextStyle(color: AppThemeColors.primaryText(ctx))),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  /// Requests permission for [source], picks an image, opens crop UI, returns result.
  /// Returns null if the user cancels at any step or permission is denied.
  static Future<PickedImage?> pickAndCrop(
    BuildContext context, {
    required ImageSource source,
  }) async {
    if (!await _requestPermission(context, source)) return null;

    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked == null) return null;

    final pickedBytes = await picked.readAsBytes();
    if (!context.mounted) return null;

    // Open in-app crop UI (works on web + mobile without any native dependency)
    final croppedBytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageCropPage(imageBytes: pickedBytes),
      ),
    );
    if (croppedBytes == null) return null;

    return (file: XFile(picked.path, name: picked.name), bytes: croppedBytes);
  }
}
