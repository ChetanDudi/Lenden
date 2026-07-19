import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/payment_success_page.dart';
import '../../wallet/lenden_wallet_page.dart';
import './create_edit_quick_transaction_page.dart';
import '../../../utils/theme_helper.dart';
import '../../../l10n/app_localizations.dart';

const _kQtCategories = [
  {'key': 'food',          'label': 'Food',          'icon': Icons.restaurant_rounded},
  {'key': 'transport',     'label': 'Transport',     'icon': Icons.directions_car_rounded},
  {'key': 'accommodation', 'label': 'Stay',          'icon': Icons.hotel_rounded},
  {'key': 'entertainment', 'label': 'Fun',           'icon': Icons.sports_esports_rounded},
  {'key': 'shopping',      'label': 'Shopping',      'icon': Icons.shopping_cart_rounded},
  {'key': 'utilities',     'label': 'Utilities',     'icon': Icons.electrical_services_rounded},
  {'key': 'medical',       'label': 'Medical',       'icon': Icons.local_hospital_rounded},
  {'key': 'education',     'label': 'Education',     'icon': Icons.school_rounded},
  {'key': 'other',         'label': 'Other',         'icon': Icons.more_horiz_rounded},
];

IconData _categoryIcon(String? key) {
  final cat = _kQtCategories.firstWhere((c) => c['key'] == key, orElse: () => _kQtCategories.last);
  return cat['icon'] as IconData;
}

String _categoryLabel(String? key) {
  return (_kQtCategories.firstWhere((c) => c['key'] == key, orElse: () => _kQtCategories.last)['label'] as String);
}

class QuickTransactionDetailPage extends StatefulWidget {
  final Map<String, dynamic> transaction;

  const QuickTransactionDetailPage({
    super.key,
    required this.transaction,
  });

  @override
  State<QuickTransactionDetailPage> createState() =>
      _QuickTransactionDetailPageState();
}

class _QuickTransactionDetailPageState
    extends State<QuickTransactionDetailPage> {
  late Map<String, dynamic> _tx;
  bool _isLoading = false;
  bool _didMutate = false;
  String? _currentUserEmail;

  @override
  void initState() {
    super.initState();
    _tx = Map<String, dynamic>.from(widget.transaction);
    final session = Provider.of<SessionProvider>(context, listen: false);
    _currentUserEmail =
        (session.user?['email'] ?? '').toString().toLowerCase().trim();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────

  String get _id => (_tx['_id'] ?? '').toString();

  double get _amount => double.tryParse(_tx['amount']?.toString() ?? '0') ?? 0;
  String get _currency => (_tx['currency'] ?? 'INR').toString();
  String get _description => (_tx['description'] ?? '').toString();
  bool get _cleared => _tx['cleared'] == true;
  String get _settlementStatus =>
      (_tx['settlementStatus'] ?? 'none').toString();
  String get _creatorEmail =>
      (_tx['creatorEmail'] ?? '').toString().toLowerCase().trim();
  String get _role => (_tx['role'] ?? 'lender').toString();
  String get _settlementRequestedBy =>
      (_tx['settlementRequestedBy'] ?? '').toString().toLowerCase().trim();

  bool get _isCreator => _currentUserEmail == _creatorEmail;

  String get _myRole {
    if (_isCreator) return _role;
    return _role == 'lender' ? 'borrower' : 'lender';
  }

  Map<String, dynamic> get _counterparty {
    final rawList = (_tx['users'] as List? ?? []);
    for (final user in rawList) {
      if (user is Map) {
        final email = (user['email'] ?? '').toString().toLowerCase().trim();
        if (email.isNotEmpty && email != _currentUserEmail) {
          return Map<String, dynamic>.from(user);
        }
      } else if (user is String) {
        // raw API response — users are email strings, not enriched objects
        final email = user.toLowerCase().trim();
        if (email.isNotEmpty && email != _currentUserEmail) {
          return {'email': user, 'name': '', 'phone': ''};
        }
      }
    }
    return <String, dynamic>{};
  }

  String get _counterpartyEmail =>
      (_counterparty['email'] ?? '').toString();
  String get _counterpartyName =>
      (_counterparty['name'] ?? _counterparty['username'] ?? '').toString();

  bool get _canEdit => !_cleared;
  bool get _canRequestSettle =>
      (_settlementStatus == 'none' || _settlementStatus == 'rejected') &&
      !_cleared &&
      _myRole == 'lender';
  bool get _canRespondToSettle =>
      _settlementStatus == 'pending' &&
      !_cleared &&
      _settlementRequestedBy != _currentUserEmail;
  bool get _canPayNow => _myRole == 'borrower' && !_cleared;

  String _formatAmount() =>
      '${_getCurrencySymbol(_currency)}${_amount.toStringAsFixed(2)}';

  String _getCurrencySymbol(String code) {
    const symbols = {
      'INR': '₹',
      'USD': '\$',
      'EUR': '€',
      'GBP': '£',
      'JPY': '¥',
      'CNY': '¥',
      'CAD': '\$',
      'AUD': '\$',
      'CHF': 'Fr',
      'RUB': '₽',
    };
    return symbols[code.toUpperCase()] ?? code;
  }

  // ─── API calls ──────────────────────────────────────────────────────────────

  Future<void> _deleteTransaction() async {
    final t = AppLocalizations.of(context).t;
    final confirm = await _showConfirmDialog(
      title: t('delete_transaction_title'),
      message: t('confirm_delete_transaction_irreversible_message'),
      confirmLabel: t('delete'),
      isDestructive: true,
    );
    if (!confirm) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.delete('/api/quick-transactions/$_id');
      if (!mounted) return;
      if (res.statusCode == 200) {
        _didMutate = true;
        showSnack(context, t('transaction_deleted_message'));
        Navigator.pop(context, true);
      } else {
        final msg = jsonDecode(res.body)['error'] ?? t('delete_failed_message');
        showSnack(context, msg.toString(), isError: true);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), isError: true);
      setState(() => _isLoading = false);
    }
  }

  // Merge server settlement fields back into _tx without clobbering the
  // enriched `users` list (which the list endpoint populates but individual
  // settlement endpoints do not).
  void _mergeSettlementFields(Map<String, dynamic> serverTx) {
    final enrichedUsers = _tx['users']; // keep the populated user objects
    setState(() {
      _tx = Map<String, dynamic>.from(serverTx);
      _tx['users'] = enrichedUsers;
      _isLoading = false;
    });
  }

  Future<void> _clearTransaction() async {
    final t = AppLocalizations.of(context).t;
    final confirm = await _showConfirmDialog(
      title: t('mark_as_cleared_title'),
      message: t('mark_transaction_cleared_confirm_message'),
      confirmLabel: t('clear'),
    );
    if (!confirm) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.put(
          '/api/quick-transactions/$_id/clear', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final serverTx =
            (data['quickTransaction'] ?? data['transaction']) as Map?;
        if (serverTx != null) {
          _mergeSettlementFields(Map<String, dynamic>.from(serverTx));
        } else {
          setState(() {
            _tx['cleared'] = true;
            _isLoading = false;
          });
        }
        _didMutate = true;
        showSnack(context, t('transaction_cleared_message'));
      } else {
        final msg = jsonDecode(res.body)['error'] ?? t('clear_failed_message');
        showSnack(context, msg.toString(), isError: true);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestSettlement() async {
    final t = AppLocalizations.of(context).t;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.post(
          '/api/quick-transactions/$_id/request-settlement', body: {});
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final serverTx =
            (data['quickTransaction'] ?? data['transaction']) as Map?;
        if (serverTx != null) {
          _mergeSettlementFields(Map<String, dynamic>.from(serverTx));
        } else {
          setState(() => _isLoading = false);
        }
        _didMutate = true;
        showSnack(context, t('settlement_request_sent_message'));
      } else {
        final msg = jsonDecode(res.body)['error'] ?? t('request_failed_message');
        showSnack(context, msg.toString(), isError: true);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString(), isError: true);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _respondSettlement(bool accept) async {
    final t = AppLocalizations.of(context).t;
    if (!accept) {
      // Reject — no payment, update backend directly and stay on this page
      setState(() => _isLoading = true);
      try {
        final res = await ApiClient.post(
            '/api/quick-transactions/$_id/respond-settlement',
            body: {'action': 'reject'});
        if (!mounted) return;
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final serverTx =
              (data['quickTransaction'] ?? data['transaction']) as Map?;
          if (serverTx != null) {
            _mergeSettlementFields(Map<String, dynamic>.from(serverTx));
          } else {
            setState(() {
              _tx['settlementStatus'] = 'rejected';
              _isLoading = false;
            });
          }
          _didMutate = true;
          showSnack(context, t('settlement_rejected_message'));
        } else {
          final msg = jsonDecode(res.body)['error'] ?? t('response_failed_message');
          showSnack(context, msg.toString(), isError: true);
          setState(() => _isLoading = false);
        }
      } catch (e) {
        if (!mounted) return;
        showSnack(context, e.toString(), isError: true);
        setState(() => _isLoading = false);
      }
      return;
    }

    // Accept — go straight to payment; backend is only updated AFTER payment succeeds
    _payNowForSettlement();
  }

  void _editTransaction() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditQuickTransactionPage(
          transaction: _tx,
        ),
      ),
    );
    if (result is Map<String, dynamic>) {
      setState(() {
        final updated = result['quickTransaction'] ??
            result['transaction'] ??
            result;
        if (updated is Map) {
          _tx = Map<String, dynamic>.from(updated);
        }
      });
      _didMutate = true;
    } else if (result is String) {
      showSnack(context, result, isError: true);
    }
  }

  void _duplicateTransaction() async {
    final t = AppLocalizations.of(context).t;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateEditQuickTransactionPage(
          prefillCounterpartyEmail: _counterpartyEmail,
          initialAmount: _amount.toString(),
          initialCurrency: _currency,
          initialDescription: _description,
          initialRole: _myRole,
        ),
      ),
    );
    if (result != null) {
      _didMutate = true;
      if (!mounted) return;
      showSnack(context, t('transaction_duplicated_success_message'));
    }
  }

  void _shareTransaction() {
    final t = AppLocalizations.of(context).t;
    final roleLabel = _myRole == 'lender' ? t('lent_label') : t('borrowed_label');
    final msg =
        '${t('quick_transaction_summary_title')}\n'
        '${_formatAmount()} - $_currency\n'
        '${t('you_role_to_from_counterparty_label').replaceFirst('{role}', roleLabel).replaceFirst('{counterparty}', _counterpartyEmail)}\n'
        '${t('description_colon_label')} $_description\n'
        '${t('status_colon_label')} ${_cleared ? t('cleared') : t('pending_label')}\n'
        '${t('settlement_colon_label')} $_settlementStatus';
    Share.share(msg);
  }

  // Direct "Pay Now" — /pay atomically transfers the wallet money and marks
  // the transaction settled server-side in one call.
  void _payNow() {
    final t = AppLocalizations.of(context).t;
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: _counterpartyEmail,
      amount: _amount,
      description: _description,
      payEndpoint: '/api/quick-transactions/$_id/pay',
      onSuccess: () {
        setState(() {
          _tx['cleared'] = true;
          _tx['settledViaPayment'] = true;
        });
        _didMutate = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentSuccessPage(
              title: t('payment_successful_exclaim'),
              amount: _amount,
              recipientName: _counterpartyEmail,
              transactionType: t('quick_transaction_settlement_label'),
              extraDetails: _description.isNotEmpty ? {t('description'): _description} : const {},
            ),
          ),
        );
      },
    );
  }

  // Called after the other party ACCEPTS a settlement request. /pay
  // atomically transfers the wallet money and flips settlementStatus
  // pending → accepted together — no separate unverified confirm call after.
  void _payNowForSettlement() {
    final t = AppLocalizations.of(context).t;
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: _counterpartyEmail,
      amount: _amount,
      description: _description,
      payEndpoint: '/api/quick-transactions/$_id/pay',
      onSuccess: () {
        setState(() {
          _tx['settlementStatus'] = 'accepted';
          _tx['cleared'] = true;
          _tx['settledViaPayment'] = true;
        });
        _didMutate = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentSuccessPage(
              title: t('payment_successful_exclaim'),
              amount: _amount,
              recipientName: _counterpartyEmail,
              transactionType: t('quick_transaction_settlement_label'),
              extraDetails: _description.isNotEmpty ? {t('description'): _description} : const {},
            ),
          ),
        );
      },
    );
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final t = AppLocalizations.of(context).t;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
        content: Text(message,
            style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : AppColors.cyan,
            ),
            child: Text(confirmLabel,
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _didMutate);
      },
      child: Scaffold(
        backgroundColor: AppThemeColors.scaffoldBg(context),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusRow(),
                          const SizedBox(height: 16),
                          _buildDetailsCard(),
                          const SizedBox(height: 16),
                          _buildParticipantsCard(),
                          if (_settlementStatus != 'none') ...[
                            const SizedBox(height: 16),
                            _buildSettlementCard(),
                          ],
                          const SizedBox(height: 16),
                          _buildActionsCard(),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    final t = AppLocalizations.of(context).t;
    final isLender = _myRole == 'lender';
    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context, _didMutate),
      ),
      backgroundColor: isLender ? AppColors.cyan : Colors.orange[700],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isLender
                  ? [AppColors.cyan, const Color(0xFF48CAE4)]
                  : [Colors.orange[700]!, Colors.orange[400]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Text(
                _formatAmount(),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isLender ? t('you_lent_money_label') : t('you_borrowed_money_label'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editTransaction();
                break;
              case 'duplicate':
                _duplicateTransaction();
                break;
              case 'delete':
                _deleteTransaction();
                break;
              case 'share':
                _shareTransaction();
                break;
            }
          },
          itemBuilder: (_) => [
            if (_canEdit)
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: const Icon(Icons.edit, color: AppColors.cyan),
                  title: Text(t('edit')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: 'duplicate',
              child: ListTile(
                leading: const Icon(Icons.copy, color: Colors.blue),
                title: Text(t('duplicate_label')),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            PopupMenuItem(
              value: 'share',
              child: ListTile(
                leading: const Icon(Icons.share, color: Colors.green),
                title: Text(t('share')),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_cleared)
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(t('delete')),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    final t = AppLocalizations.of(context).t;
    return Row(
      children: [
        _statusChip(
          label: _cleared ? t('cleared') : t('pending_label'),
          color: _cleared ? Colors.green : Colors.orange,
          icon: _cleared ? Icons.check_circle : Icons.pending,
        ),
        const SizedBox(width: 8),
        _statusChip(
          label: _settlementStatus == 'none'
              ? t('no_settlement_label')
              : _settlementStatus[0].toUpperCase() +
                  _settlementStatus.substring(1),
          color: _settlementStatus == 'accepted'
              ? Colors.green
              : _settlementStatus == 'pending'
                  ? Colors.orange
                  : _settlementStatus == 'rejected'
                      ? Colors.red
                      : Colors.grey,
          icon: Icons.handshake,
        ),
        if ((_tx['settledViaPayment'] ?? false) == true) ...[
          const SizedBox(width: 8),
          _statusChip(
            label: t('paid_label'),
            color: Colors.blue,
            icon: Icons.payment,
          ),
        ],
      ],
    );
  }

  Widget _statusChip(
      {required String label,
      required Color color,
      required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final t = AppLocalizations.of(context).t;
    final dateStr = (_tx['date'] ?? '').toString();
    final timeStr = (_tx['time'] ?? '').toString();
    String displayDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      displayDate = '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {}

    return _card(
      title: t('transaction_details_title'),
      icon: Icons.receipt_long,
      children: [
        _infoRow(t('description_label'), _description, Icons.description),
        _infoRow(t('amount_label'), _formatAmount(), Icons.currency_exchange),
        _infoRow(t('currency_label'), _currency, Icons.language),
        _infoRow(t('date_label'), displayDate, Icons.calendar_today),
        if (timeStr.isNotEmpty) _infoRow(t('time_label'), timeStr, Icons.access_time),
        _infoRow(
            t('your_role_label'),
            _myRole == 'lender' ? t('lender_gave_label') : t('borrower_took_label'),
            Icons.people),
        _infoRow('Category', _categoryLabel((_tx['category'] ?? 'other').toString()), _categoryIcon((_tx['category'] ?? 'other').toString())),
      ],
    );
  }

  Widget _buildParticipantsCard() {
    final t = AppLocalizations.of(context).t;
    return _card(
      title: t('participants_title'),
      icon: Icons.people,
      children: [
        _infoRow(t('you_label'), _currentUserEmail ?? '', Icons.person),
        _infoRow(
          _counterpartyName.isNotEmpty ? _counterpartyName : t('counterparty_label'),
          _counterpartyEmail,
          Icons.person_outline,
        ),
      ],
    );
  }

  Widget _buildSettlementCard() {
    final t = AppLocalizations.of(context).t;
    final requestedBy = (_tx['settlementRequestedBy'] ?? '').toString();
    final requestedAt = (_tx['settlementRequestedAt'] ?? '').toString();
    final respondedBy = (_tx['settlementRespondedBy'] ?? '').toString();
    final respondedAt = (_tx['settlementRespondedAt'] ?? '').toString();

    String reqDate = requestedAt;
    String respDate = respondedAt;
    try {
      if (requestedAt.isNotEmpty) {
        final dt = DateTime.parse(requestedAt);
        reqDate = '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    try {
      if (respondedAt.isNotEmpty) {
        final dt = DateTime.parse(respondedAt);
        respDate = '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (_) {}

    return _card(
      title: t('settlement_history_title'),
      icon: Icons.handshake,
      children: [
        _infoRow(t('status_label'), _settlementStatus, Icons.info_outline),
        if (requestedBy.isNotEmpty)
          _infoRow(t('requested_by_label'), requestedBy, Icons.person),
        if (reqDate.isNotEmpty && requestedBy.isNotEmpty)
          _infoRow(t('requested_at_label'), reqDate, Icons.calendar_today),
        if (respondedBy.isNotEmpty)
          _infoRow(t('responded_by_label'), respondedBy, Icons.person),
        if (respDate.isNotEmpty && respondedBy.isNotEmpty)
          _infoRow(t('responded_at_label'), respDate, Icons.calendar_today),
      ],
    );
  }

  Widget _buildActionsCard() {
    final t = AppLocalizations.of(context).t;
    return _card(
      title: t('actions_title'),
      icon: Icons.touch_app,
      children: [
        if (_canEdit)
          _actionTile(
            icon: Icons.edit,
            color: AppColors.cyan,
            label: t('edit_transaction_label'),
            subtitle: t('modify_amount_description_role_message'),
            onTap: _editTransaction,
          ),
        if (_canPayNow)
          _actionTile(
            icon: Icons.payment,
            color: Colors.green,
            label: t('pay_now_label'),
            subtitle: t('settle_via_wallet_or_razorpay_message'),
            onTap: _payNow,
          ),
        if (_canRequestSettle)
          _actionTile(
            icon: Icons.handshake,
            color: Colors.orange,
            label: t('request_settlement_label'),
            subtitle: t('ask_other_party_confirm_settlement_message'),
            onTap: _requestSettlement,
          ),
        if (_canRespondToSettle) ...[
          _actionTile(
            icon: Icons.check_circle,
            color: Colors.green,
            label: t('accept_settlement_label'),
            subtitle: t('confirm_settlement_request_message'),
            onTap: () => _respondSettlement(true),
          ),
          _actionTile(
            icon: Icons.cancel,
            color: Colors.red,
            label: t('reject_settlement_label'),
            subtitle: t('decline_settlement_request_message'),
            onTap: () => _respondSettlement(false),
          ),
        ],
        if (!_cleared)
          _actionTile(
            icon: Icons.done_all,
            color: Colors.teal,
            label: t('mark_as_cleared_title'),
            subtitle: t('mark_transaction_manually_settled_message'),
            onTap: _clearTransaction,
          ),
        _actionTile(
          icon: Icons.copy,
          color: Colors.blue,
          label: t('duplicate_label'),
          subtitle: t('create_transaction_same_details_message'),
          onTap: _duplicateTransaction,
        ),
        _actionTile(
          icon: Icons.share,
          color: Colors.indigo,
          label: t('share'),
          subtitle: t('share_transaction_summary_message'),
          onTap: _shareTransaction,
        ),
        if (_cleared)
          _actionTile(
            icon: Icons.delete_outline,
            color: Colors.red,
            label: t('delete_transaction_title'),
            subtitle: t('permanently_remove_transaction_message'),
            onTap: _deleteTransaction,
          ),
      ],
    );
  }

  // ─── Reusable widgets ────────────────────────────────────────────────────────

  Widget _card({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.cyan),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppThemeColors.divider(context)),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppThemeColors.mutedText(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppThemeColors.mutedText(context),
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value.isNotEmpty ? value : '—',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppThemeColors.primaryText(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppThemeColors.primaryText(context))),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: AppThemeColors.mutedText(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppThemeColors.mutedText(context)),
          ],
        ),
      ),
    );
  }
}
