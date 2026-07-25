import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import 'app_colors.dart';

class CalendarHeatmap extends StatelessWidget {
  final Map<String, dynamic> dailySpending;
  final String Function(num?) formatAmount;

  const CalendarHeatmap({
    super.key,
    required this.dailySpending,
    required this.formatAmount,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    if (dailySpending.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(loc.t('no_heatmap_data'),
              style: TextStyle(color: AppThemeColors.secondaryText(context))),
        ),
      );
    }

    final amounts = dailySpending.values.map((v) => (v as num).toDouble()).toList();
    final maxAmt  = amounts.reduce((a, b) => a > b ? a : b);

    // Build the last 13 weeks (91 days) grid
    final today = DateTime.now();
    final days  = List.generate(91, (i) => today.subtract(Duration(days: 90 - i)));

    // Group by week (columns)
    final weeks = <List<DateTime>>[];
    var week = <DateTime>[];
    for (final d in days) {
      week.add(d);
      if (d.weekday == DateTime.sunday || d == days.last) {
        weeks.add(week);
        week = [];
      }
    }

    final monthFmt = DateFormat('MMM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month labels
        Row(
          children: [
            const SizedBox(width: 24),
            ...weeks.map((w) {
              final first = w.first;
              final showLabel = first.day <= 7;
              return SizedBox(
                width: 14,
                child: showLabel
                    ? Text(monthFmt.format(first),
                        style: TextStyle(fontSize: 9, color: AppThemeColors.secondaryText(context)))
                    : const SizedBox(),
              );
            }),
          ],
        ),
        const SizedBox(height: 4),
        // Day rows (Mon–Sun) + week columns
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day labels
            Column(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) => SizedBox(
                height: 14,
                child: Text(d, style: TextStyle(fontSize: 9, color: AppThemeColors.secondaryText(context))),
              )).toList(),
            ),
            const SizedBox(width: 4),
            // Weeks
            ...weeks.map((w) {
              // Pad week to start on Monday
              final cells = <DateTime?>[];
              if (w.isNotEmpty) {
                final firstDow = (w.first.weekday - 1) % 7; // 0=Mon
                for (int i = 0; i < firstDow; i++) cells.add(null);
              }
              cells.addAll(w);
              while (cells.length < 7) cells.add(null);

              return Column(
                children: cells.take(7).map((d) {
                  if (d == null) return const SizedBox(width: 12, height: 14);
                  final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                  final amt = (dailySpending[key] as num?)?.toDouble() ?? 0;
                  final intensity = maxAmt > 0 ? (amt / maxAmt).clamp(0.0, 1.0) : 0.0;
                  return GestureDetector(
                    onTap: () => _showDayDetail(context, d, amt),
                    child: Tooltip(
                      message: amt > 0 ? '${DateFormat('d MMM').format(d)}: ${formatAmount(amt)}' : DateFormat('d MMM').format(d),
                      child: Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: _cellColor(context, intensity, amt),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
        const SizedBox(height: 8),
        // Legend
        Row(
          children: [
            Text(loc.t('heatmap_legend_less'), style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
            const SizedBox(width: 4),
            ...[0.0, 0.25, 0.5, 0.75, 1.0].map((v) => Container(
              width: 12, height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: _cellColor(context, v, v * maxAmt),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(width: 4),
            Text(loc.t('heatmap_legend_more'), style: TextStyle(fontSize: 10, color: AppThemeColors.secondaryText(context))),
          ],
        ),
      ],
    );
  }

  Color _cellColor(BuildContext context, double intensity, double amount) {
    if (amount == 0) {
      return Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFEEEEEE);
    }
    // Green → Yellow → Red scale
    if (intensity < 0.33) return Color.lerp(const Color(0xFF1B8A00), const Color(0xFF76C442), intensity / 0.33)!;
    if (intensity < 0.66) return Color.lerp(const Color(0xFF76C442), const Color(0xFFFFC107), (intensity - 0.33) / 0.33)!;
    return Color.lerp(const Color(0xFFFFC107), const Color(0xFFC62828), (intensity - 0.66) / 0.34)!;
  }

  void _showDayDetail(BuildContext context, DateTime day, double amount) {
    if (amount == 0) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(DateFormat('EEEE, d MMMM yyyy').format(day),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text(formatAmount(amount),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.cyan)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx).t('heatmap_close'))),
        ],
      ),
    );
  }
}
