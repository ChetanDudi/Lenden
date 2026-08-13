import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../password_management/change_password_page.dart';
import '../password_management/set_password_page.dart';
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
import '../user/calendar/due_date_calendar_page.dart';
import '../user/statements/export_statement_page.dart';
import 'app_lock_setup_page.dart';
import 'set_wallet_pin_page.dart';
import '../utils/theme_provider.dart';
import '../utils/locale_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_helper.dart';
import '../widgets/search_tab_bar.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────

  Future<void> _showThemePicker(BuildContext ctx) async {
    final themeProvider = Provider.of<ThemeProvider>(ctx, listen: false);
    final t = AppLocalizations.of(ctx).t;
    final selected = await showDialog<ThemeMode>(
      context: ctx,
      builder: (dctx) {
        Widget optTile(ThemeMode mode, String label, IconData icon) {
          final sel = mode == themeProvider.themeMode;
          return GestureDetector(
            onTap: () => Navigator.pop(dctx, mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.cyan.withValues(alpha: 0.08)
                    : AppThemeColors.scaffoldBg(dctx),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx),
                    width: sel ? 1.5 : 1.0),
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.cyan.withValues(alpha: 0.12)
                        : AppThemeColors.cardBg(dctx),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      color: sel
                          ? AppColors.cyan
                          : AppThemeColors.secondaryText(dctx),
                      size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w500,
                          color: sel
                              ? AppThemeColors.primaryText(dctx)
                              : AppThemeColors.secondaryText(dctx),
                        ))),
                Icon(
                    sel
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx),
                    size: 22),
              ]),
            ),
          );
        }

        return Dialog(
          backgroundColor: AppThemeColors.cardBg(dctx),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.dark_mode_outlined,
                        color: AppColors.cyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(t('dark_mode'),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.primaryText(dctx)))),
                ]),
                const SizedBox(height: 16),
                optTile(ThemeMode.system, t('system_default'),
                    Icons.brightness_auto_rounded),
                const SizedBox(height: 10),
                optTile(ThemeMode.light, t('light'), Icons.light_mode_rounded),
                const SizedBox(height: 10),
                optTile(ThemeMode.dark, t('dark'), Icons.dark_mode_rounded),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      await themeProvider.setThemeMode(selected);
    }
  }

  Future<void> _showLanguagePicker(BuildContext ctx) async {
    final localeProvider = Provider.of<LocaleProvider>(ctx, listen: false);
    final t = AppLocalizations.of(ctx).t;
    final current = localeProvider.locale?.languageCode;
    final selected = await showDialog<String?>(
      context: ctx,
      builder: (dctx) {
        Widget langTile(String? value, String label, IconData icon) {
          final sel = value == current;
          return GestureDetector(
            onTap: () => Navigator.pop(dctx, value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.cyan.withValues(alpha: 0.08)
                    : AppThemeColors.scaffoldBg(dctx),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx),
                    width: sel ? 1.5 : 1.0),
              ),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.cyan.withValues(alpha: 0.12)
                        : AppThemeColors.cardBg(dctx),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon,
                      color: sel
                          ? AppColors.cyan
                          : AppThemeColors.secondaryText(dctx),
                      size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight:
                              sel ? FontWeight.w600 : FontWeight.w500,
                          color: sel
                              ? AppThemeColors.primaryText(dctx)
                              : AppThemeColors.secondaryText(dctx),
                        ))),
                Icon(
                    sel
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx),
                    size: 22),
              ]),
            ),
          );
        }

        return Dialog(
          backgroundColor: AppThemeColors.cardBg(dctx),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.language_outlined,
                        color: AppColors.cyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(t('language'),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.primaryText(dctx)))),
                ]),
                const SizedBox(height: 16),
                langTile(null, t('system_default'), Icons.phone_android_rounded),
                const SizedBox(height: 10),
                langTile('en', t('english'), Icons.language_rounded),
                const SizedBox(height: 10),
                langTile('hi', t('hindi'), Icons.translate_rounded),
              ],
            ),
          ),
        );
      },
    );
    await localeProvider.setLocale(
        selected == null ? null : Locale(selected));
  }

  // ── Searchable entries ────────────────────────────────────────────────────

  List<_SettingsEntry> get _entries => [
        _SettingsEntry(
          'Change Password',
          ['password', 'change password', 'security', 'set password', 'lock'],
          Icons.lock_outline,
          action: (ctx) {
            final session = Provider.of<SessionProvider>(ctx, listen: false);
            final isGoogle = session.user?['authProvider'] == 'google';
            final hasPassword = session.user?['hasPassword'] == true;
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => (isGoogle && !hasPassword)
                    ? const SetPasswordPage()
                    : const ChangePasswordPage(),
              ),
            );
          },
        ),
        _SettingsEntry(
          'Alternative Email',
          ['email', 'alternative email', 'backup email', 'recovery', 'change email'],
          Icons.email_outlined,
          builder: (_) => const AlternativeEmailPage(),
        ),
        _SettingsEntry(
          'Account Information',
          ['account', 'account settings', 'profile', 'information', 'personal'],
          Icons.person_outline,
          builder: (_) => const AccountSettingsPage(),
        ),
        _SettingsEntry(
          'App Lock',
          ['app lock', 'lock', 'security', 'pin', 'fingerprint', 'biometric'],
          Icons.lock_outline,
          builder: (_) => const AppLockSetupPage(),
        ),
        _SettingsEntry(
          'Wallet PIN',
          ['wallet', 'pin', 'transaction pin', 'payment pin', 'wallet pin', 'security'],
          Icons.dialpad_rounded,
          builder: (_) => const SetWalletPinPage(),
        ),
        _SettingsEntry(
          'Notification Settings',
          ['notification', 'alerts', 'push', 'reminders'],
          Icons.notifications_outlined,
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Privacy Settings',
          ['privacy', 'visibility', 'who can see', 'private'],
          Icons.privacy_tip_outlined,
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Dark Mode',
          ['dark mode', 'theme', 'appearance', 'light', 'dark', 'display'],
          Icons.dark_mode_outlined,
          action: (ctx) => _showThemePicker(ctx),
        ),
        _SettingsEntry(
          'Language',
          ['language', 'hindi', 'english', 'locale', 'translation'],
          Icons.language_outlined,
          action: (ctx) => _showLanguagePicker(ctx),
        ),
        _SettingsEntry(
          'Due Date Calendar',
          ['due date', 'calendar', 'schedule', 'payment date'],
          Icons.calendar_month_outlined,
          builder: (_) => const DueDateCalendarPage(),
        ),
        _SettingsEntry(
          'Export Statement',
          ['export', 'statement', 'download', 'history', 'transactions'],
          Icons.download_outlined,
          builder: (_) => const ExportStatementPage(),
        ),
        _SettingsEntry(
          'Help & Support',
          ['help', 'support', 'contact', 'faq', 'assistance'],
          Icons.help_outline,
          builder: (_) => HelpSupportPage(),
        ),
        _SettingsEntry(
          'About LenDen',
          ['about', 'lenden', 'version', 'info', 'app info'],
          Icons.info_outline,
          builder: (_) => const AboutPage(),
        ),
        _SettingsEntry(
          'Terms of Service',
          ['terms', 'terms of service', 'legal', 'agreement'],
          Icons.description_outlined,
          builder: (_) => const TermsOfServicePage(),
        ),
        _SettingsEntry(
          'Privacy Policy',
          ['privacy policy', 'data', 'legal', 'policy'],
          Icons.security_outlined,
          builder: (_) => const PrivacyPolicyPage(),
        ),

        // ── Notification Settings sub-items ───────────────────────────────
        _SettingsEntry(
          'Transaction Notifications',
          ['transaction notifications', 'transaction alerts', 'payment notification', 'sent received alert'],
          Icons.receipt_long,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Payment Reminders',
          ['payment reminders', 'due reminders', 'due date alert', 'repayment reminder'],
          Icons.schedule,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Group Notifications',
          ['group notifications', 'group alerts', 'group updates', 'group chat notification'],
          Icons.group_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Chat Notifications',
          ['chat notifications', 'chat alerts', 'message notifications', 'message alerts'],
          Icons.chat_bubble_outline,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Push Notifications',
          ['push notifications', 'app notifications', 'push alerts'],
          Icons.notifications_active_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Email Notifications',
          ['email notifications', 'email alerts', 'notification email'],
          Icons.email_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Notification Sound',
          ['notification sound', 'sound alert', 'audio notification', 'ringtone'],
          Icons.volume_up_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Vibration',
          ['vibration', 'vibrate', 'haptic', 'haptic feedback'],
          Icons.vibration,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Quiet Hours',
          ['quiet hours', 'do not disturb', 'silent mode', 'night mode', 'mute notifications'],
          Icons.bedtime_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Reminder Frequency',
          ['reminder frequency', 'daily weekly monthly', 'how often remind'],
          Icons.repeat,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Subscription Notifications',
          ['subscription notifications', 'subscription alerts', 'plan notification'],
          Icons.workspace_premium_outlined,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),
        _SettingsEntry(
          'Friend Notifications',
          ['friend notifications', 'friend request alert', 'friend alerts'],
          Icons.people_outline,
          parentTitle: 'Notification Settings',
          builder: (_) => const NotificationSettingsPage(),
        ),

        // ── Privacy Settings sub-items ────────────────────────────────────
        _SettingsEntry(
          'Profile Visibility',
          ['profile visibility', 'who can see my profile', 'hide profile', 'public private profile'],
          Icons.visibility_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Transaction History Visibility',
          ['transaction history visibility', 'hide transactions', 'transaction privacy'],
          Icons.history,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Two Factor Authentication',
          ['two factor', '2fa', 'two step verification', 'extra security', 'otp login'],
          Icons.verified_user_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Login Notifications',
          ['login notifications', 'new login alert', 'sign in notification'],
          Icons.notifications_active_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Active Devices',
          ['active devices', 'logged in devices', 'device management', 'logout other devices', 'sessions'],
          Icons.devices,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Session Timeout',
          ['session timeout', 'auto logout', 'automatic sign out', 'stay logged in'],
          Icons.timer_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Contact Sharing',
          ['contact sharing', 'share contacts', 'contacts privacy'],
          Icons.contacts_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Analytics Sharing',
          ['analytics', 'usage data', 'analytics sharing', 'app usage'],
          Icons.analytics_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Export My Data',
          ['export data', 'download my data', 'data export', 'personal data'],
          Icons.download_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
        _SettingsEntry(
          'Deactivate Account',
          ['deactivate account', 'delete account', 'close account', 'remove account'],
          Icons.delete_forever_outlined,
          parentTitle: 'Privacy Settings',
          builder: (_) => const PrivacySettingsPage(),
        ),
      ];

  Widget _buildSearchResults(BuildContext context) {
    final results = _entries.where((e) {
      return e.title.toLowerCase().contains(_query) ||
          e.keywords.any((k) => k.contains(_query));
    }).toList();

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            "No results for '$_query'",
            style: TextStyle(
              color: AppThemeColors.secondaryText(context),
              fontSize: context.sp(14),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: AppThemeColors.cardBg(context),
          child: Column(
            children: results.asMap().entries.map((e) {
              final entry = e.value;
              return Column(children: [
                if (e.key > 0)
                  Divider(
                    height: 1,
                    indent: 68,
                    endIndent: 16,
                    color: AppThemeColors.border(context).withValues(alpha: 0.3),
                  ),
                _buildTile(
                  context,
                  title: entry.title,
                  icon: entry.icon,
                  subtitle: entry.parentTitle != null
                      ? 'in ${entry.parentTitle}'
                      : null,
                  onTap: () {
                    if (entry.action != null) {
                      entry.action!(context);
                    } else if (entry.builder != null) {
                      Navigator.push(context,
                          MaterialPageRoute(builder: entry.builder!));
                    }
                  },
                ),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

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
                  // Search bar — always visible at the top
                  AppSearchBar(
                    controller: _searchCtrl,
                    hintText: 'Search settings...',
                    onChanged: (v) =>
                        setState(() => _query = v.toLowerCase().trim()),
                    margin: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                  ),

                  if (_query.isNotEmpty) ...[
                    // ── Search results ──────────────────────────────────────
                    _buildSearchResults(context),
                  ] else ...[
                    // ── Normal settings content ─────────────────────────────

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
                                        child: session.user!['profileImage']
                                                is String
                                            ? Image.network(
                                                session.user!['profileImage'],
                                                width: 60,
                                                height: 60,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error,
                                                    stackTrace) {
                                                  return Text(
                                                    (session.user?['name']
                                                                as String?)
                                                            ?.substring(0, 1)
                                                            .toUpperCase() ??
                                                        'U',
                                                    style: TextStyle(
                                                      fontSize: context.sp(22),
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      session.user?['email'] ??
                                          'user@example.com',
                                      style: TextStyle(
                                        fontSize: context.sp(13),
                                        color:
                                            AppThemeColors.secondaryText(context),
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                  if ((session.user?['altEmail']?.toString() ??
                                          '')
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle,
                                            size: 12, color: Colors.green),
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
                              icon: const Icon(Icons.edit,
                                  color: AppColors.cyan),
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/profile'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    _settingsSectionCard(t('account_settings'), [
                      Builder(builder: (ctx) {
                        final session =
                            Provider.of<SessionProvider>(context, listen: false);
                        final isGoogle =
                            session.user?['authProvider'] == 'google';
                        final hasPassword =
                            session.user?['hasPassword'] == true;
                        final showSetPassword = isGoogle && !hasPassword;
                        return _buildTile(
                          ctx,
                          title: showSetPassword
                              ? 'Set Password'
                              : t('change_password'),
                          icon: showSetPassword
                              ? Icons.lock_person_rounded
                              : Icons.lock_outline,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => showSetPassword
                                  ? const SetPasswordPage()
                                  : const ChangePasswordPage(),
                            ),
                          ).then((_) {
                            if (mounted) setState(() {});
                          }),
                        );
                      }),
                      _buildTile(
                        context,
                        title: (session.user?['altEmail']?.toString() ?? '')
                                .isNotEmpty
                            ? t('change_alternative_email')
                            : t('add_alternative_email'),
                        icon: Icons.email_outlined,
                        subtitle: (session.user?['altEmail']?.toString() ?? '')
                                .isNotEmpty
                            ? session.user!['altEmail'].toString()
                            : t('add_backup_email_for_account_recovery'),
                        showStatus: true,
                        isActive:
                            (session.user?['altEmail']?.toString() ?? '').isNotEmpty,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AlternativeEmailPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                      _buildTile(
                        context,
                        title: t('account_information'),
                        icon: Icons.person_outline,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AccountSettingsPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                      _buildTile(
                        context,
                        title: t('app_lock'),
                        icon: Icons.lock_outline,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AppLockSetupPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                      _buildTile(
                        context,
                        title: t('wallet_transaction_pin_label'),
                        icon: Icons.dialpad_rounded,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SetWalletPinPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                    ]),

                    _settingsSectionCard(t('preferences'), [
                      _buildTile(
                        context,
                        title: t('notification_settings'),
                        icon: Icons.notifications_outlined,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const NotificationSettingsPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                      _buildTile(
                        context,
                        title: t('privacy_settings'),
                        icon: Icons.privacy_tip_outlined,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const PrivacySettingsPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
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
                            onTap: () => _showThemePicker(context),
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
                            onTap: () => _showLanguagePicker(context),
                          );
                        },
                      ),
                      _buildTile(
                        context,
                        title: t('due_date_calendar'),
                        icon: Icons.calendar_month_outlined,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const DueDateCalendarPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                      _buildTile(
                        context,
                        title: t('export_statement'),
                        icon: Icons.download_outlined,
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ExportStatementPage()))
                            .then((_) {
                          if (mounted) setState(() {});
                        }),
                      ),
                    ]),

                    _settingsSectionCard(t('support_and_about'), [
                      _buildTile(
                        context,
                        title: t('help_and_support'),
                        icon: Icons.help_outline,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => HelpSupportPage())),
                      ),
                      _buildTile(
                        context,
                        title: t('about_lenden'),
                        icon: Icons.info_outline,
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AboutPage())),
                      ),
                      _buildTile(
                        context,
                        title: t('terms_of_service'),
                        icon: Icons.description_outlined,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TermsOfServicePage())),
                      ),
                      _buildTile(
                        context,
                        title: t('privacy_policy'),
                        icon: Icons.security_outlined,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PrivacyPolicyPage())),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Logout Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => showLogoutDialog(context, onConfirm: () {
                          final session = Provider.of<SessionProvider>(context,
                              listen: false);
                          session.logout();
                          Navigator.of(context).pushReplacementNamed('/');
                        }),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.symmetric(
                              vertical: context.sh(14)),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsSectionCard(String title, List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: AppThemeColors.cardBg(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 8),
              child: Row(children: [
                Container(
                  width: 3,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(title.toUpperCase(),
                    style: TextStyle(
                      fontSize: context.sp(10),
                      fontWeight: FontWeight.bold,
                      color: AppColors.cyan,
                      letterSpacing: 1.0,
                    )),
              ]),
            ),
            Divider(
                height: 1,
                color: AppThemeColors.border(context).withValues(alpha: 0.4)),
            ...tiles.asMap().entries.map((e) => Column(children: [
                  if (e.key > 0)
                    Divider(
                      height: 1,
                      indent: 68,
                      endIndent: 16,
                      color: AppThemeColors.border(context)
                          .withValues(alpha: 0.3),
                    ),
                  e.value,
                ])),
            const SizedBox(height: 4),
          ]),
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, color: AppColors.cyan, size: 18),
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
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────

class _SettingsEntry {
  final String title;
  final List<String> keywords;
  final IconData icon;
  final String? parentTitle;
  final Widget Function(BuildContext)? builder;
  final void Function(BuildContext)? action;

  const _SettingsEntry(
    this.title,
    this.keywords,
    this.icon, {
    this.parentTitle,
    this.builder,
    this.action,
  });
}
