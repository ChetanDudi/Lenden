import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class ManageQuickTransactionsPage extends StatefulWidget {
  const ManageQuickTransactionsPage({super.key});

  @override
  State<ManageQuickTransactionsPage> createState() =>
      _ManageQuickTransactionsPageState();
}

class _ManageQuickTransactionsPageState
    extends State<ManageQuickTransactionsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  List<dynamic> _transactions = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;
  String _searchQuery = '';
  String _clearedFilter = 'all';
  String _settlementFilter = 'all';
  String _sortBy = 'latest';

  @override
  void initState() {
    super.initState();
    _fetchTransactions();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      _loading = true;
      _error = null;
      _showAll = false;
    });
    try {
      final params = <String, String>{};
      if (_searchQuery.trim().isNotEmpty) params['search'] = _searchQuery.trim();
      if (_clearedFilter == 'cleared') params['cleared'] = 'true';
      else if (_clearedFilter == 'uncleared') params['cleared'] = 'false';
      if (_settlementFilter != 'all') params['settlementStatus'] = _settlementFilter;
      if (_sortBy == 'amount_high') {
        params['sortBy'] = 'amount';
        params['order'] = 'desc';
      } else if (_sortBy == 'amount_low') {
        params['sortBy'] = 'amount';
        params['order'] = 'asc';
      } else {
        params['sortBy'] = 'createdAt';
        params['order'] = 'desc';
      }
      params['limit'] = '100';
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await ApiClient.get('/api/admin/quick-transactions$query');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _transactions = data['transactions'] ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = data['message'] ??
              AppLocalizations.of(context).t('failed_to_load_transactions');
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '${AppLocalizations.of(context).t('an_error_occurred')}: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteTransaction(String id) async {
    final t = AppLocalizations.of(context).t;
    final response =
        await ApiClient.delete('/api/admin/quick-transactions/$id');
    if (response.statusCode == 200) {
      _showSnackBar(t('transaction_deleted_successfully'));
      _fetchTransactions();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['message'] ?? t('failed_to_delete_transaction'));
  }

  Future<void> _updateTransaction(
      String id, Map<String, dynamic> body) async {
    final t = AppLocalizations.of(context).t;
    final response = await ApiClient.put(
      '/api/admin/quick-transactions/$id',
      body: body,
    );
    if (response.statusCode == 200) {
      _showSnackBar(t('transaction_updated_successfully'));
      _fetchTransactions();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['message'] ?? t('failed_to_update_transaction'));
  }

  void _showDeleteConfirmationDialog(String id) {
    showDialog(
      context: context,
      builder: (context) {
        final t = AppLocalizations.of(context).t;
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                colors: [
                  AppThemeColors.tinted(context,
                      light: const Color(0xFFFFF5F5),
                      dark: const Color(0xFF3A1F1F)),
                  AppThemeColors.cardBg(context),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppThemeColors.tinted(context,
                        light: const Color(0xFFFFE3E3),
                        dark: const Color(0xFF4A2424)),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.red,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t('delete_quick_transaction_title'),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppThemeColors.primaryText(context)),
                ),
                const SizedBox(height: 10),
                Text(
                  t('confirm_delete_quick_transaction'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      height: 1.4),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(t('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteTransaction(id);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(t('delete')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> tx) async {
    final amountCtrl =
        TextEditingController(text: '${tx['amount'] ?? ''}');
    final descCtrl =
        TextEditingController(text: '${tx['description'] ?? ''}');
    final currencyCtrl =
        TextEditingController(text: '${tx['currency'] ?? 'INR'}');
    bool cleared = tx['cleared'] == true;
    String settlementStatus = tx['settlementStatus'] ?? 'none';
    String role = tx['role'] ?? 'lender';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final t = AppLocalizations.of(context).t;
          return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                  color: AppColors.cyan.withValues(alpha: 0.18)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF003049), AppColors.cyan],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          t('edit_quick_transaction_title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: t('amount'),
                      prefixIcon: const Icon(Icons.currency_rupee_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currencyCtrl,
                    decoration: InputDecoration(
                      labelText: t('currency'),
                      prefixIcon: const Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: InputDecoration(
                      labelText: t('description'),
                      prefixIcon: const Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: InputDecoration(
                      labelText: t('role'),
                      prefixIcon: const Icon(Icons.swap_horiz_rounded),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'lender', child: Text(t('lender'))),
                      DropdownMenuItem(
                          value: 'borrower', child: Text(t('borrower'))),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => role = value ?? role),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: settlementStatus,
                    decoration: InputDecoration(
                      labelText: t('settlement_status_label'),
                      prefixIcon: const Icon(Icons.handshake_rounded),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'none', child: Text(t('none'))),
                      DropdownMenuItem(
                          value: 'pending', child: Text(t('pending'))),
                      DropdownMenuItem(
                          value: 'accepted', child: Text(t('accepted'))),
                      DropdownMenuItem(
                          value: 'rejected', child: Text(t('rejected'))),
                    ],
                    onChanged: (value) => setDialogState(
                        () => settlementStatus = value ?? settlementStatus),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: cleared,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('cleared')),
                    subtitle: Text(t('mark_as_settled_cleared')),
                    onChanged: (value) =>
                        setDialogState(() => cleared = value),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(t('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount = double.tryParse(
                                amountCtrl.text.trim());
                            if (amount == null || amount <= 0) {
                              _showSnackBar(t('enter_a_valid_amount'));
                              return;
                            }
                            Navigator.pop(context);
                            _updateTransaction(tx['_id'], {
                              'amount': amount,
                              'currency': currencyCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'cleared': cleared,
                              'settlementStatus': settlementStatus,
                              'role': role,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(t('save')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
        },
      ),
    );
  }

  void _showSnackBar(String message) => showSnack(context, message);

  String _formatDate(dynamic raw) {
    if (raw == null) return AppLocalizations.of(context).t('unknown');
    try {
      return DateFormat('MMM d, yyyy h:mm a')
          .format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return raw.toString();
    }
  }

  Color _settlementColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  List<dynamic> get _visibleTransactions =>
      _showAll || _transactions.length <= 10
          ? _transactions
          : _transactions.take(10).toList();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
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
                  color: AppThemeColors.waveSolid(context)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.iconOnWave(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('manage_quick_transactions'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.iconOnWave(context)),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh,
                            color: AppThemeColors.iconOnWave(context)),
                        onPressed: _fetchTransactions,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      color: Colors.red)))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                  16, 8, 16, 24),
                              child: Column(
                                children: [
                                  _filterBar(),
                                  const SizedBox(height: 12),
                                  _statsRow(),
                                  const SizedBox(height: 16),
                                  if (_transactions.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 80),
                                      child: Column(
                                        children: [
                                          Icon(
                                              Icons
                                                  .receipt_long_rounded,
                                              size: 72,
                                              color: AppThemeColors
                                                  .secondaryText(
                                                      context)),
                                          const SizedBox(height: 12),
                                          Text(
                                              t('no_transactions_found'),
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  color: AppThemeColors
                                                      .secondaryText(
                                                          context))),
                                        ],
                                      ),
                                    )
                                  else
                                    ..._visibleTransactions.map((tx) =>
                                        _transactionCard(
                                            Map<String,
                                                dynamic>.from(tx))),
                                  if (!_showAll &&
                                      _transactions.length > 10)
                                    TextButton(
                                      onPressed: () => setState(
                                          () => _showAll = true),
                                      child: Text(
                                          '${t('view_all_label')} (${_transactions.length})'),
                                    ),
                                ],
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

  Widget _filterBar() {
    final t = AppLocalizations.of(context).t;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _searchDebounceTimer?.cancel();
                _searchDebounceTimer = Timer(
                  const Duration(milliseconds: 300),
                  _fetchTransactions,
                );
              },
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: t('search_by_email_description_placeholder'),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: AppColors.cyan),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _clearedFilter,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppThemeColors.cardBg(context),
                  labelText: t('cleared'),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(t('all'))),
                  DropdownMenuItem(
                      value: 'cleared', child: Text(t('cleared'))),
                  DropdownMenuItem(
                      value: 'uncleared', child: Text(t('uncleared'))),
                ],
                onChanged: (value) {
                  setState(() => _clearedFilter = value!);
                  _fetchTransactions();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _settlementFilter,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppThemeColors.cardBg(context),
                  labelText: t('settlement_status_label'),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(t('all'))),
                  DropdownMenuItem(value: 'none', child: Text(t('none'))),
                  DropdownMenuItem(
                      value: 'pending', child: Text(t('pending'))),
                  DropdownMenuItem(
                      value: 'accepted', child: Text(t('accepted'))),
                  DropdownMenuItem(
                      value: 'rejected', child: Text(t('rejected'))),
                ],
                onChanged: (value) {
                  setState(() => _settlementFilter = value!);
                  _fetchTransactions();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _sortBy,
                style: TextStyle(color: AppThemeColors.primaryText(context)),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppThemeColors.cardBg(context),
                  labelText: t('sort'),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'latest', child: Text(t('latest_label'))),
                  DropdownMenuItem(
                      value: 'amount_high',
                      child: Text('${t('amount_high')} ↓')),
                  DropdownMenuItem(
                      value: 'amount_low',
                      child: Text('${t('amount_low')} ↑')),
                ],
                onChanged: (value) {
                  setState(() => _sortBy = value!);
                  _fetchTransactions();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statsRow() {
    final t = AppLocalizations.of(context).t;
    final clearedCount =
        _transactions.where((tx) => tx['cleared'] == true).length;
    final pendingCount = _transactions
        .where((tx) => tx['settlementStatus'] == 'pending')
        .length;
    final stats = [
      (t('total_label'), '${_transactions.length}', Icons.receipt_rounded),
      (t('cleared'), '$clearedCount', Icons.check_circle_rounded),
      (t('pending'), '$pendingCount', Icons.pending_rounded),
    ];
    return Row(
      children: List.generate(stats.length, (i) {
        final item = stats[i];
        final bg = AppThemeColors.tinted(
          context,
          light: i == 0
              ? const Color(0xFFFFF4E6)
              : i == 1
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFE3F2FD),
          dark: i == 0
              ? const Color(0xFF4A3A1F)
              : i == 1
                  ? const Color(0xFF1E3A26)
                  : const Color(0xFF1B3A57),
        );
        return Expanded(
          child: Container(
            margin:
                EdgeInsets.only(right: i == stats.length - 1 ? 0 : 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(item.$3, color: AppColors.cyan),
                const SizedBox(height: 6),
                Text(item.$2,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context))),
                Text(item.$1,
                    style: TextStyle(
                        color: AppThemeColors.secondaryText(context),
                        fontSize: 12)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _transactionCard(Map<String, dynamic> tx) {
    final t = AppLocalizations.of(context).t;
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = tx['currency'] ?? 'INR';
    final description = tx['description'] ?? '';
    final creatorEmail = tx['creatorEmail'] ?? t('unknown');
    final users = List<String>.from(tx['users'] ?? []);
    final cleared = tx['cleared'] == true;
    final settlementStatus = tx['settlementStatus'] ?? 'none';
    final role = tx['role'] ?? '';
    final roleLabel = role == 'lender'
        ? t('lender')
        : role == 'borrower'
            ? t('borrower')
            : role.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: AppThemeColors.cardBg(context),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: cleared
                  ? Colors.green.withValues(alpha: 0.15)
                  : AppColors.cyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              cleared
                  ? Icons.check_circle_rounded
                  : Icons.swap_horiz_rounded,
              color: cleared ? Colors.green : AppColors.cyan,
            ),
          ),
          title: Text(
            '${amount.toStringAsFixed(2)} $currency',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppThemeColors.primaryText(context)),
          ),
          subtitle: Text(
            description.isNotEmpty ? description : t('no_description'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppThemeColors.secondaryText(context)),
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text(cleared ? t('cleared') : t('uncleared')),
                  backgroundColor: cleared
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.orange.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: cleared
                        ? Colors.green[700]
                        : Colors.orange[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(
                  label: Text(
                      '${t('settlement_colon')} $settlementStatus'),
                  backgroundColor: _settlementColor(settlementStatus)
                      .withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: _settlementColor(settlementStatus),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (role.isNotEmpty)
                  Chip(
                    label: Text(roleLabel),
                    backgroundColor: AppThemeColors.tinted(context,
                        light: const Color(0xFFEDF4FF),
                        dark: const Color(0xFF1B3A57)),
                    labelStyle:
                        const TextStyle(color: Color(0xFF2563EB)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(context,
                    light: const Color(0xFFEFF8FC),
                    dark: const Color(0xFF1B3A4A)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${t('creator_colon')} $creatorEmail',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context))),
                  if (users.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('${t('users_colon')} ${users.join(', ')}',
                        style: TextStyle(
                            color: AppThemeColors.primaryText(context))),
                  ],
                  const SizedBox(height: 4),
                  Text(
                      '${t('date_colon')} ${tx['date'] ?? t('unknown')}  ${t('time_colon')} ${tx['time'] ?? ''}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text(
                      '${t('created_colon')} ${_formatDate(tx['createdAt'])}',
                      style: TextStyle(
                          color: AppThemeColors.primaryText(context))),
                  const SizedBox(height: 4),
                  Text('${t('id_colon')} ${tx['_id']}',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppThemeColors.mutedText(context))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditDialog(tx),
                    icon: const Icon(Icons.edit_rounded),
                    label: Text(t('edit')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showDeleteConfirmationDialog(tx['_id']),
                    icon: const Icon(Icons.delete_rounded,
                        color: Colors.red),
                    label: Text(t('delete'),
                        style: const TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
