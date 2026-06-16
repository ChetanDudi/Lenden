import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════════════════
// WAVE CLIPPERS
// Canonical single-source definitions for the S-wave clippers used on every
// page header.  Import this file (or lib/widgets/wave_widget.dart which
// re-exports both) instead of defining a local copy in each page file.
// ════════════════════════════════════════════════════════════════════════════

/// The standard S-wave clipper used on all page headers (cyan background behind
/// transparent AppBar).  Formerly copy-pasted into 47 files under names like
/// `TopWaveClipper`, `_TopWaveClipper`, `_WaveClipper`, `_HelpWaveClipper`, etc.
class TopWaveClipper extends CustomClipper<Path> {
  const TopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// Bottom mirror of [TopWaveClipper] — used on login/register/forgot-password
/// pages and some group-transaction dialogs.
class BottomWaveClipper extends CustomClipper<Path> {
  const BottomWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.2);
    final firstControlPoint = Offset(size.width / 4, 0);
    final firstEndPoint = Offset(size.width / 2, size.height * 0.2);
    path.quadraticBezierTo(firstControlPoint.dx, firstControlPoint.dy,
        firstEndPoint.dx, firstEndPoint.dy);
    final secondControlPoint =
        Offset(size.width - (size.width / 4), size.height * 0.4);
    final secondEndPoint = Offset(size.width, size.height * 0.2);
    path.quadraticBezierTo(secondControlPoint.dx, secondControlPoint.dy,
        secondEndPoint.dx, secondEndPoint.dy);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
