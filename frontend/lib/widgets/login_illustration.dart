import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// Canonical single-source definition. Formerly copy-pasted identically into
// both lib/login/login_page.dart and lib/register/register_page.dart.
class LoginIllustration extends StatelessWidget {
  final double height;

  const LoginIllustration({
    Key? key,
    this.height = 220,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: LoginIllustrationPainter(),
        child: Container(),
      ),
    );
  }
}

class LoginIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Responsive base values
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    // Convenience function for scaled lengths
    double sw(double fraction) => w * fraction;
    double sh(double fraction) => h * fraction;

    // Background light circle / blob behind illustration
    final bgPaint = Paint()..color = const Color(0xFFF3F6FA);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - sh(0.05)),
        width: sw(0.9),
        height: sh(0.95),
      ),
      bgPaint,
    );

    // Large decorative circle behind phone
    final decorPaint = Paint()..color = const Color(0xFFEEF6F9);
    canvas.drawCircle(
        Offset(cx - sw(0.18), cy - sh(0.18)), sw(0.28), decorPaint);

    // Rounded rectangle "paper" behind person (like a panel)
    final panelPaint = Paint()..color = const Color(0xFFF6FBFD);
    final panelRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx + sw(0.22), cy + sh(0.05)),
            width: sw(0.52),
            height: sh(0.7)),
        Radius.circular(18));
    canvas.drawRRect(panelRect, panelPaint);

    // Subtle horizontal lines on left behind phone (to mimic lined background)
    final linePaint = Paint()..color = const Color(0xFFEFF7F8);
    for (var i = -2; i <= 3; i++) {
      final y = cy - sh(0.35) + i * sh(0.08);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - sw(0.5), y, sw(0.4), sh(0.01)),
            Radius.circular(6),
          ),
          linePaint);
    }

    // --- PHONE (left side) ---
    final phoneCenter = Offset(cx - sw(0.18), cy - sh(0.08));
    final phoneW = sw(0.22);
    final phoneH = sh(0.44);
    final phoneRadius = 14.0;

    final phoneOuterPaint = Paint()..color = const Color(0xFF2E3A49);
    final phoneOuter = RRect.fromRectAndRadius(
      Rect.fromCenter(center: phoneCenter, width: phoneW, height: phoneH),
      Radius.circular(phoneRadius),
    );
    canvas.drawRRect(phoneOuter, phoneOuterPaint);

    // Phone inner screen
    final screenInset = 6.0;
    final screenRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        phoneCenter.dx - phoneW / 2 + screenInset,
        phoneCenter.dy - phoneH / 2 + screenInset,
        phoneW - screenInset * 2,
        phoneH - screenInset * 2,
      ),
      Radius.circular(10),
    );
    final screenPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(screenRect.left, screenRect.top),
        Offset(screenRect.left, screenRect.bottom),
        [const Color(0xFFECF8FF), const Color(0xFFD9F0FF)],
      );
    canvas.drawRRect(screenRect, screenPaint);

    // Phone notch and top icons
    final notchPaint = Paint()
      ..color = const Color(0xFFEAF7FF).withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(phoneCenter.dx, phoneCenter.dy - phoneH / 2 + 20),
            width: phoneW * 0.28,
            height: 8),
        Radius.circular(6),
      ),
      notchPaint,
    );

    // Phone screen content: top shield icon
    final shieldPaint = Paint()
      ..color = const Color(0xFF2B8BC6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final shieldCenter = Offset(phoneCenter.dx, phoneCenter.dy - phoneH * 0.18);
    canvas.drawCircle(shieldCenter, sw(0.02), shieldPaint);
    // small check mark inside
    final tickPath = Path();
    tickPath.moveTo(shieldCenter.dx - sw(0.01), shieldCenter.dy);
    tickPath.lineTo(shieldCenter.dx - sw(0.002), shieldCenter.dy + sh(0.01));
    tickPath.lineTo(shieldCenter.dx + sw(0.013), shieldCenter.dy - sh(0.008));
    final tickPaint = Paint()
      ..color = const Color(0xFF2B8BC6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(tickPath, tickPaint);

    // Login fields on phone
    final fieldPaint = Paint()..color = Colors.white;
    final fieldRadius = 8.0;
    double yStart = phoneCenter.dy - phoneH * 0.07;
    for (int i = 0; i < 3; i++) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          phoneCenter.dx - phoneW * 0.34 / 2 + screenInset + 6,
          yStart + i * sh(0.06),
          phoneW * 0.34,
          sh(0.04),
        ),
        Radius.circular(fieldRadius),
      );
      // slight inner shadow effect
      canvas.drawRRect(r, fieldPaint);
      final stroke = Paint()
        ..color = const Color(0xFFE2F0F6)
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(r, stroke);

      // small icon at left of field
      final iconCenter = Offset(r.left + 12, r.center.dy);
      canvas.drawCircle(
          iconCenter, 6, Paint()..color = const Color(0xFFB6DCEB));
    }

    // Phone small "sign in" button
    final btnRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(phoneCenter.dx - phoneW * 0.14,
          phoneCenter.dy + phoneH * 0.12, phoneW * 0.28, sh(0.05)),
      Radius.circular(10),
    );
    final btnPaint = Paint()
      ..shader = ui.Gradient.linear(
        // Replace invalid getters with manually computed points
        Offset(btnRect.left, (btnRect.top + btnRect.bottom) / 2),
        Offset(btnRect.right, (btnRect.top + btnRect.bottom) / 2),
        [
          const Color(0xFF386FA4),
          const Color(0xFF2B7DB8),
        ],
      );

// Draw the rounded rectangle button
    canvas.drawRRect(btnRect, btnPaint);

    // Phone tiny speaker & camera dots
    canvas.drawCircle(
        Offset(phoneCenter.dx + phoneW * 0.26 / 2,
            phoneCenter.dy - phoneH / 2 + 8),
        2,
        Paint()..color = const Color(0xFF1C2A32));
    canvas.drawCircle(
        Offset(phoneCenter.dx - phoneW * 0.26 / 2,
            phoneCenter.dy - phoneH / 2 + 8),
        2,
        Paint()..color = const Color(0xFF1C2A32));

    // --- PLANT (left bottom) ---
    final plantBase = Offset(cx - sw(0.36), cy + sh(0.24));
    final potPaint = Paint()..color = const Color(0xFFD9EDF5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: plantBase, width: sw(0.12), height: sh(0.06)),
          Radius.circular(8)),
      potPaint,
    );

    final leafPaint = Paint()..color = const Color(0xFF6ABF9B);
    // 3 leaves
    for (int i = 0; i < 3; i++) {
      final path = Path();
      final lx = plantBase.dx - 6 + i * 10.0;
      final ly = plantBase.dy - sh(0.02) - i * 6;
      path.moveTo(lx, ly);
      path.quadraticBezierTo(lx - 12, ly - 20, lx + 4, ly - 34 - i * 4);
      path.quadraticBezierTo(lx + 16, ly - 20, lx + 4, ly - 8);
      path.close();
      canvas.drawPath(path, leafPaint);
    }

    // --- ENVELOPE (top-right) ---
    final envCenter = Offset(cx + sw(0.38), cy - sh(0.26));
    final envW = sw(0.14);
    final envH = sh(0.08);
    final envRect =
        Rect.fromCenter(center: envCenter, width: envW, height: envH);
    final envPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
        RRect.fromRectAndRadius(envRect, Radius.circular(8)), envPaint);
    // flap lines
    final flap = Path();
    flap.moveTo(envRect.left + 8, envRect.top + 8);
    flap.lineTo(envRect.center.dx, envRect.bottom - 6);
    flap.lineTo(envRect.right - 8, envRect.top + 8);
    final flapPaint = Paint()
      ..color = const Color(0xFFDFEAF0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(flap, flapPaint);

    // small mail shadow
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            envRect.shift(Offset(3, 4)), Radius.circular(8)),
        Paint()..color = const Color(0xFFD7E6EA));

    // --- PERSON (right side, seated) ---
    // Shadow under person
    final groundShadow = Paint()..color = Colors.black.withValues(alpha: 0.08);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx + sw(0.2), cy + sh(0.30)),
            width: sw(0.28),
            height: sh(0.05)),
        groundShadow);

    // Pants (deep navy)
    final pantsPaint = Paint()..color = const Color(0xFF2C3E50);
    final pantsPath = Path();
    final px = cx + sw(0.18);
    final py = cy + sh(0.04);
    pantsPath.moveTo(px - sw(0.06), py + sh(0.05));
    pantsPath.quadraticBezierTo(
        px - sw(0.09), py + sh(0.15), px - sw(0.02), py + sh(0.20));
    pantsPath.lineTo(px + sw(0.08), py + sh(0.20));
    pantsPath.quadraticBezierTo(
        px + sw(0.12), py + sh(0.13), px + sw(0.06), py + sh(0.05));
    pantsPath.close();
    canvas.drawPath(pantsPath, pantsPaint);

    // Shoes
    final shoePaint = Paint()..color = const Color(0xFF172829);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(px - sw(0.03), py + sh(0.22)),
                width: sw(0.09),
                height: sh(0.03)),
            Radius.circular(6)),
        shoePaint);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(px + sw(0.06), py + sh(0.22)),
                width: sw(0.09),
                height: sh(0.03)),
            Radius.circular(6)),
        shoePaint);

    // Torso (shirt) with subtle gradient
    final torsoRect = Rect.fromCenter(
        center: Offset(px + sw(0.02), py - sh(0.02)),
        width: sw(0.22),
        height: sh(0.18));
    final torsoPaint = Paint()
      ..shader = ui.Gradient.linear(torsoRect.topLeft, torsoRect.bottomRight,
          [const Color(0xFFFFB07A), const Color(0xFFFF7A3F)]);
    canvas.drawRRect(
        RRect.fromRectAndRadius(torsoRect, Radius.circular(12)), torsoPaint);

    // Neck & head (skin tone)
    final neckRect = Rect.fromCenter(
        center: Offset(px - sw(0.02), py - sh(0.12)),
        width: sw(0.07),
        height: sh(0.06));
    final skinPaint = Paint()..color = const Color(0xFFFFDAB3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(neckRect, Radius.circular(6)), skinPaint);

    // Head
    final headCenter = Offset(px - sw(0.02), py - sh(0.20));
    final headRadius = sw(0.085);
    // head shading radial
    final headPaint = Paint()
      ..shader = ui.Gradient.radial(headCenter, headRadius,
          [const Color(0xFFFFE6CC), const Color(0xFFFFD4A8)]);
    canvas.drawCircle(headCenter, headRadius, headPaint);

    // Hair (dark)
    final hairPaint = Paint()..color = const Color(0xFF2E1E1A);
    final hairPath = Path();
    hairPath.moveTo(
        headCenter.dx - headRadius * 0.9, headCenter.dy - headRadius * 0.25);
    hairPath.quadraticBezierTo(headCenter.dx, headCenter.dy - headRadius * 1.05,
        headCenter.dx + headRadius * 0.9, headCenter.dy - headRadius * 0.25);
    hairPath.arcToPoint(
        Offset(headCenter.dx - headRadius * 0.9,
            headCenter.dy - headRadius * 0.25),
        radius: Radius.circular(headRadius),
        clockwise: false);
    hairPath.close();
    canvas.drawPath(hairPath, hairPaint);

    // Eyes
    final eyeWhite = Paint()..color = Colors.white;
    final eyeIris = Paint()..color = const Color(0xFF2F7D8E);
    final eyePupil = Paint()..color = Colors.black;
    final eyeYOffset = sh(0.012);
    canvas.drawOval(
        Rect.fromCenter(
            center:
                Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
            width: sw(0.04),
            height: sh(0.02)),
        eyeWhite);
    canvas.drawOval(
        Rect.fromCenter(
            center:
                Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
            width: sw(0.04),
            height: sh(0.02)),
        eyeWhite);
    canvas.drawCircle(
        Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.01),
        eyeIris);
    canvas.drawCircle(
        Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.01),
        eyeIris);
    canvas.drawCircle(
        Offset(headCenter.dx - sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.005),
        eyePupil);
    canvas.drawCircle(
        Offset(headCenter.dx + sw(0.03), headCenter.dy - eyeYOffset),
        sw(0.005),
        eyePupil);

    // Smile
    final smilePaint = Paint()
      ..color = const Color(0xFFB84A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final smile = Path();
    smile.moveTo(headCenter.dx - sw(0.035), headCenter.dy + sh(0.01));
    smile.quadraticBezierTo(headCenter.dx, headCenter.dy + sh(0.03),
        headCenter.dx + sw(0.035), headCenter.dy + sh(0.01));
    canvas.drawPath(smile, smilePaint);

    // Cheeks (blush)
    final blush = Paint()..color = const Color(0xFFFFB3BA).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(headCenter.dx - sw(0.06), headCenter.dy + sh(0.0)),
        sw(0.015), blush);
    canvas.drawCircle(Offset(headCenter.dx + sw(0.06), headCenter.dy + sh(0.0)),
        sw(0.015), blush);

    // Left arm (reaching to phone) - sleeve uses same gradient as torso
    final leftArm = Path();
    leftArm.moveTo(px - sw(0.02), py - sh(0.03));
    leftArm.quadraticBezierTo(
        px - sw(0.12), py - sh(0.08), px - sw(0.18), py - sh(0.14));
    leftArm.quadraticBezierTo(
        px - sw(0.16), py - sh(0.10), px - sw(0.08), py - sh(0.02));
    leftArm.close();
    canvas.drawPath(leftArm, torsoPaint);

    // Left hand (holding phone) - small circle for hand skin tone
    final leftHandCenter = Offset(px - sw(0.18), py - sh(0.14));
    canvas.drawCircle(leftHandCenter, sw(0.025), skinPaint);

    // Right arm (resting)
    final rightArm = Path();
    rightArm.moveTo(px + sw(0.06), py - sh(0.0));
    rightArm.quadraticBezierTo(
        px + sw(0.14), py + sh(0.03), px + sw(0.18), py + sh(0.06));
    rightArm.quadraticBezierTo(
        px + sw(0.14), py + sh(0.05), px + sw(0.06), py - sh(0.0));
    rightArm.close();
    canvas.drawPath(rightArm, torsoPaint);

    // Small book / paper near person (to match image)
    final paperRect = Rect.fromCenter(
        center: Offset(px + sw(0.28), py + sh(0.02)),
        width: sw(0.12),
        height: sh(0.07));
    canvas.drawRRect(RRect.fromRectAndRadius(paperRect, Radius.circular(6)),
        Paint()..color = const Color(0xFFF6F9FB));
    canvas.drawRect(
        paperRect.deflate(6), Paint()..color = const Color(0xFFEFF6F8));

    // dotted lines on paper
    for (int i = 0; i < 3; i++) {
      final dy = paperRect.top + 10 + i * 14;
      canvas.drawLine(
          Offset(paperRect.left + 8, dy),
          Offset(paperRect.right - 8, dy),
          Paint()
            ..color = const Color(0xFFE1EEF2)
            ..strokeWidth = 1);
    }

    // small envelope shadow near top-right (already drawn)
    // Add more subtle details on phone: small list bullets
    final bulletPaint = Paint()..color = const Color(0xFF5BA8D6);
    for (int i = 0; i < 3; i++) {
      final yy = phoneCenter.dy - phoneH * 0.02 + i * sh(0.06);
      canvas.drawCircle(
          Offset(phoneCenter.dx - phoneW * 0.14 + 18, yy), 4, bulletPaint);
    }

    // Overall tiny accents: rounded rectangle at bottom "Sign In" under whole illustration (mimic page CTA)
    final bottomBtn = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(cx, cy + sh(0.38)),
            width: sw(0.36),
            height: sh(0.07)),
        Radius.circular(24));
    final bottomBtnPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(bottomBtn.left, (bottomBtn.top + bottomBtn.bottom) / 2),
        Offset(bottomBtn.right, (bottomBtn.top + bottomBtn.bottom) / 2),
        [
          const Color(0xFF1D6D9F),
          const Color(0xFF154F78),
        ],
      );

    canvas.drawRRect(bottomBtn, bottomBtnPaint);

    // button text stroke (simple line to indicate)
    canvas.drawLine(
        Offset(bottomBtn.left + 24, bottomBtn.center.dy),
        Offset(bottomBtn.right - 24, bottomBtn.center.dy),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.06)
          ..strokeWidth = 12);

    // final small signature lines (mimic text under 'Login' heading)
    final titleY = cy - sh(0.4);
    canvas.drawRect(Rect.fromLTWH(cx - sw(0.35), titleY, sw(0.26), sh(0.02)),
        Paint()..color = const Color(0xFF2C3E50));
    canvas.drawRect(
        Rect.fromLTWH(cx - sw(0.35), titleY + sh(0.03), sw(0.18), sh(0.015)),
        Paint()..color = const Color(0xFF9FB9C8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
