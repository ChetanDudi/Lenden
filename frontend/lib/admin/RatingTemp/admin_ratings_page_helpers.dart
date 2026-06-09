import 'package:flutter/material.dart';

// Icon mapping for user fields
IconData getIconForField(String field) {
  switch (field) {
    case 'Name':
      return Icons.person;
    case 'Email':
      return Icons.email;
    case 'Username':
      return Icons.account_circle;
    case 'Gender':
      return Icons.wc;
    case 'Birthday':
      return Icons.cake;
    case 'Phone':
      return Icons.phone;
    case 'Address':
      return Icons.home;
    case 'Alt Email':
      return Icons.alternate_email;
    case 'Member Since':
      return Icons.calendar_today;
    case 'Average Rating':
      return Icons.star;
    case 'Role':
      return Icons.verified_user;
    case 'Is Active':
      return Icons.check_circle;
    case 'Is Verified':
      return Icons.verified;
    default:
      return Icons.info_outline;
  }
}

// Top wave clipper for stylish dialog background
class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 20);
    path.quadraticBezierTo(
        size.width / 2, size.height, size.width, size.height - 20);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

// Bottom wave clipper for stylish dialog background
class BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.moveTo(0, 20);
    path.quadraticBezierTo(size.width / 2, 0, size.width, 20);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
