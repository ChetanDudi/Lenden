import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/api_client.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

// Admin review queue for wallet withdrawals. Used while no RazorpayX payout
// account is configured: the admin transfers funds to the user's bank/UPI
// outside the app using the details shown here, then marks the request as
// processed (or rejects it, which auto-refunds the user's wallet).
class ManageWithdrawalsPage extends StatefulWidget {
  const ManageWithdrawalsPage({super.key});

  @override
  State<ManageWithdrawalsPage> createState() => _ManageWithdrawalsPageState();
}

class _ManageWithdrawalsPageState extends State<ManageWithdrawalsPage> {
  List<dynamic> _withdrawals = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'processing';

  String t(String key) => AppLocalizations.of(context).t(key);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.get('/api/admin/withdrawals?status=$_statusFilter');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() { _withdrawals = data['withdrawals'] ?? []; _loading = false; });
      } else {
        final data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
        setState(() { _error = (data?['error'] ?? t('failed_to_load_withdrawals')).toString(); _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = t('unable_to_connect_check_internet_message'); _loading = false; });
    }
  }

  Future<void> _markProcessed(String id) async {
    try {
      final res = await ApiClient.post('/api/admin/withdrawals/$id/process', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        showStylishSnackBar(context, t('withdrawal_marked_processed_message'));
        _fetch();
      } else {
        final data = jsonDecode(res.body);
        showStylishSnackBar(context, data['error'] ?? t('action_failed_label'), isError: true);
      }
    } catch (e) {
      if (mounted) showStylishSnackBar(context, t('unable_to_connect_check_internet_message'), isError: true);
    }
  }

  Future<void> _reject(String id) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('reject_withdrawal_title'), style: TextStyle(fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(dialogContext))),
        content: TextField(
          controller: reasonCtrl,
          maxLines: 2,
          style: TextStyle(color: AppThemeColors.primaryText(dialogContext)),
          decoration: InputDecoration(
            hintText: t('reject_reason_hint'),
            filled: true,
            fillColor: AppThemeColors.surfaceBg(dialogContext),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('cancel'), style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(t('reject_label'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiClient.post('/api/admin/withdrawals/$id/reject', body: { 'reason': reasonCtrl.text.trim() });
      if (!mounted) return;
      if (res.statusCode == 200) {
        showStylishSnackBar(context, t('withdrawal_rejected_refunded_message'));
        _fetch();
      } else {
        final data = jsonDecode(res.body);
        showStylishSnackBar(context, data['error'] ?? t('action_failed_label'), isError: true);
      }
    } catch (e) {
      if (mounted) showStylishSnackBar(context, t('unable_to_connect_check_internet_message'), isError: true);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'processed': return const Color(0xFF2E7D32);
      case 'failed': return Colors.red;
      case 'reversed': return Colors.orange;
      default: return AppColors.cyan;
    }
  }

  Widget _filterChip(String value, String label) {
    final selected = _statusFilter == value;
    return GestureDetector(
      onTap: () { setState(() => _statusFilter = value); _fetch(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.cyan : AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.cyan : AppThemeColors.divider(context)),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppThemeColors.secondaryText(context),
          fontWeight: FontWeight.w600, fontSize: 12.5,
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('manage_withdrawals_title'),
          style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetch)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                _filterChip('processing', t('status_pending_label')),
                const SizedBox(width: 8),
                _filterChip('processed', t('status_processed_label')),
                const SizedBox(width: 8),
                _filterChip('failed', t('status_failed_label')),
                const SizedBox(width: 8),
                _filterChip('all', t('status_all_label')),
              ]),
            ),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.cyan))
                : _error != null
                  ? errorStateWidget(context, _error!, _fetch)
                  : _withdrawals.isEmpty
                    ? Center(child: Text(t('no_withdrawal_requests_message'), style: TextStyle(color: AppThemeColors.secondaryText(context))))
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        color: AppColors.cyan,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _withdrawals.length,
                          itemBuilder: (_, i) {
                            final w = _withdrawals[i] as Map<String, dynamic>;
                            final user = (w['user'] is Map) ? w['user'] as Map<String, dynamic> : {};
                            final status = (w['status'] ?? '').toString();
                            final mode = (w['mode'] ?? '').toString();
                            final amount = ((w['amount'] ?? 0) as num).toDouble();
                            final createdAt = (w['createdAt'] ?? '').toString();
                            final dateShort = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppThemeColors.cardBg(context),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppThemeColors.divider(context)),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      (user['name'] ?? user['email'] ?? t('unknown_label')).toString(),
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppThemeColors.primaryText(context)),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _statusColor(status).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(status, style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ]),
                                if (user['email'] != null) ...[
                                  const SizedBox(height: 2),
                                  Text(user['email'].toString(), style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context))),
                                ],
                                const SizedBox(height: 8),
                                Row(children: [
                                  Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFFFF8000))),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                    child: Text(mode == 'upi' ? t('upi_label') : t('bank_account_label'),
                                      style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w600)),
                                  ),
                                ]),
                                const SizedBox(height: 6),
                                if (mode == 'upi')
                                  Text('${t('upi_id_label')}: ${w['upiId'] ?? ''}', style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context)))
                                else ...[
                                  Text('${t('account_holder_name_label')}: ${w['accountHolderName'] ?? ''}', style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context))),
                                  Text('${t('account_number_label')}: ${w['accountNumber'] ?? ''}', style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context))),
                                  Text('${t('ifsc_code_label')}: ${w['ifsc'] ?? ''}', style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context))),
                                  if ((w['bankName'] ?? '').toString().isNotEmpty)
                                    Text('${t('bank_name_optional_label')}: ${w['bankName']}', style: TextStyle(fontSize: 12.5, color: AppThemeColors.secondaryText(context))),
                                ],
                                if ((w['failureReason'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text('${t('reject_reason_hint')}: ${w['failureReason']}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                                ],
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(Icons.calendar_today_rounded, size: 11, color: AppThemeColors.mutedText(context)),
                                  const SizedBox(width: 4),
                                  Text(dateShort, style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                ]),
                                if (status == 'processing') ...[
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        icon: const Icon(Icons.close_rounded, color: Colors.red, size: 16),
                                        label: Text(t('reject_label'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                                        onPressed: () => _reject(w['_id'].toString()),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF2E7D32),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          elevation: 0,
                                        ),
                                        icon: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                                        label: Text(t('mark_as_processed_label'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                        onPressed: () => _markProcessed(w['_id'].toString()),
                                      ),
                                    ),
                                  ]),
                                ],
                              ]),
                            );
                          },
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
