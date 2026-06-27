import 'package:flutter/material.dart';
import '../utils/api_client.dart';
import '../utils/csv_utils.dart';
import '../utils/share_utils.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AdminDataExportPage extends StatefulWidget {
  const AdminDataExportPage({super.key});

  @override
  State<AdminDataExportPage> createState() => _AdminDataExportPageState();
}

class _AdminDataExportPageState extends State<AdminDataExportPage> {
  bool _isLoading = false;
  String? _lastExported;

  Future<void> _export(String type, String label, IconData icon) async {
    final t = AppLocalizations.of(context).t;
    setState(() => _isLoading = true);
    String csvBody = '';
    try {
      final response =
          await ApiClient.get('/api/admin/data/export?type=$type');
      if (response.statusCode != 200) {
        if (mounted) {
          showSnack(context, t('export_failed_try_again'), isError: true);
        }
        return;
      }
      csvBody = response.body;
      setState(() => _lastExported = label);
    } catch (e) {
      if (mounted) showSnack(context, '${t('network_error')}: $e', isError: true);
      return;
    } finally {
      setState(() => _isLoading = false);
    }

    if (!mounted) return;
    final parsed = parseCsv(csvBody);
    showCsvBottomSheet(
      context: context,
      label: label,
      icon: icon,
      csvBody: csvBody,
      headers: parsed.headers,
      rows: parsed.rows,
      onShare: () => shareTextFile(
        content: csvBody,
        filename: '${type}_export.csv',
        subject: 'LenDen Export — ${type}_export.csv',
        text: t('exported_data_from_admin_panel'),
      ),
    );
  }

  Widget _exportCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
    required Color accent,
  }) {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: AppThemeColors.secondaryText(context),
                          fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _export(type, title, icon),
              icon: const Icon(Icons.download_rounded,
                  color: Colors.white, size: 16),
              label: Text(t('export'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('data_export'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cyan,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: AppColors.cyan.withValues(alpha: 0.08),
                        dark: AppColors.cyan.withValues(alpha: 0.18)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppColors.blue, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('data_export_info_banner'),
                          style: TextStyle(
                              fontSize: 13,
                              color: AppThemeColors.primaryText(context)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(t('available_exports'),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue)),
                const SizedBox(height: 4),
                sectionLabel(t('users_and_support'), padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4)),
                const SizedBox(height: 8),
                _exportCard(
                  context: context,
                  icon: Icons.people_outline,
                  title: t('users_label'),
                  subtitle: t('export_users_subtitle'),
                  type: 'users',
                  accent: AppColors.cyan,
                ),
                _exportCard(
                  context: context,
                  icon: Icons.support_agent_outlined,
                  title: t('support_queries_label'),
                  subtitle: t('export_support_subtitle'),
                  type: 'support',
                  accent: Colors.orange,
                ),
                sectionLabel(t('transactions_label'), padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4)),
                const SizedBox(height: 8),
                _exportCard(
                  context: context,
                  icon: Icons.flash_on_rounded,
                  title: t('quick_transactions'),
                  subtitle: t('export_quick_transactions_subtitle'),
                  type: 'quick_transactions',
                  accent: Colors.green,
                ),
                _exportCard(
                  context: context,
                  icon: Icons.lock_outline_rounded,
                  title: t('secure_transactions'),
                  subtitle: t('export_secure_transactions_subtitle'),
                  type: 'transactions',
                  accent: Colors.purple,
                ),
                _exportCard(
                  context: context,
                  icon: Icons.group_outlined,
                  title: t('group_transactions'),
                  subtitle: t('export_group_transactions_subtitle'),
                  type: 'group_transactions',
                  accent: Colors.teal,
                ),
                if (_lastExported != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('${t('last_exported_label')}: $_lastExported',
                            style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_isLoading) loadingOverlay(),
        ],
      ),
    );
  }
}
