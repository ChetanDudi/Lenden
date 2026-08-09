import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class LandingNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  const LandingNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.black87 : Colors.grey.shade500;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.sw(6)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: context.sp(22)),
            SizedBox(height: context.sh(3)),
            Text(
              label,
              style: TextStyle(
                fontSize: context.sp(10),
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            SizedBox(height: context.sh(3)),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: active ? Colors.black87 : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
