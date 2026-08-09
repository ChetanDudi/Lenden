import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/responsive.dart';

class AppHighlightCard extends StatefulWidget {
  const AppHighlightCard({super.key});

  @override
  State<AppHighlightCard> createState() => _AppHighlightCardState();
}

class _AppHighlightCardState extends State<AppHighlightCard> {
  int _current = 0;
  Timer? _timer;

  static const _cards = [
    {
      'icon': Icons.flash_on_rounded,
      'title': 'Quick Transactions',
      'body': 'Lend & borrow money instantly with a single tap — no delays.',
      'color': Color(0xFF0077B6),
    },
    {
      'icon': Icons.shield_rounded,
      'title': 'Secure Transactions',
      'body': 'OTP-verified lending with interest calculation & repayment schedule.',
      'color': Color(0xFF00B4D8),
    },
    {
      'icon': Icons.groups_rounded,
      'title': 'Group Expenses',
      'body': 'Split bills fairly among friends and settle group expenses easily.',
      'color': Color(0xFF0096C7),
    },
    {
      'icon': Icons.account_balance_wallet_rounded,
      'title': 'LenDen Wallet',
      'body': 'In-app wallet for instant payments, top-ups & withdrawals.',
      'color': Color(0xFF023E8A),
    },
    {
      'icon': Icons.qr_code_scanner_rounded,
      'title': 'QR Payments',
      'body': 'Scan a QR code to pay friends or receive money instantly.',
      'color': Color(0xFF0077B6),
    },
    {
      'icon': Icons.auto_awesome_rounded,
      'title': 'Smart Insights',
      'body': 'AI-powered spending analysis and personalized money tips.',
      'color': Color(0xFF00B4D8),
    },
    {
      'icon': Icons.savings_rounded,
      'title': 'Savings Goals',
      'body': 'Set financial targets, track progress and celebrate milestones.',
      'color': Color(0xFF0096C7),
    },
    {
      'icon': Icons.monetization_on_rounded,
      'title': 'LenDen Coins',
      'body': 'Earn coins for every activity and redeem them for rewards.',
      'color': Color(0xFF023E8A),
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _current = (_current + 1) % _cards.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = _cards[_current];
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Container(
            key: ValueKey(_current),
            width: double.infinity,
            padding: EdgeInsets.all(context.sw(18)),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About this app',
                  style: TextStyle(
                    fontSize: context.sp(11),
                    color: Colors.grey.shade500,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: context.sh(8)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      card['icon'] as IconData,
                      color: Colors.black87,
                      size: context.sp(20),
                    ),
                    SizedBox(width: context.sw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['title'] as String,
                            style: TextStyle(
                              fontSize: context.sp(15),
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: context.sh(5)),
                          Text(
                            card['body'] as String,
                            style: TextStyle(
                              fontSize: context.sp(13),
                              color: Colors.black54,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: context.sh(8)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_cards.length, (i) {
            final active = i == _current;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: active ? 16 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: active ? Colors.black54 : Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}
