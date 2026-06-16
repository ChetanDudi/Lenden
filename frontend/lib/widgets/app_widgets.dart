import 'package:flutter/material.dart';
import 'app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
// TRICOLOR BORDER
// ════════════════════════════════════════════════════════════════════════════

/// Wraps [child] with a 2 px Indian-flag (orange / white / green) gradient
/// border.  Replaces every local `_tricolorBorder()` / `_tricolorBorderBox()`
/// helper defined across ~27 files.
///
/// Usage:
/// ```dart
/// tricolorBorder(child: myWidget)
/// tricolorBorder(child: myWidget, radius: 50, margin: EdgeInsets.zero)
/// ```
Widget tricolorBorder({
  required Widget child,
  double radius = 16,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry padding = const EdgeInsets.all(2),
}) {
  return Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: AppColors.tricolorGradient,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular((radius - 2).clamp(0, double.infinity)),
      child: child,
    ),
  );
}

/// Circular tricolor border specifically for avatars.
/// [radius] is the avatar radius (not the border radius).
Widget tricolorCircleAvatar({
  required Widget child,
  double avatarRadius = 30,
  double borderWidth = 3,
}) {
  return Container(
    padding: EdgeInsets.all(borderWidth),
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: AppColors.tricolorGradient,
    ),
    child: CircleAvatar(
      radius: avatarRadius,
      backgroundColor: AppColors.cyan,
      child: child,
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SECTION LABEL
// ════════════════════════════════════════════════════════════════════════════

/// Small grey semibold section-header label.
/// Replaces every local `_sectionLabel()` helper in settings, export, etc.
///
/// Usage:
/// ```dart
/// AppWidgets.sectionLabel('Account')
/// ```
Widget sectionLabel(String text, {EdgeInsetsGeometry padding = const EdgeInsets.only(left: 4)}) {
  return Padding(
    padding: padding,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.4,
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// LOADING OVERLAY
// ════════════════════════════════════════════════════════════════════════════

/// Semi-transparent black overlay with a centered [CircularProgressIndicator].
/// Place as the last child of a [Stack] and show only when loading:
///
/// ```dart
/// Stack(children: [
///   myPageContent,
///   if (_isLoading) loadingOverlay(),
/// ])
/// ```
Widget loadingOverlay({Color color = const Color(0x26000000)}) {
  return Container(
    color: color,
    child: const Center(child: CircularProgressIndicator()),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// TRANSPARENT APP BAR
// ════════════════════════════════════════════════════════════════════════════

/// A transparent [AppBar] with a black title and a black back-arrow leading
/// button.  Replaces the repeated transparent-AppBar pattern in 33+ files.
///
/// Usage:
/// ```dart
/// appBar: transparentAppBar(context, title: 'Settings')
/// ```
AppBar transparentAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
  VoidCallback? onBack,
}) {
  return AppBar(
    title: Text(
      title,
      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
    ),
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back, color: Colors.black),
      onPressed: onBack ?? () => Navigator.pop(context),
    ),
    actions: actions,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// CYAN WAVE HEADER (Positioned inside a Stack behind extendBodyBehindAppBar)
// ════════════════════════════════════════════════════════════════════════════

/// Returns the cyan S-wave header that sits behind a transparent AppBar.
/// Use inside a [Stack] when [Scaffold.extendBodyBehindAppBar] is true.
///
/// ```dart
/// body: Stack(children: [
///   cyanWaveHeader(height: 110),
///   SafeArea(child: myContent),
///   if (_isLoading) loadingOverlay(),
/// ])
/// ```
Widget cyanWaveHeader({double height = 110, CustomClipper<Path>? clipper}) {
  return Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: ClipPath(
      clipper: clipper ?? _DefaultTopWaveClipper(),
      child: Container(
        height: height,
        color: AppColors.cyan,
      ),
    ),
  );
}

class _DefaultTopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.35);
    path.quadraticBezierTo(
      size.width * 0.25, size.height * 0.5,
      size.width * 0.5, size.height * 0.35,
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.2,
      size.width, size.height * 0.35,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// ════════════════════════════════════════════════════════════════════════════
// LOGOUT DIALOG
// ════════════════════════════════════════════════════════════════════════════

/// Shows the standard "Are you sure you want to logout?" confirmation dialog.
/// [onConfirm] is called only if the user taps the red Logout button.
///
/// Replaces `_showLogoutDialog()` / `_confirmLogout()` in settings pages and
/// dashboards.
///
/// Usage:
/// ```dart
/// showLogoutDialog(context, onConfirm: () {
///   session.logout();
///   Navigator.of(context).pushReplacementNamed('/');
/// });
/// ```
void showLogoutDialog(BuildContext context, {required VoidCallback onConfirm}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Logout',
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
      content: const Text(
        'Are you sure you want to logout?',
        style: TextStyle(color: Colors.black87),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onConfirm();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// SNACKBAR HELPER
// ════════════════════════════════════════════════════════════════════════════

/// Shows a floating, rounded snackbar.
/// [isError] → red background; otherwise green.
///
/// Replaces `_showSnack()` in 13+ files.
///
/// Usage:
/// ```dart
/// showSnack(context, 'Saved!');
/// showSnack(context, 'Something went wrong', isError: true);
/// ```
void showSnack(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  if (!Navigator.of(context).mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(12),
    ),
  );
}

/// Tricolor-gradient styled floating snackbar (used in admin digitise pages).
/// Replaces the duplicate `showStylishSnackBar` free functions.
void showStylishSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          gradient: AppColors.tricolorGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isError ? Colors.red.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.check_circle_outline,
                color: isError ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError ? Colors.red.shade800 : Colors.green.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
    ),
  );
}
