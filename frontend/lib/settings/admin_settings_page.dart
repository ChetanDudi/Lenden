import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
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
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_provider.dart';
import '../utils/locale_provider.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final t = AppLocalizations.of(context).t;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('admin_settings')),
      body: Stack(
        children: [
          cyanWaveHeader(context, height: context.sh(150)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Admin Profile Card
                  tricolorBorder(
                    radius: 18,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      color: AppThemeColors.cardBg(context),
                      child: Row(
                        children: [
                          tricolorCircleAvatar(
                            avatarRadius: 30,
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.user?['name'] ?? 'Admin',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppThemeColors.primaryText(context)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  session.user?['email'] ?? 'admin@lenden.com',
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: AppThemeColors.secondaryText(context)),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    t('administrator'),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
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

                  // Preferences
                  sectionLabel(t('preferences')),
                  const SizedBox(height: 8),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      final t = AppLocalizations.of(context).t;
                      final modeLabel = {
                        ThemeMode.system: t('system_default'),
                        ThemeMode.light: t('light'),
                        ThemeMode.dark: t('dark'),
                      }[themeProvider.themeMode]!;
                      return _buildTile(
                        context: context,
                        title: t('dark_mode'),
                        icon: Icons.dark_mode_outlined,
                        subtitle: modeLabel,
                        onTap: () async {
                          final selected = await showDialog<ThemeMode>(
                            context: context,
                            builder: (context) => SimpleDialog(
                              backgroundColor: AppThemeColors.cardBg(context),
                              title: Text(t('dark_mode'),
                                  style: TextStyle(
                                      color: AppThemeColors.primaryText(context))),
                              children: [
                                for (final mode in ThemeMode.values)
                                  RadioListTile<ThemeMode>(
                                    title: Text(
                                      {
                                        ThemeMode.system: t('system_default'),
                                        ThemeMode.light: t('light'),
                                        ThemeMode.dark: t('dark'),
                                      }[mode]!,
                                      style: TextStyle(
                                          color: AppThemeColors.primaryText(context)),
                                    ),
                                    value: mode,
                                    groupValue: themeProvider.themeMode,
                                    activeColor: AppColors.cyan,
                                    onChanged: (v) => Navigator.pop(context, v),
                                  ),
                              ],
                            ),
                          );
                          if (selected != null) {
                            await themeProvider.setThemeMode(selected);
                          }
                        },
                      );
                    },
                  ),
                  Consumer<LocaleProvider>(
                    builder: (context, localeProvider, _) {
                      final t = AppLocalizations.of(context).t;
                      final current = localeProvider.locale?.languageCode;
                      final label = current == 'hi'
                          ? t('hindi')
                          : current == 'en'
                              ? t('english')
                              : t('system_default');
                      return _buildTile(
                        context: context,
                        title: t('language'),
                        icon: Icons.language_outlined,
                        subtitle: label,
                        onTap: () async {
                          final selected = await showDialog<String?>(
                            context: context,
                            builder: (context) => SimpleDialog(
                              backgroundColor: AppThemeColors.cardBg(context),
                              title: Text(t('language'),
                                  style: TextStyle(
                                      color: AppThemeColors.primaryText(context))),
                              children: [
                                RadioListTile<String?>(
                                  title: Text(t('system_default'),
                                      style: TextStyle(
                                          color: AppThemeColors.primaryText(context))),
                                  value: null,
                                  groupValue: current,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => Navigator.pop(context, v),
                                ),
                                RadioListTile<String?>(
                                  title: Text(t('english'),
                                      style: TextStyle(
                                          color: AppThemeColors.primaryText(context))),
                                  value: 'en',
                                  groupValue: current,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => Navigator.pop(context, v),
                                ),
                                RadioListTile<String?>(
                                  title: Text(t('hindi'),
                                      style: TextStyle(
                                          color: AppThemeColors.primaryText(context))),
                                  value: 'hi',
                                  groupValue: current,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => Navigator.pop(context, v),
                                ),
                              ],
                            ),
                          );
                          await localeProvider.setLocale(
                              selected == null ? null : Locale(selected));
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // System Management
                  sectionLabel(t('system_management')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context: context,
                    title: t('system_settings'),
                    icon: Icons.settings_system_daydream_outlined,
                    subtitle: t('system_settings_desc'),
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AdminSystemSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context: context,
                    title: t('manage_users'),
                    icon: Icons.people_outline,
                    subtitle: t('user_management_desc'),
                    showStatus: true,
                    isActive: true,
                    onTap: () => Navigator.pushNamed(context, '/admin/manage-users'),
                  ),
                  _buildTile(
                    context: context,
                    title: t('analytics_and_reports'),
                    icon: Icons.analytics_outlined,
                    subtitle: t('analytics_and_reports_desc'),
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminAnalyticsSettingsPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Admin Management
                  sectionLabel(t('admin_management')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context: context,
                    title: t('manage_admins'),
                    icon: Icons.admin_panel_settings,
                    subtitle: t('manage_admins_desc'),
                    showStatus: true,
                    isActive: true,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminManagementPage())),
                  ),

                  const SizedBox(height: 16),

                  // Security & Access
                  sectionLabel(t('security_and_access')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context: context,
                    title: t('security_settings'),
                    icon: Icons.security_outlined,
                    subtitle: t('security_settings_desc'),
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminSecuritySettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context: context,
                    title: t('admin_notifications'),
                    icon: Icons.admin_panel_settings_outlined,
                    subtitle: t('admin_notifications_desc'),
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(
                                builder: (_) => const AdminNotificationSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context: context,
                    title: t('change_password'),
                    icon: Icons.lock_outline,
                    subtitle: t('change_password_desc'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
                  ),
                  _buildTile(
                    context: context,
                    title: t('access_logs'),
                    icon: Icons.history,
                    subtitle: t('access_logs_desc'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AuditLogsPage())),
                  ),

                  const SizedBox(height: 16),

                  // Data Management
                  sectionLabel(t('data_management')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context: context,
                    title: t('backup_and_restore'),
                    icon: Icons.backup_outlined,
                    subtitle: t('backup_and_restore_desc'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminBackupRestorePage())),
                  ),
                  _buildTile(
                    context: context,
                    title: t('data_export'),
                    icon: Icons.file_download_outlined,
                    subtitle: t('data_export_desc'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminDataExportPage())),
                  ),
                  _buildTile(
                    context: context,
                    title: t('system_maintenance'),
                    icon: Icons.build_outlined,
                    subtitle: t('system_maintenance_desc'),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminSystemMaintenancePage())),
                  ),

                  const SizedBox(height: 24),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => showLogoutDialog(context, onConfirm: () {
                        final session = Provider.of<SessionProvider>(context, listen: false);
                        session.logout();
                        Navigator.of(context).pushReplacementNamed('/');
                      }),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        t('logout'),
                        style: const TextStyle(
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

  Widget _buildTile({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    String? subtitle,
    bool showStatus = false,
    bool isActive = false,
  }) {
    return tricolorBorder(
      margin: const EdgeInsets.only(bottom: 10),
      radius: 16,
      child: Material(
        color: AppThemeColors.cardBg(context),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppThemeColors.secondaryText(context))),
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
