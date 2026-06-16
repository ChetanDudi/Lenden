import 'package:flutter/material.dart';

/// Centralized color constants for the LenDen app.
/// Import this file instead of repeating inline hex literals everywhere.
class AppColors {
  AppColors._();

  // ── Brand blues ────────────────────────────────────────────────────────────
  /// Primary cyan used for headers, icons, wave backgrounds, etc.
  static const Color cyan = Color(0xFF00B4D8);

  /// Deeper blue used for table headers and accents.
  static const Color blue = Color(0xFF0077B6);

  // ── Tricolor (Indian flag) palette ─────────────────────────────────────────
  static const Color tricolorOrange = Color(0xFFFF9933);
  static const Color tricolorGreen = Color(0xFF138808);

  static const List<Color> tricolorGradientColors = [
    tricolorOrange,
    Colors.white,
    tricolorGreen,
  ];

  static const LinearGradient tricolorGradient = LinearGradient(
    colors: tricolorGradientColors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Background colors ──────────────────────────────────────────────────────
  /// Standard off-white scaffold background (cream).
  static const Color scaffoldBg = Color(0xFFFAF9F6);

  /// Alternate off-white scaffold background — prefer [scaffoldBg] for new pages.
  static const Color scaffoldBgAlt = Color(0xFFF8F6FA);

  /// Warm card background (used inside tricolor-bordered profile cards).
  static const Color warmCardBg = Color(0xFFFFF4E6);
}
