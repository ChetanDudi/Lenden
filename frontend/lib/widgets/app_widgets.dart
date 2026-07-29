import 'package:flutter/material.dart';
import 'app_colors.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

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
      style: TextStyle(
          color: AppThemeColors.primaryText(context),
          fontWeight: FontWeight.bold),
    ),
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
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
Widget cyanWaveHeader(BuildContext context,
    {double height = 110, CustomClipper<Path>? clipper}) {
  return Positioned(
    top: 0,
    left: 0,
    right: 0,
    child: ClipPath(
      clipper: clipper ?? _DefaultTopWaveClipper(),
      child: Container(
        height: height,
        color: AppThemeColors.waveSolid(context),
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
  final t = AppLocalizations.of(context).t;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppThemeColors.cardBg(ctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        t('logout'),
        style: TextStyle(
            fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx)),
      ),
      content: Text(
        t('logout_confirm'),
        style: TextStyle(color: AppThemeColors.secondaryText(ctx)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(t('cancel'), style: const TextStyle(color: Colors.grey)),
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
          child: Text(t('logout'), style: const TextStyle(color: Colors.white)),
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

// ════════════════════════════════════════════════════════════════════════════
// PASSWORD STRENGTH METER
// ════════════════════════════════════════════════════════════════════════════

/// Computes a 0–5 strength score for [password].
/// Score of 0 means empty or below 8 chars.
/// Score of 1–5 maps to High Risk → Weak → Fair → Good → Strong.
int passwordStrengthScore(String password) {
  if (password.length < 8) return 0;
  int score = 1; // baseline: meets minimum length
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  return score; // 1–5
}

/// Inline strength label and color for a given score (1–5).
String passwordStrengthLabel(int score) {
  switch (score) {
    case 1: return 'High Risk';
    case 2: return 'Weak';
    case 3: return 'Fair';
    case 4: return 'Good';
    case 5: return 'Strong';
    default: return '';
  }
}

Color passwordStrengthColor(int score) {
  switch (score) {
    case 1: return const Color(0xFFD32F2F);
    case 2: return const Color(0xFFE65100);
    case 3: return const Color(0xFFF59E0B);
    case 4: return const Color(0xFF0077B6);
    case 5: return const Color(0xFF22C55E);
    default: return Colors.grey;
  }
}

/// A 5-segment strength bar + label row shown below a password field.
/// Pass the current password text and it renders itself.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final score = passwordStrengthScore(password);
    final label = passwordStrengthLabel(score);
    final color = passwordStrengthColor(score);
    final isDark = AppThemeColors.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 5-segment bar
        Row(
          children: List.generate(5, (i) {
            final filled = i < score;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                height: 5,
                decoration: BoxDecoration(
                  color: filled
                      ? color
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                  color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                score <= 2
                    ? 'Add uppercase, numbers or symbols to strengthen'
                    : score == 3
                        ? 'Getting better — try adding a symbol or number'
                        : score == 4
                            ? 'Almost there — a symbol makes it Strong'
                            : 'Great password!',
                style: TextStyle(
                  fontSize: 11,
                  color: AppThemeColors.mutedText(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
