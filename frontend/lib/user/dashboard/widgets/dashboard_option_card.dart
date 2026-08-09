import 'package:flutter/material.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';

class DashboardOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String valueLabel;
  final Color iconColor;
  final Color fillColor;
  final bool showSubtitle;
  final VoidCallback onTap;

  const DashboardOptionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.iconColor,
    required this.fillColor,
    required this.showSubtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppThemeColors.cardBg(context).withValues(alpha: 0.92),
                  ),
                  child: Icon(icon, color: iconColor),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: context.sp(16),
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                  ),
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: context.sp(11),
                      color: AppThemeColors.secondaryText(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
