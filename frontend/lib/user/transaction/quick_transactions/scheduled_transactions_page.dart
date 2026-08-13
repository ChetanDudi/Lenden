import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

class ScheduledTransactionsPage extends StatefulWidget {
  const ScheduledTransactionsPage({super.key});

  @override
  State<ScheduledTransactionsPage> createState() => _ScheduledTransactionsPageState();
}

class _ScheduledTransactionsPageState extends State<ScheduledTransactionsPage> {
  List<Map<String, dynamic>> _scheduled = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/quick-transactions/scheduled');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() => _scheduled = List<Map<String, dynamic>>.from(data['scheduled'] ?? []));
        }
      } else {
        if (mounted) setState(() => _error = 'Failed to load scheduled transactions. Please try again.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Failed to load scheduled transactions. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('cancel_scheduled_title')),
        content: Text(t('cancel_scheduled_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('no'))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('yes'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await ApiClient.delete('/api/quick-transactions/$id/cancel-scheduled');
    if (!mounted) return;
    if (res.statusCode == 200) {
      showSnack(context, t('scheduled_cancelled_success'));
      _load();
    } else {
      showSnack(context, jsonDecode(res.body)['error'] ?? t('something_went_wrong'), isError: true);
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString()).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${m[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) { return d.toString(); }
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'active': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 16, 20, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.cyan, Color(0xFF48CAE4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.schedule_rounded, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t('scheduled_transactions_title'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    onPressed: _load,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? errorStateWidget(context, _error!, _load)
                      : _scheduled.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule_rounded, size: 64, color: AppThemeColors.mutedText(context)),
                              const SizedBox(height: 16),
                              Text(t('no_scheduled_transactions'),
                                  style: TextStyle(fontSize: 16, color: AppThemeColors.secondaryText(context))),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _scheduled.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final tx = _scheduled[i];
                            final status = tx['scheduledStatus']?.toString() ?? 'pending';
                            final users = tx['users'] as List? ?? [];
                            final others = users.where((u) => u.toString() != tx['creatorEmail']?.toString()).join(', ');
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppThemeColors.border(context)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tx['description']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: AppThemeColors.primaryText(context),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(status,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: _statusColor(status))),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(Icons.attach_money_rounded, size: 16, color: AppThemeColors.mutedText(context)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${tx['currency'] ?? 'INR'} ${tx['amount']}',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: tx['role'] == 'lender' ? Colors.green : Colors.red),
                                      ),
                                      const SizedBox(width: 12),
                                      Icon(Icons.person_outline, size: 16, color: AppThemeColors.mutedText(context)),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(others,
                                            style: TextStyle(fontSize: 13, color: AppThemeColors.secondaryText(context)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 14, color: AppThemeColors.mutedText(context)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${t('scheduled_for')}: ${_fmtDate(tx['scheduledAt'])}',
                                        style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)),
                                      ),
                                    ],
                                  ),
                                  if (status == 'pending') ...[
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                        label: Text(t('cancel_label'), style: const TextStyle(color: Colors.red, fontSize: 13)),
                                        onPressed: () => _cancel(tx['_id'].toString()),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
