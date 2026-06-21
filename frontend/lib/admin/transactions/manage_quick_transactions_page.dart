import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';

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
          _error = data['message'] ?? 'Failed to load transactions.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'An error occurred: $e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteTransaction(String id) async {
    final response =
        await ApiClient.delete('/api/admin/quick-transactions/$id');
    if (response.statusCode == 200) {
      _showSnackBar('Transaction deleted successfully.');
      _fetchTransactions();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['message'] ?? 'Failed to delete transaction.');
  }

  Future<void> _updateTransaction(
      String id, Map<String, dynamic> body) async {
    final response = await ApiClient.put(
      '/api/admin/quick-transactions/$id',
      body: body,
    );
    if (response.statusCode == 200) {
      _showSnackBar('Transaction updated successfully.');
      _fetchTransactions();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['message'] ?? 'Failed to update transaction.');
  }

  void _showDeleteConfirmationDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        contentPadding: EdgeInsets.zero,
        content: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFF5F5), Color(0xFFFFFFFF)],
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
                  color: const Color(0xFFFFE3E3),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.red,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Delete Transaction',
                style:
                    TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to permanently delete this quick transaction?',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.4),
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
                      child: const Text('Cancel'),
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
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
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
                    child: const Row(
                      children: [
                        Icon(Icons.edit_rounded, color: Colors.white),
                        SizedBox(width: 10),
                        Text(
                          'Edit Quick Transaction',
                          style: TextStyle(
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
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: currencyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.swap_horiz_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'lender', child: Text('Lender')),
                      DropdownMenuItem(
                          value: 'borrower', child: Text('Borrower')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => role = value ?? role),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: settlementStatus,
                    decoration: const InputDecoration(
                      labelText: 'Settlement Status',
                      prefixIcon: Icon(Icons.handshake_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'none', child: Text('None')),
                      DropdownMenuItem(
                          value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(
                          value: 'accepted', child: Text('Accepted')),
                      DropdownMenuItem(
                          value: 'rejected', child: Text('Rejected')),
                    ],
                    onChanged: (value) => setDialogState(
                        () => settlementStatus = value ?? settlementStatus),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: cleared,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cleared'),
                    subtitle: const Text('Mark as settled/cleared'),
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
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount = double.tryParse(
                                amountCtrl.text.trim());
                            if (amount == null || amount <= 0) {
                              _showSnackBar('Enter a valid amount.');
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
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message) => showSnack(context, message);

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Unknown';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(height: context.sh(156), color: AppColors.cyan),
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
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Manage Quick Transactions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: Colors.black),
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
                                    const Padding(
                                      padding:
                                          EdgeInsets.only(top: 80),
                                      child: Column(
                                        children: [
                                          Icon(
                                              Icons
                                                  .receipt_long_rounded,
                                              size: 72,
                                              color: Colors.grey),
                                          SizedBox(height: 12),
                                          Text(
                                              'No transactions found',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey)),
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
                                          'View All (${_transactions.length})'),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _searchDebounceTimer?.cancel();
                _searchDebounceTimer = Timer(
                  const Duration(milliseconds: 300),
                  _fetchTransactions,
                );
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search by email, description...',
                prefixIcon:
                    Icon(Icons.search_rounded, color: AppColors.cyan),
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
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: 'Cleared',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('All')),
                  DropdownMenuItem(
                      value: 'cleared', child: Text('Cleared')),
                  DropdownMenuItem(
                      value: 'uncleared',
                      child: Text('Uncleared')),
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
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: 'Settlement',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('All')),
                  DropdownMenuItem(
                      value: 'none', child: Text('None')),
                  DropdownMenuItem(
                      value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(
                      value: 'accepted', child: Text('Accepted')),
                  DropdownMenuItem(
                      value: 'rejected', child: Text('Rejected')),
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
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: 'Sort',
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'latest', child: Text('Latest')),
                  DropdownMenuItem(
                      value: 'amount_high',
                      child: Text('Amount ↓')),
                  DropdownMenuItem(
                      value: 'amount_low',
                      child: Text('Amount ↑')),
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
    final clearedCount =
        _transactions.where((t) => t['cleared'] == true).length;
    final pendingCount = _transactions
        .where((t) => t['settlementStatus'] == 'pending')
        .length;
    final stats = [
      ('Total', '${_transactions.length}', Icons.receipt_rounded),
      ('Cleared', '$clearedCount', Icons.check_circle_rounded),
      ('Pending', '$pendingCount', Icons.pending_rounded),
    ];
    return Row(
      children: List.generate(stats.length, (i) {
        final item = stats[i];
        return Expanded(
          child: Container(
            margin:
                EdgeInsets.only(right: i == stats.length - 1 ? 0 : 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: i == 0
                  ? const Color(0xFFFFF4E6)
                  : i == 1
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(item.$3, color: AppColors.cyan),
                const SizedBox(height: 6),
                Text(item.$2,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(item.$1,
                    style: TextStyle(
                        color: Colors.grey[700], fontSize: 12)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _transactionCard(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final currency = tx['currency'] ?? 'INR';
    final description = tx['description'] ?? '';
    final creatorEmail = tx['creatorEmail'] ?? 'Unknown';
    final users = List<String>.from(tx['users'] ?? []);
    final cleared = tx['cleared'] == true;
    final settlementStatus = tx['settlementStatus'] ?? 'none';
    final role = tx['role'] ?? '';

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
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            description.isNotEmpty ? description : 'No description',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[600]),
          ),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  label: Text(cleared ? 'Cleared' : 'Uncleared'),
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
                  label: Text('Settlement: $settlementStatus'),
                  backgroundColor: _settlementColor(settlementStatus)
                      .withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: _settlementColor(settlementStatus),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (role.isNotEmpty)
                  Chip(
                    label: Text(
                        role[0].toUpperCase() + role.substring(1)),
                    backgroundColor: const Color(0xFFEDF4FF),
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
                color: const Color(0xFFEFF8FC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Creator: $creatorEmail'),
                  if (users.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Users: ${users.join(', ')}'),
                  ],
                  const SizedBox(height: 4),
                  Text(
                      'Date: ${tx['date'] ?? 'Unknown'}  Time: ${tx['time'] ?? ''}'),
                  const SizedBox(height: 4),
                  Text('Created: ${_formatDate(tx['createdAt'])}'),
                  const SizedBox(height: 4),
                  Text('ID: ${tx['_id']}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey)),
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
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showDeleteConfirmationDialog(tx['_id']),
                    icon: const Icon(Icons.delete_rounded,
                        color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
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
