import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class ManageDisputesPage extends StatefulWidget {
  const ManageDisputesPage({Key? key}) : super(key: key);

  @override
  State<ManageDisputesPage> createState() => _ManageDisputesPageState();
}

class _ManageDisputesPageState extends State<ManageDisputesPage> {
  List<Map<String, dynamic>> _disputes = [];
  bool _isLoading = false;
  String? _error;
  String _statusFilter = 'all';

  List<Map<String, String>> _statusOptions(String Function(String) t) => [
        {'value': 'all', 'label': t('all')},
        {'value': 'open', 'label': t('open')},
        {'value': 'under_review', 'label': t('under_review')},
        {'value': 'resolved', 'label': t('resolved')},
        {'value': 'rejected', 'label': t('rejected')},
      ];

  @override
  void initState() {
    super.initState();
    _fetchDisputes();
  }

  Future<void> _fetchDisputes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final query = _statusFilter == 'all' ? '' : '?status=$_statusFilter';
      final response = await ApiClient.get('/api/admin/disputes$query');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _disputes = List<Map<String, dynamic>>.from(data['disputes'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = AppLocalizations.of(context).t('failed_to_load_disputes');
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

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'under_review':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  String _statusLabel(String status) => status
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('MMM dd, yyyy • h:mm a').format(dt.toLocal());
  }

  void _showResolveDialog(Map<String, dynamic> dispute) {
    final t = AppLocalizations.of(context).t;
    String selectedStatus = 'under_review';
    final resolutionController = TextEditingController();

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
                Text(t('update_dispute'),
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
                    DropdownMenuItem(
                        value: 'under_review', child: Text(t('under_review'))),
                    DropdownMenuItem(value: 'resolved', child: Text(t('resolved'))),
                    DropdownMenuItem(value: 'rejected', child: Text(t('rejected'))),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedStatus = v);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resolutionController,
                  maxLines: 3,
                  style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                  decoration: InputDecoration(
                    labelText: t('resolution_notes_both_parties'),
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
                        _resolveDispute(
                            dispute['_id'], selectedStatus, resolutionController.text.trim());
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

  Future<void> _resolveDispute(String id, String status, String resolution) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch('/api/admin/disputes/$id',
          body: {'status': status, 'resolution': resolution});
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('dispute_updated'))),
        );
        _fetchDisputes();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('failed_to_update_dispute'))),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('error')}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    final statusOptions = _statusOptions(t);
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
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
                            t('manage_disputes'),
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
                        onPressed: _fetchDisputes,
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
                          _fetchDisputes();
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
                          : _disputes.isEmpty
                              ? Center(
                                  child: Text(t('no_disputes_found'),
                                      style: TextStyle(color: AppThemeColors.secondaryText(context))),
                                )
                              : RefreshIndicator(
                                  onRefresh: _fetchDisputes,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    itemCount: _disputes.length,
                                    itemBuilder: (context, index) {
                                      final d = _disputes[index];
                                      final status = (d['status'] ?? 'open').toString();
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppThemeColors.cardBg(context),
                                          borderRadius: BorderRadius.circular(16),
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
                                                  child: Text((d['reason'] ?? '').toString(),
                                                      style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                          color: AppThemeColors.primaryText(context))),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _statusColor(status)
                                                        .withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(_statusLabel(status),
                                                      style: TextStyle(
                                                          color: _statusColor(status),
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 12)),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text((d['description'] ?? '').toString(),
                                                style: TextStyle(
                                                    color: AppThemeColors.secondaryText(context),
                                                    fontSize: 13)),
                                            const SizedBox(height: 8),
                                            Text(
                                              '${t('raised_by_label')}: ${d['raisedByEmail'] ?? ''}\n'
                                              '${t('respondent_label')}: ${d['respondentEmail'] ?? '-'}\n'
                                              '${t('type')}: ${d['transactionType'] ?? ''} • ${_formatDate(d['createdAt']?.toString())}',
                                              style: TextStyle(
                                                  color: AppThemeColors.mutedText(context),
                                                  fontSize: 11),
                                            ),
                                            if (d['resolution'] != null &&
                                                (d['resolution'] as String).isNotEmpty) ...[
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
                                                  '${t('resolution_label_colon')} ${d['resolution']}',
                                                  style: TextStyle(
                                                      fontSize: 12, color: AppThemeColors.primaryText(context)),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton.icon(
                                                onPressed: () => _showResolveDialog(d),
                                                icon: const Icon(Icons.gavel_rounded, size: 18),
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
