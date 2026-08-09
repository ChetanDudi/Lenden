import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../settings/about_page.dart';
import '../utils/responsive.dart';

class LenDenShowcaseCard extends StatefulWidget {
  const LenDenShowcaseCard({super.key});

  @override
  State<LenDenShowcaseCard> createState() => _LenDenShowcaseCardState();
}

class _LenDenShowcaseCardState extends State<LenDenShowcaseCard> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    const sageGreen = Color(0xFFC8CBBA);
    const darkText = Color(0xFF1A1A1A);

    return Container(
      decoration: BoxDecoration(
        color: sageGreen,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 12, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: EdgeInsets.fromLTRB(context.sw(18), context.sh(18),
                context.sw(14), context.sh(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'LenDen',
                        style: TextStyle(
                          fontSize: context.sp(26),
                          fontWeight: FontWeight.w800,
                          color: darkText,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: context.sh(2)),
                      Text(
                        'Smart Money Management',
                        style: TextStyle(
                          fontSize: context.sp(12),
                          color: darkText.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _collapsed = !_collapsed),
                  child: Container(
                    padding: EdgeInsets.all(context.sw(8)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: darkText,
                      size: context.sp(18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Avatar cluster + Get Started
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
            child: Row(
              children: [
                const AvatarCluster(),
                SizedBox(width: context.sw(12)),
                Consumer<SessionProvider>(
                  builder: (context, session, _) => GestureDetector(
                    onTap: () {
                      if (session.token != null && session.user != null) {
                        if (session.isAdmin) {
                          Navigator.pushNamed(context, '/admin/dashboard');
                        } else {
                          Navigator.pushNamed(context, '/user/dashboard');
                        }
                      } else {
                        Navigator.pushNamed(context, '/login');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.sw(14),
                          vertical: context.sh(7)),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9)),
                      ),
                      child: Text(
                        'Get Started',
                        style: TextStyle(
                          fontSize: context.sp(12),
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: context.sh(14)),
          // Feature row
          ShowcaseRow(
            icon: Icons.location_on_rounded,
            label: 'Quick • Secure • Group Transactions',
            darkText: darkText,
          ),
          SizedBox(height: context.sh(12)),
          // Two action buttons
          Padding(
            padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutPage())),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: context.sw(20),
                        vertical: context.sh(8)),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    child: Text(
                      'About',
                      style: TextStyle(
                        fontSize: context.sp(13),
                        fontWeight: FontWeight.w600,
                        color: darkText,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Consumer<SessionProvider>(
                  builder: (context, session, _) => GestureDetector(
                    onTap: () {
                      if (session.token != null && session.user != null) {
                        if (session.isAdmin) {
                          Navigator.pushNamed(context, '/admin/dashboard');
                        } else {
                          Navigator.pushNamed(context, '/user/dashboard');
                        }
                      } else {
                        Navigator.pushNamed(context, '/login');
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.sw(20),
                          vertical: context.sh(8)),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Explore',
                        style: TextStyle(
                          fontSize: context.sp(13),
                          fontWeight: FontWeight.w600,
                          color: darkText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Expanded sub-items
          if (!_collapsed) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: darkText.withValues(alpha: 0.12),
              indent: context.sw(18),
              endIndent: context.sw(18),
            ),
            SizedBox(height: context.sh(12)),
            ...[
              (Icons.flash_on_rounded,              'Quick Transactions',   'Lend & borrow instantly with one tap'),
              (Icons.shield_rounded,                'Secure Transactions',  'OTP-verified lending with interest & repayment'),
              (Icons.groups_rounded,                'Group Expenses',       'Split bills & settle group expenses fairly'),
              (Icons.account_balance_wallet_rounded,'LenDen Wallet',        'In-app wallet for instant payments & withdrawals'),
              (Icons.qr_code_scanner_rounded,       'QR Payments',          'Scan a QR code to pay friends instantly'),
              (Icons.people_alt_rounded,            'Friend Balances',      'See exactly who owes you & what you owe'),
              (Icons.pin_rounded,                   'Wallet PIN',           'Secure every payment with a 6-digit PIN'),
              (Icons.monetization_on_rounded,       'LenDen Coins',         'Earn coins for activity & redeem rewards'),
              (Icons.calendar_today_rounded,        'Due Date Calendar',    'Visual calendar of all upcoming due dates'),
              (Icons.local_offer_rounded,           'Offers & Gifts',       'Exclusive coin offers & gift card rewards'),
              (Icons.support_agent_rounded,         '24/7 Support',         'In-app help, disputes & live chat'),
              (Icons.repeat_rounded,                'Recurring Payments',   'Auto-schedule recurring payments & reminders'),
              (Icons.savings_rounded,               'Savings Goals',        'Set targets, track progress & hit milestones'),
              (Icons.pie_chart_rounded,             'Budget Planning',      'Monthly limits by category with alerts'),
              (Icons.auto_awesome_rounded,          'Smart Insights',       'AI-powered spending analysis & predictions'),
              (Icons.bar_chart_rounded,             'Reports & Analytics',  'Charts, trends & PDF export for any period'),
              (Icons.grid_view_rounded,             'Spending Heatmap',     '13-week visual calendar of daily spending'),
              (Icons.star_rounded,                  'Ratings',              'Build trust by rating your counterparties'),
              (Icons.workspace_premium_rounded,     'Go Premium',           'Unlock Insights, Budget, Reports, Goals & more'),
            ].map(
              (item) => Padding(
                padding: EdgeInsets.fromLTRB(
                    context.sw(18), 0, context.sw(18), context.sh(10)),
                child: Row(
                  children: [
                    Container(
                      width: context.sw(42),
                      height: context.sw(42),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.$1,
                          color: darkText, size: context.sp(20)),
                    ),
                    SizedBox(width: context.sw(12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$2,
                            style: TextStyle(
                              fontSize: context.sp(13),
                              fontWeight: FontWeight.w600,
                              color: darkText,
                            ),
                          ),
                          Text(
                            item.$3,
                            style: TextStyle(
                              fontSize: context.sp(11),
                              color: darkText.withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/icon.png',
                        width: context.sw(40),
                        height: context.sw(40),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: context.sw(40),
                          height: context.sw(40),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(item.$1,
                              color: darkText.withValues(alpha: 0.5),
                              size: context.sp(18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: context.sh(4)),
          ],
        ],
      ),
    );
  }
}

class AvatarCluster extends StatelessWidget {
  const AvatarCluster({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFF0077B6),
      Color(0xFF00B4D8),
      Color(0xFF48CAE4),
    ];
    const icons = [Icons.person, Icons.face, Icons.account_circle];
    return SizedBox(
      width: context.sw(68),
      height: context.sw(28),
      child: Stack(
        children: List.generate(3, (i) {
          return Positioned(
            left: i * context.sw(18),
            child: CircleAvatar(
              radius: context.sw(14),
              backgroundColor: Colors.white,
              child: CircleAvatar(
                radius: context.sw(12),
                backgroundColor: colors[i],
                child:
                    Icon(icons[i], color: Colors.white, size: context.sp(13)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class ShowcaseRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color darkText;
  const ShowcaseRow({
    super.key,
    required this.icon,
    required this.label,
    required this.darkText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.sw(18)),
      child: Row(
        children: [
          Icon(icon, size: context.sp(15), color: darkText.withValues(alpha: 0.6)),
          SizedBox(width: context.sw(8)),
          Text(
            label,
            style: TextStyle(
              fontSize: context.sp(13),
              color: darkText.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
