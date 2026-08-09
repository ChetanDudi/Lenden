import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../session.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/responsive.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class DashboardGreetingCard extends StatelessWidget {
  final String greetingSubtitle;
  final int dailyTip;
  final double? netLent;
  final double? netBorrowed;

  const DashboardGreetingCard({
    super.key,
    required this.greetingSubtitle,
    required this.dailyTip,
    this.netLent,
    this.netBorrowed,
  });

  static const _tips = [
    '💡 Track every expense — small ones add up fast.',
    '📊 Review your budget weekly to stay on track.',
    '🎯 Setting a savings goal makes spending intentional.',
    '🔁 Automate savings before you spend.',
    '📉 Cutting one subscription can save ₹1,000+/year.',
    '🧾 Split group expenses fairly — use LenDen Groups.',
    '⚡ Quick transactions under ₹500 drain budgets silently.',
    '📅 End-of-month reviews reveal your biggest leaks.',
    '🏆 A 3-month budget streak builds lasting habits.',
    '💸 Pay yourself first — save before you splurge.',
    '🔍 Audit your subscriptions every 3 months.',
    '📆 Plan big purchases a month ahead.',
  ];

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context, listen: false);
    final name = (session.user?['name'] as String? ?? '').split(' ').first;
    final hour = DateTime.now().hour;
    final (greeting, emoji) = hour >= 5 && hour < 12
        ? ('Good Morning', '🌅')
        : hour >= 12 && hour < 17
            ? ('Good Afternoon', '☀️')
            : hour >= 17 && hour < 21
                ? ('Good Evening', '🌇')
                : ('Good Night', '🌙');
    final tip = _tips[dailyTip % _tips.length];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.cyan.withValues(alpha: 0.15),
              Colors.deepPurple.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? '$greeting, $name!' : greeting,
                        style: TextStyle(
                          fontSize: context.sp(16),
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      Text(
                        greetingSubtitle,
                        style: TextStyle(
                          fontSize: context.sp(11),
                          color: AppThemeColors.secondaryText(context),
                        ),
                      ),
                      if (netLent != null) ...[
                        const SizedBox(height: 4),
                        Builder(builder: (ctx) {
                          final net = (netLent ?? 0) - (netBorrowed ?? 0);
                          final isPositive = net >= 0;
                          final color = isPositive
                              ? Colors.green.shade600
                              : Colors.red.shade600;
                          final key = isPositive
                              ? 'net_positive_label'
                              : 'net_negative_label';
                          final label = AppLocalizations.of(ctx)
                              .t(key)
                              .replaceAll('{amount}', net.abs().toStringAsFixed(0));
                          return Text(
                            label,
                            style: TextStyle(
                              fontSize: context.sp(11),
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tip,
                style: TextStyle(
                  fontSize: context.sp(11),
                  color: AppThemeColors.primaryText(context),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
