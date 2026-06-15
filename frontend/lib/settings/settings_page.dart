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
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(110),
                color: const Color(0xFF00B4D8),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Profile Card
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        color: const Color(0xFFFFF4E6),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 30,
                                backgroundColor: const Color(0xFF00B4D8),
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
                              icon: const Icon(Icons.edit, color: Color(0xFF00B4D8)),
                              onPressed: () => Navigator.pushNamed(context, '/profile'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Account Settings
                  _sectionLabel('Account Settings'),
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
                  _sectionLabel('Preferences'),
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
                  _sectionLabel('Support & About'),
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
                      onPressed: () => _showLogoutDialog(context),
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 0.4,
        ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9933), Colors.white, Color(0xFF138808)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
                      Icon(icon, color: const Color(0xFF00B4D8), size: 24),
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
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Logout',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
          content: const Text('Are you sure you want to logout?',
              style: TextStyle(color: Colors.black87)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final session = Provider.of<SessionProvider>(context, listen: false);
                session.logout();
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed('/');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height * 0.35);
    path.quadraticBezierTo(
        size.width * 0.25, size.height * 0.5, size.width * 0.5, size.height * 0.35);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.2, size.width, size.height * 0.35);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
