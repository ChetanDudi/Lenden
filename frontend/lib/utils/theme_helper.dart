import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';

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
      isDark(context) ? Colors.grey[500]! : Colors.grey[500]!;

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

  static Color iconOnWave(BuildContext context) => Colors.white;

  /// Generic light/dark pair picker for the many hand-picked pastel "tinted
  /// surface" colors (status banners, alert dialogs, etc.) scattered across
  /// the app. Pass the existing light pastel as [light] and a dark-friendly
  /// equivalent as [dark].
  static Color tinted(BuildContext context,
          {required Color light, required Color dark}) =>
      isDark(context) ? dark : light;
}
