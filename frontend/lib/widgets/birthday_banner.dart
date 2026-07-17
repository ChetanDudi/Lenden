import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Shows a celebratory banner when today is the given birthday.
/// Returns [SizedBox.shrink] if [birthdayRaw] is null or not today.
class BirthdayBanner extends StatelessWidget {
  final String? birthdayRaw;

  const BirthdayBanner({super.key, required this.birthdayRaw});

  @override
  Widget build(BuildContext context) {
    if (birthdayRaw == null || birthdayRaw!.isEmpty) return const SizedBox.shrink();
    final bday = DateTime.tryParse(birthdayRaw!);
    if (bday == null) return const SizedBox.shrink();
    final now = DateTime.now();
    if (bday.month != now.month || bday.day != now.day) return const SizedBox.shrink();

    final age = now.year - bday.year;
    final t = AppLocalizations.of(context).t;
    final sub = age > 0
        ? t('birthday_age_message').replaceFirst('{age}', '$age')
        : t('birthday_wish_message');

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B6B), Color(0xFFFFB300), Color(0xFF6BCB77)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.amber.withValues(alpha: 0.40), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Row(children: [
        const Text('🎂', style: TextStyle(fontSize: 32)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('happy_birthday_label'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
        const Icon(Icons.celebration_rounded, color: Colors.white70, size: 26),
      ]),
    );
  }
}
