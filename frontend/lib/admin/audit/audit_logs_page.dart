import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';

class AuditLogsPage extends StatefulWidget {
  const AuditLogsPage({Key? key}) : super(key: key);

  @override
  State<AuditLogsPage> createState() => _AuditLogsPageState();
}

class _AuditLogsPageState extends State<AuditLogsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = false;
  String? _error;
  String _severity = 'all';
  String _actor = 'All';

  static const Map<String, Color> _severityColors = {
    'info': AppColors.cyan,
    'warning': Colors.orange,
    'critical': Colors.red,
  };

  static const Map<String, IconData> _severityIcons = {
    'info': Icons.info_outline_rounded,
    'warning': Icons.warning_amber_rounded,
    'critical': Icons.error_outline_rounded,
  };

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final params = <String, String>{};
      final search = _searchController.text.trim();
      if (search.isNotEmpty) params['search'] = Uri.encodeComponent(search);
      if (_severity != 'all') params['severity'] = _severity;
      if (_actor != 'All') params['actor'] = _actor;
      final query = params.isEmpty
          ? ''
          : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      final response = await ApiClient.get('/api/admin/audit-logs$query');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _logs = List<Map<String, dynamic>>.from(data['logs'] ?? []);
          _isLoading = false;
        });
      } else {
        final data = jsonDecode(response.body);
        setState(() {
          _error = (data['message'] ?? 'Failed to load audit logs').toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  String _actionLabel(String action) =>
      action.replaceAll('_', ' ').toUpperCase();

  String _cleanIp(String ip) =>
      ip.startsWith('::ffff:') ? ip.substring(7) : ip;

  Widget _buildSeverityChip(String value, String label) {
    final isSelected = _severity == value;
    final color = value == 'all'
        ? AppColors.cyan
        : (_severityColors[value] ?? AppColors.cyan);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _severity = value);
          _fetchLogs();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isSelected ? color : Colors.grey.shade300),
            boxShadow: isSelected
                ? [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 6)]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final severity = (log['severity'] as String?) ?? 'info';
    final color = _severityColors[severity] ?? AppColors.cyan;
    final icon = _severityIcons[severity] ?? Icons.info_outline_rounded;
    final action = (log['action'] as String?) ?? '';
    final summary = (log['summary'] as String?) ?? '';
    final adminEmail = (log['adminEmail'] as String?) ?? 'Unknown admin';
    final targetType = (log['targetType'] as String?) ?? '';
    final ipAddress = (log['ipAddress'] as String?) ?? '';
    final createdAt = (log['createdAt'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _actionLabel(action),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        adminEmail,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                summary,
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                if (targetType.isNotEmpty)
                  _buildMetaChip(Icons.category_outlined,
                      targetType.toUpperCase(), Colors.grey),
                if (ipAddress.isNotEmpty)
                  _buildMetaChip(Icons.location_on_outlined, _cleanIp(ipAddress),
                      Colors.blueGrey),
                if (createdAt != null)
                  _buildMetaChip(Icons.access_time_rounded,
                      _formatTime(createdAt), Colors.grey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBgAlt,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Audit Logs',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          // Actor toggle
                          GestureDetector(
                            onTap: () {
                              setState(() =>
                                  _actor = _actor == 'All' ? 'mine' : 'All');
                              _fetchLogs();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _actor == 'mine'
                                    ? AppColors.cyan
                                    : Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _actor == 'mine' ? 'Mine' : 'All',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: _actor == 'mine'
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: _fetchLogs,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: tricolorBorder(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: Colors.grey[500], size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              onSubmitted: (_) => _fetchLogs(),
                              decoration: InputDecoration(
                                hintText:
                                    'Search action, admin, summary...',
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 4),
                              ),
                            ),
                          ),
                          if (_searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _fetchLogs();
                              },
                              child: Icon(Icons.clear,
                                  color: Colors.grey[400], size: 18),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Severity filter chips
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _buildSeverityChip('all', 'All'),
                      _buildSeverityChip('info', 'Info'),
                      _buildSeverityChip('warning', 'Warning'),
                      _buildSeverityChip('critical', 'Critical'),
                    ],
                  ),
                ),

                // Count
                if (!_isLoading && _error == null)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Text(
                      '${_logs.length} log${_logs.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                    ),
                  ),

                const SizedBox(height: 4),

                // List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 48,
                                      color: Colors.red[300]),
                                  const SizedBox(height: 12),
                                  Text(_error!,
                                      style: const TextStyle(
                                          color: Colors.red)),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _fetchLogs,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            )
                          : _logs.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                          Icons.history_toggle_off_rounded,
                                          size: 64,
                                          color: Colors.grey[300]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No audit logs found',
                                        style: TextStyle(
                                            fontSize: 17,
                                            color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 24),
                                  itemCount: _logs.length,
                                  itemBuilder: (_, i) =>
                                      _buildLogCard(_logs[i]),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
