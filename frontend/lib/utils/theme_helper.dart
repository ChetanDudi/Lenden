import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';

/// Stylish character counter for description/note fields (limit 300).
/// Pass into TextField's buildCounter parameter — ctx is the BuildContext
/// provided by the callback so colors adapt to the current theme.
Widget? buildDescCounter(BuildContext ctx, int currentLength, int? maxLength) {
  final limit = maxLength ?? 300;
  if (currentLength == 0) return null;
  final isAtLimit = currentLength >= limit;
  final isNear = currentLength >= limit - 30;
  final isDark = Theme.of(ctx).brightness == Brightness.dark;
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (isAtLimit)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(Icons.warning_amber_rounded, size: 12,
              color: isDark ? Colors.red.shade400 : Colors.red.shade600),
        ),
      Text(
        '$currentLength / $limit',
        style: TextStyle(
          fontSize: 11,
          fontWeight: isAtLimit ? FontWeight.w700 : FontWeight.w500,
          color: isAtLimit
              ? (isDark ? Colors.red.shade400 : Colors.red.shade600)
              : isNear
                  ? (isDark ? Colors.orange.shade400 : Colors.orange.shade700)
                  : (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
        ),
      ),
    ]),
  );
}

/// Central dark-mode color lookup. Every screen should read colors through
/// these helpers (instead of hardcoding hex literals) so toggling the app's
/// theme actually changes how the screen looks.
class AppThemeColors {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Scaffold/page background.
  static Color scaffoldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF121212) : const Color(0xFFF8F6FA);

  /// Card/sheet/dialog surface background.
  static Color cardBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E1E1E) : Colors.white;

  /// Slightly raised surface (e.g. inner containers on top of a card).
  static Color surfaceBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF2A2A2A) : const Color(0xFFF7FBFD);

  static Color primaryText(BuildContext context) =>
      isDark(context) ? Colors.white : Colors.black87;

  static Color secondaryText(BuildContext context) =>
      isDark(context) ? Colors.grey[400]! : Colors.grey[600]!;

  static Color mutedText(BuildContext context) =>
      isDark(context) ? Colors.grey[400]! : Colors.grey[500]!;

  static Color border(BuildContext context) =>
      isDark(context) ? Colors.white24 : const Color(0xFFBFE8F2);

  static Color divider(BuildContext context) =>
      isDark(context) ? Colors.white12 : Colors.grey.shade300;

  /// Top wave / header gradient colors.
  static List<Color> waveGradient(BuildContext context) => isDark(context)
      ? [const Color(0xFF023047), const Color(0xFF011627)]
      : [AppColors.cyan, const Color(0xFF48CAE4)];

  static Color waveSolid(BuildContext context) =>
      isDark(context) ? const Color(0xFF023047) : AppColors.cyan;

  /// Warm card background used in home / summary cards.
  static Color warmCardBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A1A2E) : const Color(0xFFFFF8F0);

  /// Blue accent — use instead of the light-only [AppColors.blue].
  static Color blue(BuildContext context) =>
      isDark(context) ? const Color(0xFF64B5F6) : const Color(0xFF1976D2);

  /// Generic light/dark pair picker for the many hand-picked pastel "tinted
  /// surface" colors (status banners, alert dialogs, etc.) scattered across
  /// the app. Pass the existing light pastel as [light] and a dark-friendly
  /// equivalent as [dark].
  static Color tinted(BuildContext context,
          {required Color light, required Color dark}) =>
      isDark(context) ? dark : light;
}
