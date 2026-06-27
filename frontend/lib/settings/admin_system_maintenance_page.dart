import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AdminSystemMaintenancePage extends StatefulWidget {
  const AdminSystemMaintenancePage({super.key});

  @override
  State<AdminSystemMaintenancePage> createState() =>
      _AdminSystemMaintenancePageState();
}

class _AdminSystemMaintenancePageState
    extends State<AdminSystemMaintenancePage> {
  bool _isLoading = false;
  Map<String, dynamic>? _stats;

  static const _cyan = AppColors.cyan;
  static const _blue = Color(0xFF0077B6);

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.get('/api/admin/data/stats');
      if (response.statusCode == 200) {
        setState(() =>
            _stats = jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runAction(String action, String confirmMsg) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(t('confirm_action_title'),
                style: TextStyle(color: AppThemeColors.primaryText(ctx))),
          ],
        ),
        content: Text(confirmMsg,
            style: TextStyle(color: AppThemeColors.primaryText(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(t('confirm'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final response = await ApiClient.post(
        '/api/admin/data/maintenance',
        body: {'action': action},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        showSnack(context, data['message'] ?? t('done_exclaim'));
        await _fetchStats();
      } else {
        final data = jsonDecode(response.body);
        showSnack(context, data['error'] ?? t('action_failed'), isError: true);
      }
    } catch (e) {
      showSnack(context, '${t('network_error_label')}: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _statTile(
      BuildContext context, String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14, color: AppThemeColors.primaryText(context))),
          ),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
    required String confirmMsg,
    Color color = _cyan,
  }) {
    final t = AppLocalizations.of(context).t;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: AppThemeColors.primaryText(context))),
                Text(subtitle,
                    style: TextStyle(
                        color: AppThemeColors.secondaryText(context),
                        fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _isLoading
                ? null
                : () => _runAction(action, confirmMsg),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(t('run'), style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  String _formatUptime(int? seconds) {
    if (seconds == null) return '--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h}h ${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('system_maintenance_title'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _cyan,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStats,
            tooltip: t('refresh_stats_tooltip'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // System health
                Text(t('system_health_title'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _blue)),
                const SizedBox(height: 10),
                _statTile(context, t('total_users_label'),
                    '${_stats?['users'] ?? '--'}', Icons.people_outline, _cyan),
                _statTile(
                    context,
                    t('total_admins_label'),
                    '${_stats?['admins'] ?? '--'}',
                    Icons.admin_panel_settings_outlined,
                    Colors.purple),
                _statTile(
                    context,
                    t('transactions_label'),
                    '${_stats?['transactions'] ?? '--'}',
                    Icons.swap_horiz_rounded,
                    Colors.green),
                _statTile(
                    context,
                    t('support_queries_label'),
                    '${_stats?['supportQueries'] ?? '--'}',
                    Icons.support_agent_outlined,
                    Colors.orange),
                _statTile(
                    context,
                    t('activity_records_label'),
                    '${_stats?['activities'] ?? '--'}',
                    Icons.timeline_rounded,
                    Colors.blue),
                _statTile(
                    context,
                    t('server_uptime_label'),
                    _formatUptime(_stats?['uptimeSeconds'] as int?),
                    Icons.timer_outlined,
                    Colors.teal),
                if (_stats?['serverTime'] != null)
                  _statTile(
                    context,
                    t('server_time_label'),
                    (_stats!['serverTime'] as String).replaceAll('T', ' ').split('.').first,
                    Icons.access_time,
                    Colors.indigo,
                  ),
                const SizedBox(height: 24),

                // Maintenance actions
                Text(t('maintenance_actions_title'),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _blue)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: Colors.orange.withValues(alpha: 0.08),
                        dark: Colors.orange.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t('maintenance_actions_warning'),
                          style: const TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                _actionCard(
                  context,
                  icon: Icons.delete_sweep_outlined,
                  title: t('clear_old_resolved_queries_title'),
                  subtitle: t('clear_old_resolved_queries_desc'),
                  action: 'clear_old_queries',
                  confirmMsg: t('clear_old_resolved_queries_confirm'),
                  color: Colors.orange,
                ),
                _actionCard(
                  context,
                  icon: Icons.history_toggle_off_rounded,
                  title: t('clear_old_activity_logs_title'),
                  subtitle: t('clear_old_activity_logs_desc'),
                  action: 'clear_old_activities',
                  confirmMsg: t('clear_old_activity_logs_confirm'),
                  color: Colors.deepOrange,
                ),
                _actionCard(
                  context,
                  icon: Icons.manage_history_rounded,
                  title: t('clear_old_audit_logs_title'),
                  subtitle: t('clear_old_audit_logs_desc'),
                  action: 'clear_old_audit_logs',
                  confirmMsg: t('clear_old_audit_logs_confirm'),
                  color: Colors.red,
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
