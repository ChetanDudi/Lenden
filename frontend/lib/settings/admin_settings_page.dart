import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../widgets/currency_display.dart';
import '../widgets/search_tab_bar.dart';
import 'admin_system_settings_page.dart';
import 'admin_analytics_settings_page.dart';
import 'admin_security_settings_page.dart';
import 'admin_notification_settings_page.dart';
import 'admin_management_page.dart';
import '../password_management/change_password_page.dart';
import '../admin/audit/audit_logs_page.dart';
import '../admin/coin_pricing/manage_coin_pricing_page.dart';
import '../admin/currency_conversion/manage_currency_conversions_page.dart';
import '../admin/digitise/manage_gift_cards_page.dart';
import '../admin/digitise/manage_offers_page.dart';
import '../admin/digitise/manage_referral_settings_page.dart';
import '../admin/digitise/manage_subscriptions_page.dart';
import '../admin/disputes/manage_disputes_page.dart';
import '../admin/disputes/fraud_alerts_page.dart';
import '../admin/rating/admin_ratings_page.dart';
import '../admin/track_users/track_user_activity_page.dart';
import '../admin/support/admin_feedbacks_page.dart';
import '../admin/support/contact_messages_page.dart';
import '../admin/insights/admin_insights_page.dart';
import 'admin_backup_restore_page.dart';
import 'admin_data_export_page.dart';
import 'admin_system_maintenance_page.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';
import '../utils/theme_provider.dart';
import '../utils/locale_provider.dart';
import '../utils/currency_provider.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Dialog helpers ────────────────────────────────────────────────────────

  Future<void> _showThemePicker() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dctx) {
        Widget optTile(ThemeMode mode, String label, IconData icon) {
          final sel = mode == themeProvider.themeMode;
          return GestureDetector(
            onTap: () => Navigator.pop(dctx, mode),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel ? AppColors.cyan.withValues(alpha: 0.08) : AppThemeColors.scaffoldBg(dctx),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? AppColors.cyan : AppThemeColors.border(dctx), width: sel ? 1.5 : 1.0),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.cyan.withValues(alpha: 0.12) : AppThemeColors.cardBg(dctx),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: sel ? AppColors.cyan : AppThemeColors.secondaryText(dctx), size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(
                  fontSize: 15, fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? AppThemeColors.primaryText(dctx) : AppThemeColors.secondaryText(dctx),
                ))),
                Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx), size: 22),
              ]),
            ),
          );
        }
        return Dialog(
          backgroundColor: AppThemeColors.cardBg(dctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.dark_mode_outlined, color: AppColors.cyan, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t('dark_mode'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(dctx)))),
              ]),
              const SizedBox(height: 16),
              optTile(ThemeMode.system, t('system_default'), Icons.brightness_auto_rounded),
              const SizedBox(height: 10),
              optTile(ThemeMode.light, t('light'), Icons.light_mode_rounded),
              const SizedBox(height: 10),
              optTile(ThemeMode.dark, t('dark'), Icons.dark_mode_rounded),
            ]),
          ),
        );
      },
    );
    if (selected != null) await themeProvider.setThemeMode(selected);
  }

  Future<void> _showLanguagePicker() async {
    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final current = localeProvider.locale?.languageCode;
    final selected = await showDialog<String?>(
      context: context,
      builder: (dctx) {
        Widget langTile(String? value, String label, IconData icon) {
          final sel = value == current;
          return GestureDetector(
            onTap: () => Navigator.pop(dctx, value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: sel ? AppColors.cyan.withValues(alpha: 0.08) : AppThemeColors.scaffoldBg(dctx),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? AppColors.cyan : AppThemeColors.border(dctx), width: sel ? 1.5 : 1.0),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.cyan.withValues(alpha: 0.12) : AppThemeColors.cardBg(dctx),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: sel ? AppColors.cyan : AppThemeColors.secondaryText(dctx), size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: TextStyle(
                  fontSize: 15, fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                  color: sel ? AppThemeColors.primaryText(dctx) : AppThemeColors.secondaryText(dctx),
                ))),
                Icon(sel ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: sel ? AppColors.cyan : AppThemeColors.border(dctx), size: 22),
              ]),
            ),
          );
        }
        return Dialog(
          backgroundColor: AppThemeColors.cardBg(dctx),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.language_outlined, color: AppColors.cyan, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(t('language'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppThemeColors.primaryText(dctx)))),
              ]),
              const SizedBox(height: 16),
              langTile(null, t('system_default'), Icons.phone_android_rounded),
              const SizedBox(height: 10),
              langTile('en', t('english'), Icons.language_rounded),
              const SizedBox(height: 10),
              langTile('hi', t('hindi'), Icons.translate_rounded),
            ]),
          ),
        );
      },
    );
    await localeProvider.setLocale(selected == null ? null : Locale(selected));
  }

  void _showCurrencyPicker() {
    final currencyProvider = Provider.of<CurrencyProvider>(context, listen: false);
    CurrencyProvider.showPickerSheet(
      context,
      currencies: kCurrencyFallbacks,
      selected: currencyProvider.defaultCurrency,
      onSelect: (code) => currencyProvider.setDefaultCurrency(code),
    );
  }

  // ── Searchable entries ────────────────────────────────────────────────────

  List<_AdminEntry> get _entries => [
    _AdminEntry('Dark Mode', ['theme', 'dark mode', 'appearance', 'light', 'dark'], Icons.dark_mode_outlined, action: (_) => _showThemePicker()),
    _AdminEntry('Language', ['language', 'hindi', 'english', 'locale'], Icons.language_outlined, action: (_) => _showLanguagePicker()),
    _AdminEntry('Default Currency', ['currency', 'display currency', 'inr', 'usd'], Icons.currency_exchange_rounded, action: (_) => _showCurrencyPicker()),
    _AdminEntry('System Settings', ['system', 'configuration', 'app settings', 'limits'], Icons.settings_system_daydream_outlined, builder: (_) => const AdminSystemSettingsPage()),
    _AdminEntry('Manage Users', ['users', 'user list', 'user management', 'accounts'], Icons.people_outline, route: '/admin/manage-users'),
    _AdminEntry('Analytics & Reports', ['analytics', 'reports', 'metrics', 'data'], Icons.analytics_outlined, builder: (_) => const AdminAnalyticsSettingsPage()),
    _AdminEntry('Manage Admins', ['admins', 'roles', 'permissions', 'admin list'], Icons.admin_panel_settings, builder: (_) => const AdminManagementPage()),
    _AdminEntry('Security Settings', ['security', 'ip whitelist', 'geo restrictions', 'password policy'], Icons.security_outlined, builder: (_) => const AdminSecuritySettingsPage()),
    _AdminEntry('Admin Notifications', ['notifications', 'alerts', 'push', 'email alerts'], Icons.notifications_outlined, builder: (_) => const AdminNotificationSettingsPage()),
    _AdminEntry('Change Password', ['password', 'change password', 'credentials'], Icons.lock_outline, builder: (_) => const ChangePasswordPage()),
    _AdminEntry('Access Logs', ['logs', 'audit', 'activity', 'history'], Icons.history, builder: (_) => const AuditLogsPage()),
    _AdminEntry('Fraud Alerts', ['fraud', 'suspicious', 'security', 'alerts'], Icons.warning_amber_outlined, builder: (_) => const FraudAlertsPage()),
    _AdminEntry('Disputes', ['disputes', 'claims', 'issues', 'refunds'], Icons.gavel_outlined, builder: (_) => const ManageDisputesPage()),
    _AdminEntry('Subscription Plans', ['subscriptions', 'plans', 'premium', 'features'], Icons.workspace_premium_outlined, builder: (_) => AdminFeaturesPage()),
    _AdminEntry('Coin Pricing', ['coins', 'pricing', 'lenden coins', 'credits'], Icons.monetization_on_outlined, builder: (_) => ManageCoinPricingPage()),
    _AdminEntry('Currency Conversions', ['currency', 'exchange rate', 'conversion'], Icons.currency_exchange_rounded, builder: (_) => const ManageCurrencyConversionsPage()),
    _AdminEntry('Gift Cards', ['gift cards', 'vouchers', 'promo codes'], Icons.card_giftcard_outlined, builder: (_) => ManageGiftCardsPage()),
    _AdminEntry('Offers', ['offers', 'promotions', 'deals', 'discounts'], Icons.local_offer_outlined, builder: (_) => const ManageOffersPage()),
    _AdminEntry('Referral Settings', ['referral', 'invite', 'rewards', 'refer'], Icons.redeem_outlined, builder: (_) => const ReferralSettingsPage()),
    _AdminEntry('Contact Messages', ['contact', 'messages', 'inquiries', 'support tickets'], Icons.contact_mail_outlined, builder: (_) => const ContactMessagesPage()),
    _AdminEntry('User Feedbacks', ['feedback', 'suggestions', 'reviews', 'reports'], Icons.feedback_outlined, builder: (_) => const AdminFeedbacksPage()),
    _AdminEntry('User Ratings', ['ratings', 'reviews', 'stars', 'scores'], Icons.star_rate_outlined, builder: (_) => const AdminRatingsPage()),
    _AdminEntry('Track Users', ['track', 'user activity', 'monitor', 'behavior'], Icons.track_changes_outlined, builder: (_) => TrackUserActivityPage()),
    _AdminEntry('Admin Insights', ['insights', 'intelligence', 'summary', 'dashboard analytics'], Icons.insights_outlined, builder: (_) => AdminInsightsPage()),
    _AdminEntry('Backup & Restore', ['backup', 'restore', 'data recovery', 'snapshot'], Icons.backup_outlined, builder: (_) => const AdminBackupRestorePage()),
    _AdminEntry('Data Export', ['export', 'download', 'csv', 'data dump'], Icons.file_download_outlined, builder: (_) => const AdminDataExportPage()),
    _AdminEntry('System Maintenance', ['maintenance', 'cleanup', 'clear cache', 'restart'], Icons.build_outlined, builder: (_) => const AdminSystemMaintenancePage()),
  ];

  Widget _buildSearchResults() {
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
            style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: context.sp(14)),
          ),
        ),
      );
    }

    return _sectionCard('Search Results', results.map((e) => _tile(
      title: e.title,
      icon: e.icon,
      onTap: () {
        if (e.action != null) e.action!(context);
        else if (e.builder != null) Navigator.push(context, MaterialPageRoute(builder: e.builder!));
        else if (e.route != null) Navigator.pushNamed(context, e.route!);
      },
    )).toList());
  }

  @override
  Widget build(BuildContext context) {
    final session = Provider.of<SessionProvider>(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('admin_settings')),
      body: Stack(
        children: [
          cyanWaveHeader(context, height: context.sh(156)),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search bar
                  AppSearchBar(
                    controller: _searchCtrl,
                    hintText: 'Search admin settings...',
                    onChanged: (v) => setState(() => _query = v.toLowerCase().trim()),
                    margin: const EdgeInsets.fromLTRB(0, 8, 0, 16),
                  ),

                  if (_query.isNotEmpty) ...[
                    _buildSearchResults(),
                  ] else ...[

                  // ── Admin Profile Card ─────────────────────────────────────
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
                                            width: 60, height: 60, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Text(
                                              (session.user?['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'A',
                                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                          )
                                        : Image.memory(session.user!['profileImage'], width: 60, height: 60, fit: BoxFit.cover),
                                  )
                                : Text(
                                    (session.user?['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'A',
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                session.user?['name'] ?? 'Admin',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                session.user?['email'] ?? 'admin@lenden.com',
                                style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  t('administrator'),
                                  style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ]),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit, color: AppColors.cyan),
                            onPressed: () => Navigator.pushNamed(context, '/profile'),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── PREFERENCES ───────────────────────────────────────────
                  _sectionCard(t('preferences'), [
                    Consumer<ThemeProvider>(builder: (ctx, tp, _) {
                      final modeLabel = {
                        ThemeMode.system: t('system_default'),
                        ThemeMode.light: t('light'),
                        ThemeMode.dark: t('dark'),
                      }[tp.themeMode]!;
                      return _tile(title: t('dark_mode'), icon: Icons.dark_mode_outlined, subtitle: modeLabel, onTap: _showThemePicker);
                    }),
                    Consumer<LocaleProvider>(builder: (ctx, lp, _) {
                      final c = lp.locale?.languageCode;
                      final label = c == 'hi' ? t('hindi') : c == 'en' ? t('english') : t('system_default');
                      return _tile(title: t('language'), icon: Icons.language_outlined, subtitle: label, onTap: _showLanguagePicker);
                    }),
                    Consumer<CurrencyProvider>(builder: (ctx, cp, _) {
                      return _tile(title: t('default_currency'), icon: Icons.currency_exchange_rounded, subtitle: cp.defaultCurrency, onTap: _showCurrencyPicker);
                    }),
                  ]),

                  // ── SYSTEM MANAGEMENT ─────────────────────────────────────
                  _sectionCard(t('system_management'), [
                    _tile(
                      title: t('system_settings'), icon: Icons.settings_system_daydream_outlined,
                      subtitle: t('system_settings_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSystemSettingsPage())).then((_) => setState(() {})),
                    ),
                    _tile(
                      title: t('manage_users'), icon: Icons.people_outline,
                      subtitle: t('user_management_desc'), showStatus: true, isActive: true,
                      onTap: () => Navigator.pushNamed(context, '/admin/manage-users'),
                    ),
                    _tile(
                      title: t('analytics_and_reports'), icon: Icons.analytics_outlined,
                      subtitle: t('analytics_and_reports_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAnalyticsSettingsPage())).then((_) => setState(() {})),
                    ),
                    _tile(
                      title: t('admin_insights'), icon: Icons.insights_outlined,
                      subtitle: t('admin_insights_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminInsightsPage())),
                    ),
                    _tile(
                      title: t('track_users'), icon: Icons.track_changes_outlined,
                      subtitle: t('track_users_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackUserActivityPage())),
                    ),
                  ]),

                  // ── ADMIN MANAGEMENT ──────────────────────────────────────
                  _sectionCard(t('admin_management'), [
                    _tile(
                      title: t('manage_admins'), icon: Icons.admin_panel_settings,
                      subtitle: t('manage_admins_desc'), showStatus: true, isActive: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminManagementPage())),
                    ),
                  ]),

                  // ── SECURITY & ACCESS ─────────────────────────────────────
                  _sectionCard(t('security_and_access'), [
                    _tile(
                      title: t('security_settings'), icon: Icons.security_outlined,
                      subtitle: t('security_settings_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSecuritySettingsPage())).then((_) => setState(() {})),
                    ),
                    _tile(
                      title: t('admin_notifications'), icon: Icons.admin_panel_settings_outlined,
                      subtitle: t('admin_notifications_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationSettingsPage())).then((_) => setState(() {})),
                    ),
                    _tile(
                      title: t('change_password'), icon: Icons.lock_outline,
                      subtitle: t('change_password_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordPage())),
                    ),
                    _tile(
                      title: t('access_logs'), icon: Icons.history,
                      subtitle: t('access_logs_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AuditLogsPage())),
                    ),
                    _tile(
                      title: t('fraud_alerts'), icon: Icons.warning_amber_outlined,
                      subtitle: t('fraud_alerts_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FraudAlertsPage())),
                    ),
                    _tile(
                      title: t('disputes'), icon: Icons.gavel_outlined,
                      subtitle: t('disputes_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageDisputesPage())),
                    ),
                  ]),

                  // ── MONETIZATION ──────────────────────────────────────────
                  _sectionCard(t('monetization'), [
                    _tile(
                      title: t('subscription_plans'), icon: Icons.workspace_premium_outlined,
                      subtitle: t('subscription_plans_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminFeaturesPage())),
                    ),
                    _tile(
                      title: t('coin_pricing'), icon: Icons.monetization_on_outlined,
                      subtitle: t('coin_pricing_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageCoinPricingPage())),
                    ),
                    _tile(
                      title: t('currency_conversions'), icon: Icons.currency_exchange_rounded,
                      subtitle: t('currency_conversions_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageCurrencyConversionsPage())),
                    ),
                    _tile(
                      title: t('gift_cards'), icon: Icons.card_giftcard_outlined,
                      subtitle: t('gift_cards_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageGiftCardsPage())),
                    ),
                    _tile(
                      title: t('offers'), icon: Icons.local_offer_outlined,
                      subtitle: t('offers_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageOffersPage())),
                    ),
                    _tile(
                      title: t('referral_settings'), icon: Icons.redeem_outlined,
                      subtitle: t('referral_settings_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReferralSettingsPage())),
                    ),
                  ]),

                  // ── CONTENT & SUPPORT ─────────────────────────────────────
                  _sectionCard(t('content_and_support'), [
                    _tile(
                      title: t('contact_messages'), icon: Icons.contact_mail_outlined,
                      subtitle: t('contact_messages_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactMessagesPage())),
                    ),
                    _tile(
                      title: t('user_feedbacks'), icon: Icons.feedback_outlined,
                      subtitle: t('user_feedbacks_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminFeedbacksPage())),
                    ),
                    _tile(
                      title: t('user_ratings'), icon: Icons.star_rate_outlined,
                      subtitle: t('user_ratings_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRatingsPage())),
                    ),
                  ]),

                  // ── DATA MANAGEMENT ───────────────────────────────────────
                  _sectionCard(t('data_management'), [
                    _tile(
                      title: t('backup_and_restore'), icon: Icons.backup_outlined,
                      subtitle: t('backup_and_restore_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBackupRestorePage())),
                    ),
                    _tile(
                      title: t('data_export'), icon: Icons.file_download_outlined,
                      subtitle: t('data_export_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDataExportPage())),
                    ),
                    _tile(
                      title: t('system_maintenance'), icon: Icons.build_outlined,
                      subtitle: t('system_maintenance_desc'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminSystemMaintenancePage())),
                    ),
                  ]),

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
                      child: Text(t('logout'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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

  Widget _sectionCard(String title, List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeColors.border(context).withValues(alpha: 0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                  width: 3, height: 13,
                  decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 8),
                Text(title.toUpperCase(), style: TextStyle(
                  fontSize: context.sp(10), fontWeight: FontWeight.bold,
                  color: AppColors.cyan, letterSpacing: 1.0,
                )),
              ]),
            ),
            Divider(height: 1, color: AppThemeColors.border(context).withValues(alpha: 0.4)),
            ...tiles.asMap().entries.map((e) => Column(children: [
              if (e.key > 0) Divider(height: 1, indent: 68, endIndent: 16, color: AppThemeColors.border(context).withValues(alpha: 0.3)),
              e.value,
            ])),
            const SizedBox(height: 4),
          ]),
        ),
      ),
    );
  }

  Widget _tile({
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
            Stack(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: AppColors.cyan.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: AppColors.cyan, size: 18),
              ),
              if (showStatus)
                Positioned(
                  right: 0, top: 0,
                  child: Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(
                  fontSize: context.sp(15), fontWeight: FontWeight.w500,
                  color: AppThemeColors.primaryText(context),
                )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: context.sp(11), color: AppThemeColors.secondaryText(context))),
                ],
              ]),
            ),
            Icon(Icons.arrow_forward_ios, color: AppThemeColors.mutedText(context), size: 16),
          ],
        ),
      ),
    );
  }
}

class _AdminEntry {
  final String title;
  final List<String> keywords;
  final IconData icon;
  final Widget Function(BuildContext)? builder;
  final void Function(BuildContext)? action;
  final String? route;

  const _AdminEntry(this.title, this.keywords, this.icon, {this.builder, this.action, this.route});
}
