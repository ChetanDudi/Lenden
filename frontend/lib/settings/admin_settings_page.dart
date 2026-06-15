import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'admin_system_settings_page.dart';
import 'admin_analytics_settings_page.dart';
import 'admin_security_settings_page.dart';
import 'admin_notification_settings_page.dart';
import 'admin_management_page.dart';
import '../password_management/change_password_page.dart';
import '../admin/audit/audit_logs_page.dart';
import 'admin_backup_restore_page.dart';
import 'admin_data_export_page.dart';
import 'admin_system_maintenance_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text(
          'Admin Settings',
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
              clipper: _AdminTopWaveClipper(),
              child: Container(
                height: 110,
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
                  // Admin Profile Card
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
                                                errorBuilder: (context, error, stackTrace) =>
                                                    Text(
                                                  (session.user?['name'] as String?)
                                                          ?.substring(0, 1)
                                                          .toUpperCase() ??
                                                      'A',
                                                  style: const TextStyle(
                                                      fontSize: 24,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.white),
                                                ),
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
                                            'A',
                                        style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.user?['name'] ?? 'Admin',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    session.user?['email'] ?? 'admin@lenden.com',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Administrator',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
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

                  // System Management
                  _sectionLabel('System Management'),
                  const SizedBox(height: 8),
                  _buildTile(
                    title: 'System Settings',
                    icon: Icons.settings_system_daydream_outlined,
                    subtitle: 'Configure system-wide settings and preferences',
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AdminSystemSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    title: 'User Management',
                    icon: Icons.people_outline,
                    subtitle: 'Manage and track user accounts',
                    showStatus: true,
                    isActive: true,
                    onTap: () => Navigator.pushNamed(context, '/admin/manage-users'),
                  ),
                  _buildTile(
                    title: 'Analytics & Reports',
                    icon: Icons.analytics_outlined,
                    subtitle: 'Configure analytics and reporting settings',
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminAnalyticsSettingsPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Admin Management
                  _sectionLabel('Admin Management'),
                  const SizedBox(height: 8),
                  _buildTile(
                    title: 'Manage Admins',
                    icon: Icons.admin_panel_settings,
                    subtitle: 'Add or remove admin accounts',
                    showStatus: true,
                    isActive: true,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminManagementPage())),
                  ),

                  const SizedBox(height: 16),

                  // Security & Access
                  _sectionLabel('Security & Access'),
                  const SizedBox(height: 8),
                  _buildTile(
                    title: 'Security Settings',
                    icon: Icons.security_outlined,
                    subtitle: 'Manage admin security and access controls',
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminSecuritySettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    title: 'Admin Notifications',
                    icon: Icons.admin_panel_settings_outlined,
                    subtitle: 'Configure admin-specific notifications',
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminNotificationSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    title: 'Change Password',
                    icon: Icons.lock_outline,
                    subtitle: 'Update your admin account password',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
                  ),
                  _buildTile(
                    title: 'Access Logs',
                    icon: Icons.history,
                    subtitle: 'View system access and activity logs',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AuditLogsPage())),
                  ),

                  const SizedBox(height: 16),

                  // Data Management
                  _sectionLabel('Data Management'),
                  const SizedBox(height: 8),
                  _buildTile(
                    title: 'Backup & Restore',
                    icon: Icons.backup_outlined,
                    subtitle: 'Manage system backups and data restoration',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminBackupRestorePage())),
                  ),
                  _buildTile(
                    title: 'Data Export',
                    icon: Icons.file_download_outlined,
                    subtitle: 'Export system data and reports',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminDataExportPage())),
                  ),
                  _buildTile(
                    title: 'System Maintenance',
                    icon: Icons.build_outlined,
                    subtitle: 'Perform system maintenance tasks',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminSystemMaintenancePage())),
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
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text(
                        'Logout',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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

  Widget _buildTile({
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
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
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

class _AdminTopWaveClipper extends CustomClipper<Path> {
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
