import 'package:flutter/material.dart';
import '../utils/api_client.dart';
import '../utils/csv_utils.dart';
import '../utils/share_utils.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';

class AdminDataExportPage extends StatefulWidget {
  const AdminDataExportPage({super.key});

  @override
  State<AdminDataExportPage> createState() => _AdminDataExportPageState();
}

class _AdminDataExportPageState extends State<AdminDataExportPage> {
  bool _isLoading = false;
  String? _lastExported;

  Future<void> _export(String type, String label, IconData icon) async {
    setState(() => _isLoading = true);
    String csvBody = '';
    try {
      final response =
          await ApiClient.get('/api/admin/data/export?type=$type');
      if (response.statusCode != 200) {
        if (mounted) showSnack(context, 'Export failed. Please try again.', isError: true);
        return;
      }
      csvBody = response.body;
      setState(() => _lastExported = label);
    } catch (e) {
      if (mounted) showSnack(context, 'Network error: $e', isError: true);
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
        text: 'Exported data from LenDen Admin Panel.',
      ),
    );
  }

  Widget _exportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
    required Color accent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
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
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
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
              label: const Text('Export',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('Data Export',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
                    color: AppColors.cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cyan.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.blue, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tap Export to preview the data as a table. '
                          'Use Share / Email to send the CSV file.',
                          style:
                              TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Available Exports',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.blue)),
                const SizedBox(height: 4),
                sectionLabel('Users & Support', padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4)),
                const SizedBox(height: 8),
                _exportCard(
                  icon: Icons.people_outline,
                  title: 'Users',
                  subtitle: 'All user accounts — name, username, email, gender, joined date',
                  type: 'users',
                  accent: AppColors.cyan,
                ),
                _exportCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Support Queries',
                  subtitle: 'All support tickets — user, topic, status, priority, date',
                  type: 'support',
                  accent: Colors.orange,
                ),
                sectionLabel('Transactions', padding: const EdgeInsets.only(top: 12, bottom: 2, left: 4)),
                const SizedBox(height: 8),
                _exportCard(
                  icon: Icons.flash_on_rounded,
                  title: 'Quick Transactions',
                  subtitle: 'Creator, participants, role, amount, settlement status',
                  type: 'quick_transactions',
                  accent: Colors.green,
                ),
                _exportCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Secure Transactions',
                  subtitle: 'User email, counterparty, role, amount, currency, place',
                  type: 'transactions',
                  accent: Colors.purple,
                ),
                _exportCard(
                  icon: Icons.group_outlined,
                  title: 'Group Transactions',
                  subtitle: 'Group title, creator, each expense with amount & date',
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
                        Text('Last exported: $_lastExported',
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
