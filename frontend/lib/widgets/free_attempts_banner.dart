import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'app_colors.dart';

/// Shows a chip indicating free attempts left and/or coin-based daily attempts.
/// Pass [featureKey] matching session's hasFeature keys.
/// [dailyRemaining] is optional — pass it for pages that already track the
/// coin-based daily limit (e.g. quick transactions).
class FreeAttemptsBanner extends StatelessWidget {
  final String featureKey;
  final int? dailyRemaining;

  const FreeAttemptsBanner({
    super.key,
    required this.featureKey,
    this.dailyRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SessionProvider>(
      builder: (context, session, _) {
        if (session.hasFeature(featureKey)) {
          return _chip(
            context,
            icon: Icons.all_inclusive_rounded,
            label: 'Unlimited — subscribed',
            color: AppColors.cyan,
          );
        }

        final free = _freeFor(session);
        final chips = <Widget>[];

        if (free != null) {
          final color = free > 2
              ? const Color(0xFF1565C0)
              : free > 0
                  ? Colors.orange
                  : Colors.red;
          chips.add(_chip(
            context,
            icon: free > 0
                ? Icons.confirmation_num_outlined
                : Icons.block_rounded,
            label: free > 0
                ? '$free free attempt${free == 1 ? '' : 's'} remaining'
                : 'Free attempts exhausted',
            color: color,
          ));
        }

        if ((free ?? 1) <= 0 && dailyRemaining != null) {
          chips.add(const SizedBox(height: 5));
          chips.add(_chip(
            context,
            icon: Icons.monetization_on_outlined,
            label: dailyRemaining! > 0
                ? '${dailyRemaining!} coin-based attempt${dailyRemaining! == 1 ? '' : 's'} left today'
                : 'Daily coin limit reached',
            color: dailyRemaining! > 0 ? const Color(0xFF00695C) : Colors.red,
          ));
        }

        if (chips.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: chips,
          ),
        );
      },
    );
  }

  int? _freeFor(SessionProvider session) {
    switch (featureKey) {
      case 'quick_transactions':
        return session.freeQuickTransactionsRemaining;
      case 'secure_transactions':
        return session.freeUserTransactionsRemaining;
      case 'group_creation':
      case 'group_expenses':
        return session.freeGroupsRemaining;
      default:
        return null;
    }
  }

  Widget _chip(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
