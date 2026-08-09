import 'package:flutter/material.dart';

class GoogleMenuIcon extends StatelessWidget {
  const GoogleMenuIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 3),
        ColoredBar(color: Color(0xFF4285F4)),
        SizedBox(height: 4),
        ColoredBar(color: Color(0xFFDB4437)),
        SizedBox(height: 4),
        ColoredBar(color: Color(0xFFF4B400)),
      ],
    );
  }
}

class ColoredBar extends StatelessWidget {
  final Color color;
  const ColoredBar({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      width: 24,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
