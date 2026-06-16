import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../password_management/change_password_page.dart';
import '../alternative_email/alternative_email_page.dart';
import 'notification_settings_page.dart';
import 'privacy_settings_page.dart';
import 'account_settings_page.dart';
import '../user/support/help_support_page.dart';
import '../utils/responsive.dart';
import 'about_page.dart';
import 'terms_of_service_page.dart';
import 'privacy_policy_page.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppColors.scaffoldBg,
      appBar: transparentAppBar(context, title: 'Settings'),
      body: Stack(
        children: [
          cyanWaveHeader(height: context.sh(110)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile Card
                  tricolorBorder(
                    radius: 18,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      color: AppColors.warmCardBg,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.tricolorGradient,
                            ),
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: AppColors.cyan,
                              child: session.user?['profileImage'] != null
                                  ? ClipOval(
                                      child: session.user!['profileImage'] is String
                                          ? Image.network(
                                              session.user!['profileImage'],
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return Text(
                                                  (session.user?['name'] as String?)
                                                          ?.substring(0, 1)
                                                          .toUpperCase() ??
                                                      'U',
                                                  style: TextStyle(
                                                    fontSize: context.sp(22),
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                );
                                              },
                                            )
                                          : Image.memory(
                                              session.user!['profileImage'],
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover,
                                            ),
                                    )
                                  : Text(
                                      (session.user?['name'] as String?)
                                              ?.substring(0, 1)
                                              .toUpperCase() ??
                                          'U',
                                      style: TextStyle(
                                        fontSize: context.sp(22),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.user?['name'] ?? 'User',
                                  style: TextStyle(
                                    fontSize: context.sp(16),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  session.user?['email'] ?? 'user@example.com',
                                  style: TextStyle(
                                    fontSize: context.sp(13),
                                    color: Colors.grey,
                                  ),
                                ),
                                if (session.user?['altEmail'] != null &&
                                    (session.user!['altEmail'] as String).isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, size: 12, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Alternative email set',
                                        style: TextStyle(
                                          fontSize: context.sp(9),
                                          color: Colors.green,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppColors.cyan),
                            onPressed: () => Navigator.pushNamed(context, '/profile'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Account Settings
                  sectionLabel('Account Settings'),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: 'Change Password',
                    icon: Icons.lock_outline,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ChangePasswordPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: session.user?['altEmail'] != null &&
                            (session.user!['altEmail'] as String).isNotEmpty
                        ? 'Change Alternative Email'
                        : 'Add Alternative Email',
                    icon: Icons.email_outlined,
                    subtitle: session.user?['altEmail'] != null &&
                            (session.user!['altEmail'] as String).isNotEmpty
                        ? session.user!['altEmail'] as String
                        : 'Add a backup email for account recovery',
                    showStatus: true,
                    isActive: session.user?['altEmail'] != null &&
                        (session.user!['altEmail'] as String).isNotEmpty,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AlternativeEmailPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: 'Account Information',
                    icon: Icons.person_outline,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AccountSettingsPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Preferences
                  sectionLabel('Preferences'),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: 'Notification Settings',
                    icon: Icons.notifications_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NotificationSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: 'Privacy Settings',
                    icon: Icons.privacy_tip_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PrivacySettingsPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Support & About
                  sectionLabel('Support & About'),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: 'Help & Support',
                    icon: Icons.help_outline,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => HelpSupportPage())),
                  ),
                  _buildTile(
                    context,
                    title: 'About LenDen',
                    icon: Icons.info_outline,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AboutPage())),
                  ),
                  _buildTile(
                    context,
                    title: 'Terms of Service',
                    icon: Icons.description_outlined,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const TermsOfServicePage())),
                  ),
                  _buildTile(
                    context,
                    title: 'Privacy Policy',
                    icon: Icons.security_outlined,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PrivacyPolicyPage())),
                  ),

                  const SizedBox(height: 24),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => showLogoutDialog(context, onConfirm: () {
                        final session =
                            Provider.of<SessionProvider>(context, listen: false);
                        session.logout();
                        Navigator.of(context).pushReplacementNamed('/');
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: EdgeInsets.symmetric(vertical: context.sh(14)),
                      ),
                      child: Text(
                        'Logout',
                        style: TextStyle(
                          fontSize: context.sp(15),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    String? subtitle,
    bool showStatus = false,
    bool isActive = false,
  }) {
    return tricolorBorder(
      radius: 16,
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Stack(
                  children: [
                    Icon(icon, color: AppColors.cyan, size: 24),
                    if (showStatus)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: context.sp(15),
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: context.sp(11), color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
