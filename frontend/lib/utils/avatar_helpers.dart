import 'package:flutter/material.dart';

const List<Color> _kAvatarColors = [
  Color(0xFF0077B6), Color(0xFF2E7D32), Color(0xFF6A1B9A),
  Color(0xFFD32F2F), Color(0xFF00838F), Color(0xFFE65100),
  Color(0xFF1565C0), Color(0xFF558B2F),
];

Color avatarColor(String name) {
  if (name.isEmpty) return _kAvatarColors[0];
  return _kAvatarColors[name.codeUnitAt(0) % _kAvatarColors.length];
}

String initials(String name, [String secondary = '']) {
  final n = name.trim();
  if (n.isNotEmpty) {
    final parts = n.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return n[0].toUpperCase();
  }
  if (secondary.trim().isNotEmpty) return secondary.trim()[0].toUpperCase();
  return '?';
}
