import 'package:flutter/material.dart';

/// Responsive sizing helpers.
///
/// Usage inside a build method:
///   Text('Hello', style: TextStyle(fontSize: context.sp(16)))
///   SizedBox(height: context.sh(24))
///   Container(width: context.sw(120))
extension ResponsiveContext on BuildContext {
  Size get _screen => MediaQuery.sizeOf(this);

  /// Scales a font size relative to a 375-pt reference width (iPhone SE / typical small phone).
  /// Clamped so text never gets tiny on small screens or huge on large ones.
  double sp(double size) {
    final scale = (_screen.width / 375).clamp(0.8, 1.4);
    return size * scale;
  }

  /// Scales a horizontal dimension.
  double sw(double size) {
    final scale = (_screen.width / 375).clamp(0.75, 1.5);
    return size * scale;
  }

  /// Scales a vertical dimension.
  double sh(double size) {
    final scale = (_screen.height / 812).clamp(0.75, 1.4);
    return size * scale;
  }

  /// True when the screen is narrower than 360 pt (very small phones).
  bool get isSmallScreen => _screen.width < 360;

  /// Adaptive horizontal padding: tighter on small screens.
  double get hPadding => isSmallScreen ? 12.0 : 20.0;

  /// Adaptive vertical padding.
  double get vPadding => isSmallScreen ? 16.0 : 24.0;
}
