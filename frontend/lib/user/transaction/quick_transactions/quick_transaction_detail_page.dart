import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';
import '../../../session.dart';
import '../../../utils/api_client.dart';
import '../../wallet/lenden_wallet_page.dart';
import './create_edit_quick_transaction_page.dart';

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
    final confirm = await _showConfirmDialog(
      title: 'Delete Transaction',
      message:
          'Are you sure you want to delete this transaction? This cannot be undone.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirm) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.delete('/api/quick-transactions/$_id');
      if (!mounted) return;
      if (res.statusCode == 200) {
        _didMutate = true;
        showSnack(context, 'Transaction deleted');
        Navigator.pop(context, true);
      } else {
        final msg = jsonDecode(res.body)['error'] ?? 'Delete failed';
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
    final confirm = await _showConfirmDialog(
      title: 'Mark as Cleared',
      message:
          'Mark this transaction as cleared? This indicates the debt has been settled.',
      confirmLabel: 'Clear',
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
        showSnack(context, 'Transaction cleared');
      } else {
        final msg = jsonDecode(res.body)['error'] ?? 'Clear failed';
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
        showSnack(context, 'Settlement request sent');
      } else {
        final msg = jsonDecode(res.body)['error'] ?? 'Request failed';
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
          showSnack(context, 'Settlement rejected');
        } else {
          final msg = jsonDecode(res.body)['error'] ?? 'Response failed';
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
      showSnack(context, 'Transaction duplicated');
    }
  }

  void _shareTransaction() {
    final roleLabel = _myRole == 'lender' ? 'lent' : 'borrowed';
    final msg =
        'Quick Transaction Summary\n'
        '${_formatAmount()} - $_currency\n'
        'You $roleLabel to/from $_counterpartyEmail\n'
        'Description: $_description\n'
        'Status: ${_cleared ? "Cleared" : "Pending"}\n'
        'Settlement: $_settlementStatus';
    Share.share(msg);
  }

  // Direct "Pay Now" — no prior settlement request; just clears the transaction
  void _payNow() {
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: _counterpartyEmail,
      amount: _amount,
      description: _description,
      counterpartyPhone: (_counterparty['phone'] ?? '').toString(),
      quickTransactionId: _id,
      onSuccess: () async {
        final res = await ApiClient.put(
            '/api/quick-transactions/$_id/clear', body: {});
        if (!mounted) return;
        setState(() {
          _tx['cleared'] = true;
          _tx['settledViaPayment'] = true;
        });
        _didMutate = true;
        showSnack(context,
            res.statusCode == 200 ? 'Payment successful!' : 'Paid locally.');
      },
    );
  }

  // Called after the other party ACCEPTS a settlement request.
  // Payment screen opens first; backend is only marked settled after payment succeeds.
  // If payment is cancelled/fails nothing changes (stays 'pending').
  void _payNowForSettlement() {
    LendenPaymentHelper.showPaymentSheet(
      context,
      counterpartyEmail: _counterpartyEmail,
      amount: _amount,
      description: _description,
      counterpartyPhone: (_counterparty['phone'] ?? '').toString(),
      quickTransactionId: _id,
      onSuccess: () async {
        // Payment succeeded → confirm settlement on backend
        try {
          final res = await ApiClient.post(
              '/api/quick-transactions/$_id/respond-settlement',
              body: {'action': 'accept'});
          if (!mounted) return;
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final serverTx =
                (data['quickTransaction'] ?? data['transaction']) as Map?;
            if (serverTx != null) {
              _mergeSettlementFields(Map<String, dynamic>.from(serverTx));
            } else {
              setState(() {
                _tx['settlementStatus'] = 'accepted';
                _tx['cleared'] = true;
                _tx['settledViaPayment'] = true;
              });
            }
          } else {
            // Payment went through but status update failed — mark cleared locally
            setState(() {
              _tx['cleared'] = true;
              _tx['settledViaPayment'] = true;
            });
          }
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _tx['cleared'] = true;
            _tx['settledViaPayment'] = true;
          });
        }
        _didMutate = true;
        if (mounted) showSnack(context, 'Payment successful! Settlement complete.');
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
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
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
        backgroundColor: const Color(0xFFF5F7FA),
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
                  isLender ? 'You lent money' : 'You borrowed money',
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
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit, color: AppColors.cyan),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'duplicate',
              child: ListTile(
                leading: Icon(Icons.copy, color: Colors.blue),
                title: Text('Duplicate'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: ListTile(
                leading: Icon(Icons.share, color: Colors.green),
                title: Text('Share'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_cleared)
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        _statusChip(
          label: _cleared ? 'Cleared' : 'Pending',
          color: _cleared ? Colors.green : Colors.orange,
          icon: _cleared ? Icons.check_circle : Icons.pending,
        ),
        const SizedBox(width: 8),
        _statusChip(
          label: _settlementStatus == 'none'
              ? 'No Settlement'
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
            label: 'Paid',
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
    final dateStr = (_tx['date'] ?? '').toString();
    final timeStr = (_tx['time'] ?? '').toString();
    String displayDate = dateStr;
    try {
      final dt = DateTime.parse(dateStr);
      displayDate = '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {}

    return _card(
      title: 'Transaction Details',
      icon: Icons.receipt_long,
      children: [
        _infoRow('Description', _description, Icons.description),
        _infoRow('Amount', _formatAmount(), Icons.currency_exchange),
        _infoRow('Currency', _currency, Icons.language),
        _infoRow('Date', displayDate, Icons.calendar_today),
        if (timeStr.isNotEmpty) _infoRow('Time', timeStr, Icons.access_time),
        _infoRow(
            'Your Role', _myRole == 'lender' ? 'Lender (Gave)' : 'Borrower (Took)', Icons.people),
      ],
    );
  }

  Widget _buildParticipantsCard() {
    return _card(
      title: 'Participants',
      icon: Icons.people,
      children: [
        _infoRow('You', _currentUserEmail ?? '', Icons.person),
        _infoRow(
          _counterpartyName.isNotEmpty ? _counterpartyName : 'Counterparty',
          _counterpartyEmail,
          Icons.person_outline,
        ),
      ],
    );
  }

  Widget _buildSettlementCard() {
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
      title: 'Settlement History',
      icon: Icons.handshake,
      children: [
        _infoRow('Status', _settlementStatus, Icons.info_outline),
        if (requestedBy.isNotEmpty)
          _infoRow('Requested by', requestedBy, Icons.person),
        if (reqDate.isNotEmpty && requestedBy.isNotEmpty)
          _infoRow('Requested at', reqDate, Icons.calendar_today),
        if (respondedBy.isNotEmpty)
          _infoRow('Responded by', respondedBy, Icons.person),
        if (respDate.isNotEmpty && respondedBy.isNotEmpty)
          _infoRow('Responded at', respDate, Icons.calendar_today),
      ],
    );
  }

  Widget _buildActionsCard() {
    return _card(
      title: 'Actions',
      icon: Icons.touch_app,
      children: [
        if (_canEdit)
          _actionTile(
            icon: Icons.edit,
            color: AppColors.cyan,
            label: 'Edit Transaction',
            subtitle: 'Modify amount, description, or role',
            onTap: _editTransaction,
          ),
        if (_canPayNow)
          _actionTile(
            icon: Icons.payment,
            color: Colors.green,
            label: 'Pay Now',
            subtitle: 'Settle via LenDen Wallet or Razorpay',
            onTap: _payNow,
          ),
        if (_canRequestSettle)
          _actionTile(
            icon: Icons.handshake,
            color: Colors.orange,
            label: 'Request Settlement',
            subtitle: 'Ask the other party to confirm settlement',
            onTap: _requestSettlement,
          ),
        if (_canRespondToSettle) ...[
          _actionTile(
            icon: Icons.check_circle,
            color: Colors.green,
            label: 'Accept Settlement',
            subtitle: 'Confirm the settlement request',
            onTap: () => _respondSettlement(true),
          ),
          _actionTile(
            icon: Icons.cancel,
            color: Colors.red,
            label: 'Reject Settlement',
            subtitle: 'Decline the settlement request',
            onTap: () => _respondSettlement(false),
          ),
        ],
        if (!_cleared)
          _actionTile(
            icon: Icons.done_all,
            color: Colors.teal,
            label: 'Mark as Cleared',
            subtitle: 'Mark this transaction as manually settled',
            onTap: _clearTransaction,
          ),
        _actionTile(
          icon: Icons.copy,
          color: Colors.blue,
          label: 'Duplicate',
          subtitle: 'Create a new transaction with same details',
          onTap: _duplicateTransaction,
        ),
        _actionTile(
          icon: Icons.share,
          color: Colors.indigo,
          label: 'Share',
          subtitle: 'Share transaction summary',
          onTap: _shareTransaction,
        ),
        if (_cleared)
          _actionTile(
            icon: Icons.delete_outline,
            color: Colors.red,
            label: 'Delete Transaction',
            subtitle: 'Permanently remove this transaction',
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
        color: Colors.white,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
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
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value.isNotEmpty ? value : '—',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
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
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
