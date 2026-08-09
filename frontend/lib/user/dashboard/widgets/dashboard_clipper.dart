import 'package:flutter/material.dart';
import '../../../utils/theme_helper.dart';

class BottomNavWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height);
    path.lineTo(0, size.height * 0.3);
    path.quadraticBezierTo(
        size.width * 0.25, 0, size.width * 0.5, size.height * 0.3);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.6, size.width, size.height * 0.3);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(BottomNavWaveClipper oldClipper) => false;
}

Color getDashboardBoxColor(int index, BuildContext context) {
  if (AppThemeColors.isDark(context)) {
    return AppThemeColors.surfaceBg(context);
  }
  const colors = [
    Color(0xFFE8F5E9),
    Color(0xFFFFF8E7),
    Color(0xFFF3E5F5),
    Color(0xFFE8F5F7),
    Color(0xFFFCE4EC),
    Color(0xFFFFF3E0),
  ];
  return colors[index % colors.length];
}
