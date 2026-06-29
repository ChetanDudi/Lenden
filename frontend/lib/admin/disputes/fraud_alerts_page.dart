import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class FraudAlertsPage extends StatefulWidget {
  const FraudAlertsPage({Key? key}) : super(key: key);

  @override
  State<FraudAlertsPage> createState() => _FraudAlertsPageState();
}

class _FraudAlertsPageState extends State<FraudAlertsPage> {
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  String _statusFilter = 'open';

  List<Map<String, String>> _statusOptions(String Function(String) t) => [
        {'value': 'all', 'label': t('all')},
        {'value': 'open', 'label': t('open')},
        {'value': 'reviewing', 'label': t('reviewing')},
        {'value': 'resolved', 'label': t('resolved')},
        {'value': 'dismissed', 'label': t('dismissed')},
      ];

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = _statusFilter == 'all' ? '' : '?status=$_statusFilter';
      final response = await ApiClient.get('/api/admin/fraud-alerts$query');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _alerts = List<Map<String, dynamic>>.from(data['alerts'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context).t('failed_to_load_fraud_alerts');
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '${AppLocalizations.of(context).t('error')}: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _runScan() async {
    final t = AppLocalizations.of(context).t;
    setState(() => _isScanning = true);
    try {
      final response = await ApiClient.post('/api/admin/fraud-alerts/scan');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? t('scan_complete'))),
        );
        _fetchAlerts();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('scan_failed'))),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('error')}: $e')),
      );
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _updateAlert(String id, String status, String note) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch('/api/admin/fraud-alerts/$id',
          body: {'status': status, 'reviewNote': note});
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('alert_updated'))),
        );
        _fetchAlerts();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('failed_to_update_alert'))),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('error')}: $e')),
      );
    }
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFB71C1C);
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'dismissed':
        return Colors.grey;
      case 'reviewing':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _label(String value) => value
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  void _showActionDialog(Map<String, dynamic> alert) {
    final t = AppLocalizations.of(context).t;
    String selectedStatus = 'reviewing';
    final noteController = TextEditingController(text: alert['reviewNote'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: AppThemeColors.cardBg(ctx),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('update_alert'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: AppColors.cyan)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedStatus,
                  decoration: InputDecoration(
                    labelText: t('status'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: [
                    DropdownMenuItem(value: 'reviewing', child: Text(t('reviewing'))),
                    DropdownMenuItem(value: 'resolved', child: Text(t('resolved'))),
                    DropdownMenuItem(value: 'dismissed', child: Text(t('dismissed'))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedStatus = v);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    labelText: t('review_note_internal'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: Text(t('cancel')),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: Text(t('save')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _updateAlert(alert['_id'], selectedStatus, noteController.text.trim());
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final statusOptions = _statusOptions(t);
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _runScan,
        backgroundColor: AppColors.cyan,
        icon: _isScanning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Icon(Icons.search_rounded),
        label: Text(_isScanning ? t('scanning_ellipsis') : t('scan_now')),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            t('fraud_alerts'),
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppThemeColors.primaryText(context)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, color: AppThemeColors.primaryText(context)),
                        tooltip: t('refresh'),
                        onPressed: _fetchAlerts,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: statusOptions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final opt = statusOptions[index];
                      final selected = _statusFilter == opt['value'];
                      return ChoiceChip(
                        label: Text(opt['label']!),
                        selected: selected,
                        selectedColor: AppColors.cyan,
                        labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppThemeColors.primaryText(context)),
                        onSelected: (_) {
                          setState(() => _statusFilter = opt['value']!);
                          _fetchAlerts();
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style: TextStyle(color: AppThemeColors.primaryText(context))))
                          : _alerts.isEmpty
                              ? Center(
                                  child: Text(t('no_fraud_alerts_found'),
                                      style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                )
                              : RefreshIndicator(
                                  onRefresh: _fetchAlerts,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                                    itemCount: _alerts.length,
                                    itemBuilder: (context, index) {
                                      final a = _alerts[index];
                                      final status = (a['status'] ?? 'open').toString();
                                      final severity = (a['severity'] ?? 'medium').toString();
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.cardBg(context),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border(
                                              left: BorderSide(
                                                  color: _severityColor(severity), width: 4)),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.06),
                                              blurRadius: 8,
                                              offset: const Offset(0, 3),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(_label((a['type'] ?? '').toString()),
                                                      style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 15,
                                                          color: AppThemeColors.primaryText(context))),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _severityColor(severity)
                                                        .withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(severity.toUpperCase(),
                                                      style: TextStyle(
                                                          color: _severityColor(severity),
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 10)),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: _statusColor(status)
                                                        .withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  child: Text(_label(status),
                                                      style: TextStyle(
                                                          color: _statusColor(status),
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 10)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text((a['description'] ?? '').toString(),
                                                style: TextStyle(
                                                    color: AppThemeColors.secondaryText(context),
                                                    fontSize: 13)),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${t('target_label')}: ${a['targetEmail'] ?? '-'}'
                                              '${(a['occurrenceCount'] ?? 1) > 1 ? ' • ${t('seen_x_times')} ${a['occurrenceCount']}x' : ''}'
                                              ' • ${_formatDate(a['createdAt']?.toString())}',
                                              style: TextStyle(
                                                  color: AppThemeColors.mutedText(context),
                                                  fontSize: 11),
                                            ),
                                            if (a['reviewNote'] != null &&
                                                (a['reviewNote'] as String).isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: AppThemeColors.tinted(context,
                                                      light: const Color(0xFFF0F7FF),
                                                      dark: const Color(0xFF1B3A57)),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  '${t('note_label_colon')} ${a['reviewNote']}',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Color(0xFF0B4E8A)),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                onPressed: () => _showActionDialog(a),
                                                icon: const Icon(Icons.flag_rounded, size: 18),
                                                label: Text(t('take_action')),
                                                style: TextButton.styleFrom(
                                                    foregroundColor: AppColors.cyan),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
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
