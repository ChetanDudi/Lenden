import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';

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

  static const _cyan = Color(0xFF00B4D8);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Confirm Action'),
          ],
        ),
        content: Text(confirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
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
        _showSnack(data['message'] ?? 'Done!');
        await _fetchStats();
      } else {
        final data = jsonDecode(response.body);
        _showSnack(data['error'] ?? 'Action failed.', isError: true);
      }
    } catch (e) {
      _showSnack('Network error: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
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
                style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String action,
    required String confirmMsg,
    Color color = _cyan,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
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
            child: Text('Run', style: TextStyle(color: color)),
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text('System Maintenance',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _cyan,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStats,
            tooltip: 'Refresh Stats',
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
                const Text('System Health',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _blue)),
                const SizedBox(height: 10),
                _statTile('Total Users', '${_stats?['users'] ?? '--'}',
                    Icons.people_outline, _cyan),
                _statTile('Total Admins', '${_stats?['admins'] ?? '--'}',
                    Icons.admin_panel_settings_outlined, Colors.purple),
                _statTile(
                    'Transactions',
                    '${_stats?['transactions'] ?? '--'}',
                    Icons.swap_horiz_rounded,
                    Colors.green),
                _statTile(
                    'Support Queries',
                    '${_stats?['supportQueries'] ?? '--'}',
                    Icons.support_agent_outlined,
                    Colors.orange),
                _statTile(
                    'Activity Records',
                    '${_stats?['activities'] ?? '--'}',
                    Icons.timeline_rounded,
                    Colors.blue),
                _statTile(
                    'Server Uptime',
                    _formatUptime(_stats?['uptimeSeconds'] as int?),
                    Icons.timer_outlined,
                    Colors.teal),
                if (_stats?['serverTime'] != null)
                  _statTile(
                    'Server Time',
                    (_stats!['serverTime'] as String).replaceAll('T', ' ').split('.').first,
                    Icons.access_time,
                    Colors.indigo,
                  ),
                const SizedBox(height: 24),

                // Maintenance actions
                const Text('Maintenance Actions',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _blue)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'These actions permanently delete data. Use with caution.',
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                _actionCard(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Clear Old Resolved Queries',
                  subtitle: 'Delete resolved/closed support queries older than 7 days',
                  action: 'clear_old_queries',
                  confirmMsg:
                      'This will permanently delete all resolved/closed support queries older than 7 days. This cannot be undone.',
                  color: Colors.orange,
                ),
                _actionCard(
                  icon: Icons.history_toggle_off_rounded,
                  title: 'Clear Old Activity Logs',
                  subtitle: 'Delete activity records older than 30 days',
                  action: 'clear_old_activities',
                  confirmMsg:
                      'This will permanently delete all activity records older than 30 days. This cannot be undone.',
                  color: Colors.deepOrange,
                ),
                _actionCard(
                  icon: Icons.manage_history_rounded,
                  title: 'Clear Old Audit Logs',
                  subtitle: 'Delete admin audit logs older than 90 days',
                  action: 'clear_old_audit_logs',
                  confirmMsg:
                      'This will permanently delete admin audit logs older than 90 days. This cannot be undone.',
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
