import 'package:flutter/material.dart';
import '../user/digitise/subscriptions_page.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

Widget _tricolorBorder({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        colors: [Colors.orange, Colors.white, Colors.green],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: child,
  );
}

Widget _subscribeBtn(BuildContext context) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      icon: const Icon(Icons.workspace_premium, color: Colors.amber, size: 18),
      label: const Text('Subscribe Now',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
  return SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color ?? Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.w600)),
    ),
  );
}

// ── Daily limit dialog — hard block, must wait for tomorrow or subscribe ──────

void showDailyLimitDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
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
            const Text('Daily Limit Reached',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
            const SizedBox(height: 10),
            Text(
              message ??
                  'You have reached today\'s limit for this action. Please try again tomorrow.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
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
                  Text('Free attempts are also paused until tomorrow.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            const Row(children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR SUBSCRIBE FOR UNLIMITED',
                    style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 0.6)),
              ),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 14),
            _subscribeBtn(ctx),
            const SizedBox(height: 8),
            _closeBtn(ctx, color: Colors.red.shade300),
          ]),
        ),
      ),
    ),
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
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFF3E5F5),
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
            const Text('No Free Attempts Left',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple)),
            const SizedBox(height: 10),
            Text(
              'You\'ve used all your free $featureName attempts. You can spend $coinCost LenDen coins to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
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
                    Text('Your coins: $currentCoins',
                        style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                  ]),
                  Row(children: [
                    const Icon(Icons.remove_circle_outline, size: 14, color: Colors.deepOrange),
                    const SizedBox(width: 4),
                    Text('Cost: $coinCost coins',
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
                label: Text('Use $coinCost Coins',
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
            const Row(children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('OR SUBSCRIBE',
                    style: TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 0.6)),
              ),
              Expanded(child: Divider()),
            ]),
            const SizedBox(height: 8),
            _subscribeBtn(ctx),
            const SizedBox(height: 8),
            _closeBtn(ctx, color: Colors.purple.shade200),
          ]),
        ),
      ),
    ),
  );
}

// ── Insufficient coins dialog ─────────────────────────────────────────────────

void showInsufficientCoinsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
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
            const Text('Insufficient LenDen Coins',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange)),
            const SizedBox(height: 10),
            Text(
              'You don\'t have enough LenDen coins to perform this action. Subscribe for unlimited access.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 20),
            _subscribeBtn(ctx),
            const SizedBox(height: 8),
            _closeBtn(ctx, color: Colors.orange.shade200),
          ]),
        ),
      ),
    ),
  );
}

// ── Zero coins dialog ─────────────────────────────────────────────────────────

void showZeroCoinsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
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
            const Text('No LenDen Coins',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
            const SizedBox(height: 10),
            Text(
              'You have 0 LenDen coins. Subscribe for unlimited access to all features.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 20),
            _subscribeBtn(ctx),
            const SizedBox(height: 8),
            _closeBtn(ctx, color: Colors.red.shade300),
          ]),
        ),
      ),
    ),
  );
}

// ── Blocked user dialog ───────────────────────────────────────────────────────

void showBlockedUserDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E6),
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
            const Text('Blocked User',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red)),
            const SizedBox(height: 10),
            Text(
              message ??
                  'This user is blocked. Unblock them to create transactions or groups.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[800], height: 1.4),
            ),
            const SizedBox(height: 20),
            _closeBtn(ctx, color: Colors.red.shade300),
          ]),
        ),
      ),
    ),
  );
}

// ── Total message limit dialog (chat) ─────────────────────────────────────────

void showTotalLimitDialog(BuildContext context, {String? message}) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: _tricolorBorder(
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4E6),
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
            const Text('Message Limit Reached',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange)),
            const SizedBox(height: 10),
            Text(
              message ??
                  'You have reached the total free message limit. Subscribe for unlimited access.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 20),
            _subscribeBtn(ctx),
            const SizedBox(height: 8),
            _closeBtn(ctx, color: Colors.deepOrange.shade200),
          ]),
        ),
      ),
    ),
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
      title = 'Daily limit reached';
      subtitle = 'Free attempts also paused. Resets tomorrow.';
    } else if (freeOut) {
      bgColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
      textColor = Colors.orange.shade800;
      icon = Icons.toll_rounded;
      title = 'No free $featureName attempts left';
      subtitle = 'You can use LenDen coins to continue (daily limit: ${dailyRemaining ?? '—'} left today).';
    } else {
      bgColor = Colors.green.shade50;
      borderColor = Colors.green.shade300;
      textColor = Colors.green.shade800;
      icon = Icons.check_circle_outline;
      title = '${freeRemaining ?? '—'} free attempt${(freeRemaining ?? 1) == 1 ? '' : 's'} left';
      subtitle = '${dailyRemaining ?? '—'} of today\'s daily limit remaining.';
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
              child: const Text('Subscribe',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ]),
    );
  }
}
