import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../utils/responsive.dart';
import '../widgets/app_colors.dart';
import '../user/support/contact_page.dart';
import '../settings/about_page.dart';
import '../widgets/notification_icon.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_helper.dart';
import 'landing_nav_item.dart';
import 'landing_tab_bar.dart';
import 'app_highlight_card.dart';
import 'lenden_showcase_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      drawer: Drawer(
        width: context.sw(200),
        backgroundColor: AppThemeColors.cardBg(context),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: AppThemeColors.waveSolid(context),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/icon.png',
                      width: context.sw(48), height: context.sw(48)),
                  SizedBox(height: context.sh(8)),
                  Text('Lenden App',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: context.sp(20),
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: Text(t('home')),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: Text(t('login')),
              onTap: () {
                final session =
                    Provider.of<SessionProvider>(context, listen: false);
                if (session.token != null && session.user != null) {
                  if (session.isAdmin) {
                    Navigator.pushReplacementNamed(context, '/admin/dashboard');
                  } else {
                    Navigator.pushReplacementNamed(context, '/user/dashboard');
                  }
                } else {
                  Navigator.pushNamed(context, '/login');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add),
              title: Text(t('register')),
              onTap: () => Navigator.pushNamed(context, '/register'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(t('about')),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.contact_mail),
              title: Text(t('contact')),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContactPage()),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Light-blue header panel (title + tabs)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFBEE3F0),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(context.sw(20), context.sh(6),
                    context.sw(20), context.sh(18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon row: menu | spacer | notification + profile
                    Row(
                      children: [
                        Builder(
                          builder: (ctx) => GestureDetector(
                            onTap: () => Scaffold.of(ctx).openDrawer(),
                            child: Icon(Icons.menu,
                                color: Colors.black87,
                                size: context.sp(26)),
                          ),
                        ),
                        const Spacer(),
                        NotificationIcon(),
                        SizedBox(width: context.sw(8)),
                        Consumer<SessionProvider>(
                          builder: (context, session, _) {
                            final user = session.user;
                            final profileImage = user != null &&
                                    user['profileImage'] != null &&
                                    user['profileImage']
                                            .toString()
                                            .isNotEmpty &&
                                    user['profileImage'] != 'null'
                                ? NetworkImage(user['profileImage'])
                                : null;
                            return GestureDetector(
                              onTap: () {
                                if (session.token != null &&
                                    session.user != null) {
                                  Navigator.pushNamed(context, '/profile');
                                } else {
                                  showDialog(
                                    context: context,
                                    builder: (dlgCtx) {
                                      final dt =
                                          AppLocalizations.of(dlgCtx).t;
                                      return AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(24),
                                        ),
                                        backgroundColor:
                                            const Color(0xFFF6F7FB),
                                        elevation: 12,
                                        title: Row(
                                          children: [
                                            Icon(Icons.lock_outline,
                                                color: AppColors.cyan,
                                                size: context.sp(26)),
                                            SizedBox(width: context.sw(8)),
                                            Text(dt('login_required'),
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    fontSize:
                                                        context.sp(20))),
                                          ],
                                        ),
                                        content: Text(
                                          dt('please_login_to_view_profile'),
                                          style: TextStyle(
                                              fontSize: context.sp(15),
                                              color: Colors.black87),
                                        ),
                                        actions: [
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              backgroundColor: AppColors.cyan,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                            ),
                                            onPressed: () =>
                                                Navigator.of(dlgCtx).pop(),
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: context.sw(16),
                                                  vertical: context.sh(6)),
                                              child: Text(dt('ok'),
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize:
                                                          context.sp(15))),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                }
                              },
                              child: CircleAvatar(
                                radius: context.sw(17),
                                backgroundColor: Colors.grey.shade300,
                                backgroundImage: profileImage,
                                child: profileImage == null
                                    ? Icon(Icons.person,
                                        color: Colors.grey.shade600,
                                        size: context.sp(18))
                                    : null,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    SizedBox(height: context.sh(18)),
                    Text(
                      'My Transactions',
                      style: TextStyle(
                        fontSize: context.sp(30),
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: context.sh(16)),
                    const LandingTabBar(),
                    SizedBox(height: context.sh(2)),
                  ],
                ),
              ),
            ),
          ),
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                  horizontal: context.sw(20), vertical: context.sh(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppHighlightCard(),
                  SizedBox(height: context.sh(18)),
                  const LenDenShowcaseCard(),
                  SizedBox(height: context.sh(18)),
                  const _FeatureTrioRow(),
                  SizedBox(height: context.sh(16)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: context.sw(8), vertical: context.sh(8)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              LandingNavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                active: true,
                onTap: () {
                  final session =
                      Provider.of<SessionProvider>(context, listen: false);
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
              ),
              LandingNavItem(
                icon: Icons.person_add_rounded,
                label: 'Register',
                onTap: () => Navigator.pushNamed(context, '/register'),
              ),
              LandingNavItem(
                icon: Icons.info_outline_rounded,
                label: 'About',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutPage())),
              ),
              LandingNavItem(
                icon: Icons.contact_mail_rounded,
                label: 'Contact',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ContactPage())),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTrioRow extends StatelessWidget {
  const _FeatureTrioRow();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.flash_on_rounded,   'Quick',   'Instant lending',  Color(0xFF0096C7)),
      (Icons.shield_rounded,     'Secure',  'OTP-verified',     Color(0xFF6A1B9A)),
      (Icons.groups_rounded,     'Groups',  'Split fairly',     Color(0xFF00796B)),
    ];
    return Row(
      children: items.map((item) {
        final (icon, label, desc, color) = item;
        return Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: context.sw(5)),
            padding: EdgeInsets.symmetric(
                vertical: context.sh(14), horizontal: context.sw(10)),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: context.sw(40),
                  height: context.sw(40),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: context.sp(20)),
                ),
                SizedBox(height: context.sh(8)),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: context.sp(13),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: context.sh(2)),
                Text(
                  desc,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: context.sp(10),
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
