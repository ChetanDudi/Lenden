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

/// A deeper variant of [TopWaveClipper] (dips to full height instead of half) —
/// used on pages with a back-arrow + title row that needs to sit fully on the
/// wave. Formerly copy-pasted into 8 files as a second local `TopWaveClipper`.
class DeepTopWaveClipper extends CustomClipper<Path> {
  const DeepTopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.7,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.4,
      size.width,
      size.height * 0.7,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// An even deeper variant of [TopWaveClipper] (dips to full height, baseline
/// at 0.8 instead of 0.7) — used on the secure/group transaction creation
/// pages. Formerly copy-pasted into 2 files as a second local `TopWaveClipper`.
class DeeperTopWaveClipper extends CustomClipper<Path> {
  const DeeperTopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.8);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height * 0.8,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.6,
      size.width,
      size.height * 0.8,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// A medium-depth variant of [TopWaveClipper] (baseline at 0.35 instead of
/// 0.4) — used on the subscriptions/gift-card pages. Formerly copy-pasted
/// into 3 files as a second local `TopWaveClipper`.
class MediumTopWaveClipper extends CustomClipper<Path> {
  const MediumTopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.35);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.5,
        size.width * 0.5, size.height * 0.35);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.2, size.width, size.height * 0.35);
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

/// A 0.75x-scaled variant of [DeepTopWaveClipper] — used on the login/register
/// pages where the wave is shorter. Formerly copy-pasted into 2 files as a
/// second local `TopWaveClipper`.
class ScaledDeepTopWaveClipper extends CustomClipper<Path> {
  const ScaledDeepTopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.525);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.75,
      size.width * 0.5,
      size.height * 0.525,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.525,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// An alternate bottom wave shape (starts at the top corners, dips down to a
/// shallow double-curve) — used on login/register/forgot-password pages and
/// some group-transaction dialogs as a second local `BottomWaveClipper`,
/// distinct from the curve in [BottomWaveClipper] above.
class AltBottomWaveClipper extends CustomClipper<Path> {
  const AltBottomWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.6,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.75, 0, size.width, size.height * 0.4);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

/// A cubic-bezier variant used on the Feedback, Help & Support, and
/// Edit Profile pages — produces a more aggressive asymmetric S-curve than
/// the quadratic [TopWaveClipper].
class CubicTopWaveClipper extends CustomClipper<Path> {
  const CubicTopWaveClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.75);
    path.cubicTo(
      size.width * 0.25, size.height * 1.05,
      size.width * 0.75, size.height * 0.45,
      size.width, size.height * 0.75,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
