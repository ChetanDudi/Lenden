import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import 'admin_system_settings_page.dart';
import 'admin_analytics_settings_page.dart';
import 'admin_security_settings_page.dart';
import 'admin_notification_settings_page.dart';
import 'admin_management_page.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  @override
  void initState() {
    super.initState();
    // No need to refresh on init as the session should already have user data
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Admin Settings',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Admin Profile Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
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
                                            'A',
                                        style: const TextStyle(
                                          fontSize: 24,
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
                                'A',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          session.user?['email'] ?? 'admin@lenden.com',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Administrator',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Color(0xFF00B4D8)),
                    onPressed: () {
                      Navigator.pushNamed(context, '/profile');
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // System Management Section
            _buildSettingsSection(
              context,
              'System Management',
              [
                _buildSettingsTile(
                  context,
                  'System Settings',
                  Icons.settings_system_daydream_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminSystemSettingsPage(),
                      ),
                    ).then((_) => setState(() {}));
                  },
                  subtitle: 'Configure system-wide settings and preferences',
                ),
                _buildSettingsTile(
                  context,
                  'User Management',
                  Icons.people_outline,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.pushNamed(context, '/admin/manage-users');
                  },
                  subtitle: 'Manage and track user accounts',
                  showStatus: true,
                  isActive: true,
                ),
                _buildSettingsTile(
                  context,
                  'Analytics & Reports',
                  Icons.analytics_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const AdminAnalyticsSettingsPage(),
                      ),
                    ).then((_) => setState(() {}));
                  },
                  subtitle: 'Configure analytics and reporting settings',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Admin Management Section
            _buildSettingsSection(
              context,
              'Admin Management',
              [
                _buildSettingsTile(
                  context,
                  'Manage Admins',
                  Icons.admin_panel_settings,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminManagementPage(),
                      ),
                    );
                  },
                  subtitle: 'Add or remove admin accounts',
                  showStatus: true,
                  isActive: true,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Security & Access Section
            _buildSettingsSection(
              context,
              'Security & Access',
              [
                _buildSettingsTile(
                  context,
                  'Security Settings',
                  Icons.security_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminSecuritySettingsPage(),
                      ),
                    ).then((_) => setState(() {}));
                  },
                  subtitle: 'Manage admin security and access controls',
                ),
                _buildSettingsTile(
                  context,
                  'Admin Notifications',
                  Icons.admin_panel_settings_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const AdminNotificationSettingsPage(),
                      ),
                    ).then((_) => setState(() {}));
                  },
                  subtitle: 'Configure admin-specific notifications',
                ),
                _buildSettingsTile(
                  context,
                  'Access Logs',
                  Icons.history,
                  Icons.arrow_forward_ios,
                  () {
                    // TODO: Implement access logs
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Access Logs coming soon!')),
                    );
                  },
                  subtitle: 'View system access and activity logs',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Data Management Section
            _buildSettingsSection(
              context,
              'Data Management',
              [
                _buildSettingsTile(
                  context,
                  'Backup & Restore',
                  Icons.backup_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    // TODO: Implement backup and restore
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Backup & Restore coming soon!')),
                    );
                  },
                  subtitle: 'Manage system backups and data restoration',
                ),
                _buildSettingsTile(
                  context,
                  'Data Export',
                  Icons.file_download_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    // TODO: Implement data export
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Data Export coming soon!')),
                    );
                  },
                  subtitle: 'Export system data and reports',
                ),
                _buildSettingsTile(
                  context,
                  'System Maintenance',
                  Icons.build_outlined,
                  Icons.arrow_forward_ios,
                  () {
                    // TODO: Implement system maintenance
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('System Maintenance coming soon!')),
                    );
                  },
                  subtitle: 'Perform system maintenance tasks',
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  _showLogoutDialog(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Logout',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(
      BuildContext context, String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF00B4D8),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context,
    String title,
    IconData leadingIcon,
    IconData trailingIcon,
    VoidCallback onTap, {
    String? subtitle,
    bool showStatus = false,
    bool isActive = false,
  }) {
    return ListTile(
      leading: Stack(
        children: [
          Icon(
            leadingIcon,
            color: const Color(0xFF00B4D8),
            size: 24,
          ),
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
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            )
          : null,
      trailing: Icon(
        trailingIcon,
        color: Colors.grey,
        size: 16,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Logout',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          content: const Text(
            'Are you sure you want to logout?',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                final session =
                    Provider.of<SessionProvider>(context, listen: false);
                session.logout();
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed('/');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
}
