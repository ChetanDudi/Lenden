import 'package:flutter/material.dart';
import '../user/digitise/subscriptions_page.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import 'app_widgets.dart';
import 'app_colors.dart';

Future<void> showDailyRewardSheet(BuildContext context, int coins) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: false,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(ctx),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppThemeColors.divider(ctx),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 28),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.stars_rounded, color: Colors.white, size: 42),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Daily Login Bonus! 🎉',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppThemeColors.primaryText(ctx),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'You earned',
                  style: TextStyle(fontSize: 15, color: AppThemeColors.secondaryText(ctx)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on_rounded, color: Color(0xFFF59E0B), size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '$coins LenDen Coin${coins > 1 ? "s" : ""}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Keep logging in daily to earn more!',
              style: TextStyle(fontSize: 13, color: AppThemeColors.mutedText(ctx)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.cyan, AppColors.blue]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Awesome!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _subscribeBtn(BuildContext context) {
  final t = AppLocalizations.of(context).t;
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: const Icon(Icons.workspace_premium, color: Colors.amber, size: 18),
      label: Text(t('subscribe_now'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0096C7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () {
        Navigator.of(context).pop();
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SubscriptionsPage()));
      },
    ),
  );
}

Widget _closeBtn(BuildContext context, {Color? color}) {
  final t = AppLocalizations.of(context).t;
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color ?? AppThemeColors.border(context)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () => Navigator.of(context).pop(),
      child: Text(t('got_it'),
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppThemeColors.primaryText(context))),
    ),
  );
}

// ── Daily limit dialog — hard block, must wait for tomorrow or subscribe ──────

void showDailyLimitDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFFFF3E0), dark: const Color(0xFF332A1A)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Icon with glow
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.schedule, color: Colors.red, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('daily_limit_reached'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 10),
              Text(
                message ?? t('daily_limit_default_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Text(t('free_attempts_paused'),
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(t('or_subscribe_unlimited'),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey, letterSpacing: 0.6)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 14),
              _subscribeBtn(ctx),
              const SizedBox(height: 8),
              _closeBtn(ctx, color: Colors.red.shade300),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Free attempts exhausted — coins available as fallback ─────────────────────

Future<bool?> showFreeAttemptsExhaustedDialog(
  BuildContext context, {
  required String featureName,
  required int coinCost,
  required int currentCoins,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFF3E5F5), dark: const Color(0xFF2E2335)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.toll_rounded, color: Colors.purple, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('no_free_attempts_left_title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.purple)),
              const SizedBox(height: 10),
              Text(
                t('used_all_free_attempts_message').replaceFirst('{feature}', featureName).replaceFirst('{coins}', '$coinCost'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      const Icon(Icons.toll_rounded, size: 14, color: Colors.purple),
                      const SizedBox(width: 4),
                      Text('${t('your_coins')}: $currentCoins',
                          style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                    ]),
                    Row(children: [
                      const Icon(Icons.remove_circle_outline, size: 14, color: Colors.deepOrange),
                      const SizedBox(width: 4),
                      Text('${t('cost_label')}: $coinCost',
                          style: TextStyle(fontSize: 12, color: Colors.deepOrange.shade700, fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.toll_rounded, color: Colors.white, size: 18),
                  label: Text(t('use_coins_label').replaceFirst('{coins}', '$coinCost'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(t('or_subscribe'),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey, letterSpacing: 0.6)),
                ),
                const Expanded(child: Divider()),
              ]),
              const SizedBox(height: 8),
              _subscribeBtn(ctx),
              const SizedBox(height: 8),
              _closeBtn(ctx, color: Colors.purple.shade200),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Insufficient coins dialog ─────────────────────────────────────────────────

void showInsufficientCoinsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFFFF8E1), dark: const Color(0xFF332C1A)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('insufficient_coins_title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange)),
              const SizedBox(height: 10),
              Text(
                t('insufficient_coins_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              _subscribeBtn(ctx),
              const SizedBox(height: 8),
              _closeBtn(ctx, color: Colors.orange.shade200),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Zero coins dialog ─────────────────────────────────────────────────────────

void showZeroCoinsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFFFEBEE), dark: const Color(0xFF3A2222)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.red.withValues(alpha: 0.2),
                        blurRadius: 16,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.toll_rounded, color: Colors.red, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('zero_coins_title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 10),
              Text(
                t('zero_coins_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              _subscribeBtn(ctx),
              const SizedBox(height: 8),
              _closeBtn(ctx, color: Colors.red.shade300),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Blocked user dialog ───────────────────────────────────────────────────────

void showBlockedUserDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFFFF4E6), dark: const Color(0xFF332A1F)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block, color: Colors.red, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('blocked_user_title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red)),
              const SizedBox(height: 10),
              Text(
                message ?? t('blocked_user_default_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.primaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              _closeBtn(ctx, color: Colors.red.shade300),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Total message limit dialog (chat) ─────────────────────────────────────────

void showTotalLimitDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) {
      final t = AppLocalizations.of(ctx).t;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: tricolorBorder(radius: 22,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
            decoration: BoxDecoration(
              color: AppThemeColors.tinted(ctx,
                  light: const Color(0xFFFFF4E6), dark: const Color(0xFF332A1F)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline, color: Colors.deepOrange, size: 40),
              ),
              const SizedBox(height: 16),
              Text(t('message_limit_reached_title'),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange)),
              const SizedBox(height: 10),
              Text(
                message ?? t('message_limit_default_message'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppThemeColors.secondaryText(ctx),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              _subscribeBtn(ctx),
              const SizedBox(height: 8),
              _closeBtn(ctx, color: Colors.deepOrange.shade200),
            ]),
          ),
        ),
      );
    },
  );
}

// ── Limit status banner — inline widget for list/create pages ─────────────────

class LimitStatusBanner extends StatelessWidget {
  final bool isSubscribed;
  final int? freeRemaining;
  final int? dailyRemaining;
  final String featureName;

  const LimitStatusBanner({
    Key? key,
    required this.isSubscribed,
    this.freeRemaining,
    this.dailyRemaining,
    required this.featureName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isSubscribed) return const SizedBox.shrink();
    final t = AppLocalizations.of(context).t;

    final dailyOut = dailyRemaining != null && dailyRemaining! <= 0;
    final freeOut = freeRemaining != null && freeRemaining! <= 0;

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String title;
    String subtitle;

    if (dailyOut) {
      bgColor = Colors.red.shade50;
      borderColor = Colors.red.shade300;
      textColor = Colors.red.shade800;
      icon = Icons.schedule;
      title = t('daily_limit_reached');
      subtitle = t('free_attempts_paused_resets_tomorrow_message');
    } else if (freeOut) {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      textColor = Colors.orange.shade800;
      icon = Icons.toll_rounded;
      title = t('no_free_feature_attempts_left_message').replaceFirst('{feature}', featureName);
      subtitle = t('use_coins_continue_daily_limit_message').replaceFirst('{count}', '${dailyRemaining ?? '—'}');
    } else {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      textColor = Colors.green.shade800;
      icon = Icons.check_circle_outline;
      title = t('free_attempts_left_message').replaceFirst('{count}', '${freeRemaining ?? '—'}');
      subtitle = t('daily_limit_remaining_message').replaceFirst('{count}', '${dailyRemaining ?? '—'}');
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: textColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.85))),
          ]),
        ),
        if (dailyOut || freeOut)
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SubscriptionsPage())),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0096C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(t('subscribe'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }
}
