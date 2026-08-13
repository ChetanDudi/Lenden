import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'wave_widget.dart';
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
  bool glow = false,
}) {
  return Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: AppColors.tricolorGradient,
      boxShadow: glow
          ? [BoxShadow(color: Colors.amber.withValues(alpha: 0.55), blurRadius: 22, spreadRadius: 2)]
          : null,
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
      clipper: clipper ?? const MediumTopWaveClipper(),
      child: Container(
        height: height,
        color: AppThemeColors.waveSolid(context),
      ),
    ),
  );
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
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: tricolorBorder(
        radius: 22,
        margin: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 32),
              // Red gradient logout icon
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE53935), Color(0xFFFF7043)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.30),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.logout_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  t('are_you_sure_title'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  t('logout_confirm_message'),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Divider(height: 1, color: AppThemeColors.divider(ctx)),
              // Split button row
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: AppThemeColors.secondaryText(ctx),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(20),
                            ),
                          ),
                        ),
                        child: Text(
                          t('cancel'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: AppThemeColors.secondaryText(ctx),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    VerticalDivider(width: 1, color: AppThemeColors.divider(ctx)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onConfirm();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: Colors.red,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(
                              bottomRight: Radius.circular(20),
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.logout_rounded, size: 16, color: Colors.red),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                t('logout'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.red,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
  if (!context.mounted) return;
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
  if (!context.mounted) return;
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
                    ? 'Longer password with mixed characters will be stronger'
                    : score == 3
                        ? 'Getting better — try a longer or more varied password'
                        : score == 4
                            ? 'Almost there — mix in more variety to make it Strong'
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

// ════════════════════════════════════════════════════════════════════════════
// ERROR STATE
// ════════════════════════════════════════════════════════════════════════════

bool _isNetworkMessage(String msg) {
  final lower = msg.toLowerCase();
  return lower.contains('internet') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('offline') ||
      lower.contains('socket') ||
      lower.contains('unreachable');
}

/// Full-page animated error card. Auto-detects network vs server errors from [message].
/// Pass [isNetwork] to override auto-detection.
/// Pass [onRetry] = null to hide the retry button.
Widget errorStateWidget(
  BuildContext context,
  String message,
  VoidCallback? onRetry, {
  bool? isNetwork,
}) =>
    _AppErrorWidget(message: message, onRetry: onRetry, isNetwork: isNetwork);

class _AppErrorWidget extends StatefulWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool? isNetwork;
  const _AppErrorWidget({required this.message, this.onRetry, this.isNetwork});

  @override
  State<_AppErrorWidget> createState() => _AppErrorWidgetState();
}

class _AppErrorWidgetState extends State<_AppErrorWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.10)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final network = widget.isNetwork ?? _isNetworkMessage(widget.message);

    final IconData icon;
    final Color iconBg, iconColor;
    final List<Color> gradColors;
    final String title, subtitle;

    if (network) {
      icon = Icons.wifi_off_rounded;
      iconBg = const Color(0xFFFFEBEE);
      iconColor = const Color(0xFFE53935);
      gradColors = [const Color(0xFFEF5350), const Color(0xFFFF8A65)];
      title = t('no_internet_connection_title');
      subtitle = t('check_connection_and_retry_message');
    } else {
      icon = Icons.cloud_off_rounded;
      iconBg = const Color(0xFFE3F2FD);
      iconColor = const Color(0xFF1565C0);
      gradColors = [const Color(0xFF42A5F5), const Color(0xFF26C6DA)];
      title = t('oops_something_went_wrong');
      subtitle = widget.message;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: gradColors.first.withValues(alpha: 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _scale,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: iconBg,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: iconColor.withValues(alpha: 0.20),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(icon, size: 52, color: iconColor),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: iconColor,
                        letterSpacing: -0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppThemeColors.secondaryText(context),
                        height: 1.5,
                      ),
                    ),
                    if (network) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: iconColor.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            t('no_connection_label'),
                            style: TextStyle(
                              fontSize: 11,
                              color: AppThemeColors.mutedText(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: gradColors.first.withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2),
                child: ElevatedButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(t('retry'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 36, vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
