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
import '../user/budget/lending_budget_page.dart';
import '../user/calendar/due_date_calendar_page.dart';
import '../user/statements/export_statement_page.dart';
import 'app_lock_setup_page.dart';
import 'set_wallet_pin_page.dart';
import '../utils/theme_provider.dart';
import '../utils/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    final t = AppLocalizations.of(context).t;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('settings')),
      body: Stack(
        children: [
          cyanWaveHeader(context, height: context.sh(156)),
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
                      color: AppThemeColors.tinted(context,
                          light: AppColors.warmCardBg,
                          dark: const Color(0xFF2A2218)),
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
                                  session.user?['name'] ?? t('user_fallback'),
                                  style: TextStyle(
                                    fontSize: context.sp(16),
                                    fontWeight: FontWeight.bold,
                                    color: AppThemeColors.primaryText(context),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  session.user?['email'] ?? 'user@example.com',
                                  style: TextStyle(
                                    fontSize: context.sp(13),
                                    color: AppThemeColors.secondaryText(context),
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
                                        t('alternative_email_set'),
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
                  sectionLabel(t('account_settings')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: t('change_password'),
                    icon: Icons.lock_outline,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ChangePasswordPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: session.user?['altEmail'] != null &&
                            (session.user!['altEmail'] as String).isNotEmpty
                        ? t('change_alternative_email')
                        : t('add_alternative_email'),
                    icon: Icons.email_outlined,
                    subtitle: session.user?['altEmail'] != null &&
                            (session.user!['altEmail'] as String).isNotEmpty
                        ? session.user!['altEmail'] as String
                        : t('add_backup_email_for_account_recovery'),
                    showStatus: true,
                    isActive: session.user?['altEmail'] != null &&
                        (session.user!['altEmail'] as String).isNotEmpty,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AlternativeEmailPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: t('account_information'),
                    icon: Icons.person_outline,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AccountSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: t('app_lock'),
                    icon: Icons.lock_outline,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AppLockSetupPage()))
                        .then((_) => setState(() {})),
                  ),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: t('wallet_transaction_pin_label'),
                    icon: Icons.dialpad_rounded,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const SetWalletPinPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Preferences
                  sectionLabel(t('preferences')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: t('notification_settings'),
                    icon: Icons.notifications_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const NotificationSettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: t('privacy_settings'),
                    icon: Icons.privacy_tip_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PrivacySettingsPage()))
                        .then((_) => setState(() {})),
                  ),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      final t = AppLocalizations.of(context).t;
                      final modeLabel = {
                        ThemeMode.system: t('system_default'),
                        ThemeMode.light: t('light'),
                        ThemeMode.dark: t('dark'),
                      }[themeProvider.themeMode]!;
                      return _buildTile(
                        context,
                        title: t('dark_mode'),
                        icon: Icons.dark_mode_outlined,
                        subtitle: modeLabel,
                        onTap: () async {
                          final selected = await showDialog<ThemeMode>(
                            context: context,
                            builder: (context) => SimpleDialog(
                              title: Text(t('dark_mode')),
                              children: [
                                for (final mode in ThemeMode.values)
                                  RadioListTile<ThemeMode>(
                                    title: Text({
                                      ThemeMode.system: t('system_default'),
                                      ThemeMode.light: t('light'),
                                      ThemeMode.dark: t('dark'),
                                    }[mode]!),
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
                        context,
                        title: t('language'),
                        icon: Icons.language_outlined,
                        subtitle: label,
                        onTap: () async {
                          final selected = await showDialog<String?>(
                            context: context,
                            builder: (context) => SimpleDialog(
                              title: Text(t('language')),
                              children: [
                                RadioListTile<String?>(
                                  title: Text(t('system_default')),
                                  value: null,
                                  groupValue: current,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => Navigator.pop(context, v),
                                ),
                                RadioListTile<String?>(
                                  title: Text(t('english')),
                                  value: 'en',
                                  groupValue: current,
                                  activeColor: AppColors.cyan,
                                  onChanged: (v) => Navigator.pop(context, v),
                                ),
                                RadioListTile<String?>(
                                  title: Text(t('hindi')),
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
                  _buildTile(
                    context,
                    title: t('monthly_lending_budget'),
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const LendingBudgetPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: t('due_date_calendar'),
                    icon: Icons.calendar_month_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const DueDateCalendarPage()))
                        .then((_) => setState(() {})),
                  ),
                  _buildTile(
                    context,
                    title: t('export_statement'),
                    icon: Icons.download_outlined,
                    onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const ExportStatementPage()))
                        .then((_) => setState(() {})),
                  ),

                  const SizedBox(height: 16),

                  // Support & About
                  sectionLabel(t('support_and_about')),
                  const SizedBox(height: 8),
                  _buildTile(
                    context,
                    title: t('help_and_support'),
                    icon: Icons.help_outline,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => HelpSupportPage())),
                  ),
                  _buildTile(
                    context,
                    title: t('about_lenden'),
                    icon: Icons.info_outline,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AboutPage())),
                  ),
                  _buildTile(
                    context,
                    title: t('terms_of_service'),
                    icon: Icons.description_outlined,
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const TermsOfServicePage())),
                  ),
                  _buildTile(
                    context,
                    title: t('privacy_policy'),
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
                        t('logout'),
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
                          fontSize: context.sp(15),
                          fontWeight: FontWeight.w500,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: context.sp(11),
                              color: AppThemeColors.secondaryText(context)),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios,
                    color: AppThemeColors.mutedText(context), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
