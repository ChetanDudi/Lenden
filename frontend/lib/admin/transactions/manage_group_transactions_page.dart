import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import '../../utils/api_client.dart';

class ManageGroupTransactionsPage extends StatefulWidget {
  const ManageGroupTransactionsPage({super.key});

  @override
  State<ManageGroupTransactionsPage> createState() =>
      _ManageGroupTransactionsPageState();
}

class _ManageGroupTransactionsPageState
    extends State<ManageGroupTransactionsPage> {
  final _searchController = TextEditingController();
  Timer? _searchDebounceTimer;
  List<dynamic> groups = [];
  bool loading = true;
  String? error;
  bool _showAll = false;
  String _searchQuery = '';
  String _statusFilter = 'all';
  String _sortBy = 'latest';

  @override
  void initState() {
    super.initState();
    _fetchGroups();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGroups() async {
    setState(() {
      loading = true;
      error = null;
      _showAll = false;
    });
    try {
      final params = <String, String>{};
      if (_searchQuery.trim().isNotEmpty) params['search'] = _searchQuery.trim();
      if (_statusFilter != 'all') params['status'] = _statusFilter;
      // Map UI sort values to API params
      if (_sortBy == 'members') {
        params['sortBy'] = 'memberCount';
        params['sortOrder'] = 'desc';
      } else if (_sortBy == 'expenses') {
        params['sortBy'] = 'expenseCount';
        params['sortOrder'] = 'desc';
      } else {
        params['sortBy'] = 'createdAt';
        params['sortOrder'] = 'desc';
      }
      final query = params.isNotEmpty
          ? '?${params.entries.map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}').join('&')}'
          : '';
      final response = await ApiClient.get('/api/admin/group-transactions$query');
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          groups = data['groups'] ?? [];
          loading = false;
        });
      } else {
        setState(() {
          error = data['error'] ?? 'Failed to load groups.';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'An error occurred: $e';
        loading = false;
      });
    }
  }

  Future<void> _deleteGroup(String groupId) async {
    final response =
        await ApiClient.delete('/api/admin/group-transactions/$groupId');
    if (response.statusCode == 200) {
      _showSnackBar('Group deleted successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to delete group.');
  }

  Future<void> _pickGroupColor({
    required Color initialColor,
    required ValueChanged<Color> onPicked,
  }) async {
    var picked = initialColor;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Text('Pick Group Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: picked,
            onColorChanged: (color) {
              picked = color;
              onPicked(color);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog(String groupId) {
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
                'Delete Group',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to delete this group and all its expenses?',
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
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteGroup(groupId);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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

  Future<void> _showExpenseDialog({
    required String groupId,
    required List<dynamic> members,
    Map<String, dynamic>? expense,
  }) async {
    if (members.isEmpty) {
      _showSnackBar('Cannot add expense: Group has no members.');
      return;
    }

    final descriptionController =
        TextEditingController(text: '${expense?['description'] ?? ''}');
    final amountController = TextEditingController(
        text: expense == null ? '' : '${expense['amount'] ?? ''}');
    final memberEmails = members
        .map((m) => m['email'].toString())
        .where((e) => e.isNotEmpty)
        .toList();
    var paidBy = (expense?['addedBy'] ?? memberEmails.first).toString();
    var splitType = (expense?['splitType'] ?? 'equal').toString();
    final selectedMembers =
        List<String>.from(expense?['selectedMembers'] ?? memberEmails);
    final customSplitAmounts = <String, double>{
      for (final email in memberEmails) email: 0,
    };

    if (expense != null && expense['split'] is List) {
      for (final split in expense['split']) {
        final member = members.cast<Map<String, dynamic>>().firstWhere(
              (m) => '${m['_id']}' == '${split['user']}',
              orElse: () => <String, dynamic>{'email': ''},
            );
        final email = (member['email'] ?? '').toString();
        if (email.isNotEmpty) {
          customSplitAmounts[email] =
              (split['amount'] as num?)?.toDouble() ?? 0;
        }
      }
    }

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
                color: const Color(0xFF00B4D8).withOpacity(0.18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
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
                        colors: [Color(0xFF003049), Color(0xFF00B4D8)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            color: Colors.white),
                        const SizedBox(width: 10),
                        Text(
                          expense == null ? 'Add Expense' : 'Edit Expense',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.description_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.currency_rupee_rounded),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paidBy,
                    decoration: const InputDecoration(
                      labelText: 'Paid By',
                      prefixIcon: Icon(Icons.person_pin_circle_outlined),
                    ),
                    items: memberEmails
                        .map((email) => DropdownMenuItem(
                              value: email,
                              child: Text(email),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => paidBy = value ?? paidBy),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: splitType,
                    decoration: const InputDecoration(
                      labelText: 'Split Type',
                      prefixIcon: Icon(Icons.call_split_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'equal', child: Text('Equal')),
                      DropdownMenuItem(value: 'custom', child: Text('Custom')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => splitType = value ?? 'equal'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text(
                        'Included Members',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            selectedMembers
                              ..clear()
                              ..addAll(memberEmails);
                          });
                        },
                        child: const Text('Select All'),
                      ),
                    ],
                  ),
                  ...memberEmails.map(
                    (email) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(email),
                      value: selectedMembers.contains(email),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selectedMembers.add(email);
                          } else {
                            selectedMembers.remove(email);
                          }
                        });
                      },
                    ),
                  ),
                  if (splitType == 'custom') ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Custom split',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                  ...selectedMembers.map(
                      (email) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextFormField(
                          initialValue:
                              (customSplitAmounts[email] ?? 0).toString(),
                          decoration: InputDecoration(
                            labelText: email,
                            prefixIcon:
                                const Icon(Icons.currency_rupee_rounded),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              customSplitAmounts[email] =
                                  double.tryParse(value) ?? 0;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                  if (splitType == 'custom') ...[
                    const SizedBox(height: 6),
                    Builder(
                      builder: (context) {
                        final totalAmount =
                            double.tryParse(amountController.text.trim()) ?? 0;
                        final remaining = totalAmount -
                            selectedMembers.fold<double>(
                              0,
                              (sum, email) =>
                                  sum + (customSplitAmounts[email] ?? 0),
                            );
                        final balanced = remaining.abs() <= 0.01;
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: balanced
                                ? Colors.green.withOpacity(0.08)
                                : Colors.orange.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'Left amount: ${remaining.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: balanced ? Colors.green : Colors.orange,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            final amount =
                                double.tryParse(amountController.text.trim());
                            if (descriptionController.text.trim().isEmpty) {
                              _showSnackBar('Please enter a description.');
                              return;
                            }
                            if (amount == null || amount <= 0) {
                              _showSnackBar('Please enter a valid amount.');
                              return;
                            }
                            if (selectedMembers.isEmpty) {
                              _showSnackBar(
                                  'Please select at least one member.');
                              return;
                            }

                            dynamic splitPayload;
                            Map<String, dynamic>? customSplitPayload;
                            if (splitType == 'custom') {
                              final total = selectedMembers.fold<double>(
                                0,
                                (sum, email) =>
                                    sum + (customSplitAmounts[email] ?? 0),
                              );
                              if ((total - amount).abs() > 0.01) {
                                _showSnackBar(
                                  'Custom split amounts must match total amount.',
                                );
                                return;
                              }
                              splitPayload = selectedMembers
                                  .map((email) => {
                                        'user': email,
                                        'amount':
                                            customSplitAmounts[email] ?? 0,
                                      })
                                  .toList();
                              customSplitPayload = {
                                for (final email in selectedMembers)
                                  email: customSplitAmounts[email] ?? 0,
                              };
                            } else {
                              final per = amount / selectedMembers.length;
                              splitPayload = selectedMembers
                                  .map((email) => {
                                        'user': email,
                                        'amount': per,
                                      })
                                  .toList();
                            }

                            Navigator.pop(context);
                            final payload = {
                              'description': descriptionController.text.trim(),
                              'amount': amount,
                              'splitType': splitType,
                              'selectedMembers': selectedMembers,
                              'addedByEmail': paidBy,
                              if (splitType == 'custom')
                                'customSplitAmounts': customSplitPayload,
                              if (splitType == 'custom' || expense == null)
                                'split': splitPayload,
                            };

                            if (expense == null) {
                              _addExpense(groupId, payload);
                            } else {
                              _editExpense(groupId, expense['_id'], payload);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00B4D8),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(expense == null ? 'Add' : 'Save'),
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

  Future<void> _updateGroup(String groupId, Map<String, dynamic> body) async {
    final response = await ApiClient.put(
      '/api/admin/group-transactions/$groupId',
      body: body,
    );
    if (response.statusCode == 200) {
      _showSnackBar('Group updated successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to update group.');
  }

  Future<void> _addMember(String groupId, String email) async {
    final response = await ApiClient.post(
      '/api/admin/group-transactions/$groupId/members',
      body: {'email': email},
    );
    if (response.statusCode == 200) {
      _showSnackBar('Member added successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to add member.');
  }

  Future<void> _removeMember(String groupId, String memberId) async {
    final response = await ApiClient.delete(
      '/api/admin/group-transactions/$groupId/members/$memberId',
    );
    if (response.statusCode == 200) {
      _showSnackBar('Member removed successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to remove member.');
  }

  Future<void> _addExpense(String groupId, Map<String, dynamic> body) async {
    final response = await ApiClient.post(
      '/api/admin/group-transactions/$groupId/expenses',
      body: body,
    );
    if (response.statusCode == 200) {
      _showSnackBar('Expense added successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to add expense.');
  }

  Future<void> _editExpense(
      String groupId, String expenseId, Map<String, dynamic> body) async {
    final response = await ApiClient.put(
      '/api/admin/group-transactions/$groupId/expenses/$expenseId',
      body: body,
    );
    if (response.statusCode == 200) {
      _showSnackBar('Expense updated successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to update expense.');
  }

  Future<void> _deleteExpense(String groupId, String expenseId) async {
    final response = await ApiClient.delete(
      '/api/admin/group-transactions/$groupId/expenses/$expenseId',
    );
    if (response.statusCode == 200) {
      _showSnackBar('Expense deleted successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to delete expense.');
  }

  Future<void> _settleExpenseSplits(
      String groupId, String expenseId, List<String> memberEmails) async {
    final response = await ApiClient.post(
      '/api/admin/group-transactions/$groupId/expenses/$expenseId/settle',
      body: {'memberEmails': memberEmails},
    );
    if (response.statusCode == 200) {
      _showSnackBar('Expense splits settled successfully.');
      _fetchGroups();
      return;
    }
    final data = jsonDecode(response.body);
    _showSnackBar(data['error'] ?? 'Failed to settle expense splits.');
  }

  Future<bool> _showExpenseActionConfirmation({
    required String title,
    required String message,
    required Color color,
    required IconData icon,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            contentPadding: EdgeInsets.zero,
            content: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(icon, color: color, size: 34),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(confirmLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF00B4D8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(dynamic raw) {
    if (raw == null) return 'Unknown';
    try {
      return DateFormat('MMM d, yyyy h:mm a')
          .format(DateTime.parse(raw.toString()).toLocal());
    } catch (_) {
      return raw.toString();
    }
  }

  double _groupTotal(List<dynamic> expenses) => expenses.fold<double>(
        0,
        (sum, expense) => sum + ((expense['amount'] as num?)?.toDouble() ?? 0),
      );

  String _extractUserId(dynamic value) {
    if (value is Map<String, dynamic>) {
      return '${value['_id'] ?? value['id'] ?? value['user'] ?? ''}';
    }
    return '$value';
  }

  double _calculateMemberSplitAmount({
    required List<dynamic> expenses,
    required String memberId,
  }) {
    var total = 0.0;

    for (final expense in expenses) {
      final splitItems = expense['split'] as List<dynamic>? ?? const [];
      for (final splitItem in splitItems) {
        if (_extractUserId(splitItem['user']) != memberId) continue;
        if (splitItem['settled'] == true) continue;
        total += (splitItem['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    return total;
  }

  Color _parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) return Colors.blue;
    try {
      var clean = colorString.replaceAll('#', '');
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  List<dynamic> get _visibleGroups =>
      _showAll || groups.length <= 5 ? groups : groups.take(5).toList();

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
              child: Container(height: 60, color: const Color(0xFF00B4D8)),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'Manage Group Transactions',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.black),
                        onPressed: _fetchGroups,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : error != null
                          ? Center(
                              child: Text(error!,
                                  style: const TextStyle(color: Colors.red)))
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              child: Column(
                                children: [
                                  _filterBar(),
                                  const SizedBox(height: 12),
                                  _statsRow(),
                                  const SizedBox(height: 16),
                                  if (groups.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 80),
                                      child: Column(
                                        children: [
                                          Icon(Icons.group_off_rounded,
                                              size: 72, color: Colors.grey),
                                          SizedBox(height: 12),
                                          Text('No groups found',
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  color: Colors.grey)),
                                        ],
                                      ),
                                    )
                                  else
                                    ..._visibleGroups.map((group) => _groupCard(
                                        Map<String, dynamic>.from(group))),
                                  if (!_showAll && groups.length > 5)
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _showAll = true),
                                      child: Text(
                                          'View All (${groups.length})'),
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
                  _fetchGroups,
                );
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Search group, member, creator, id...',
                prefixIcon:
                    Icon(Icons.search_rounded, color: Color(0xFF00B4D8)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _statusFilter,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: 'Status',
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All Groups')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                ],
                onChanged: (value) {
                  setState(() => _statusFilter = value!);
                  _fetchGroups();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _sortBy,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: 'Sort',
                ),
                items: const [
                  DropdownMenuItem(value: 'latest', child: Text('Latest')),
                  DropdownMenuItem(
                      value: 'members', child: Text('Most Members')),
                  DropdownMenuItem(
                      value: 'expenses', child: Text('Most Expenses')),
                ],
                onChanged: (value) {
                  setState(() => _sortBy = value!);
                  _fetchGroups();
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statsRow() {
    final stats = [
      ('Total', '${groups.length}', Icons.groups_2_rounded),
      ('Showing', '${_visibleGroups.length}', Icons.visibility_rounded),
      (
        'Expenses',
        '${groups.fold<int>(0, (s, g) => s + ((g['expenses'] as List?)?.length ?? 0))}',
        Icons.receipt_long_rounded
      ),
    ];
    return Row(
      children: List.generate(stats.length, (i) {
        final item = stats[i];
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == stats.length - 1 ? 0 : 10),
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
                Icon(item.$3, color: const Color(0xFF00B4D8)),
                const SizedBox(height: 6),
                Text(item.$2,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                Text(item.$1,
                    style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _groupCard(Map<String, dynamic> group) {
    final members = (group['members'] as List<dynamic>? ?? const []);
    final expenses = (group['expenses'] as List<dynamic>? ?? const []);
    final balances = (group['balances'] as List<dynamic>? ?? const []);
    final balanceMap = <String, double>{};
    for (final balance in balances) {
      final userId = _extractUserId(balance['user']);
      if (userId.isEmpty) continue;
      balanceMap[userId] =
          (balance['balance'] as num?)?.toDouble() ?? 0;
    }
    final hasAnyStoredBalance =
        balanceMap.values.any((amount) => amount.abs() >= 0.01);
    final selectedColor = _parseColor(group['color']);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            color: selectedColor.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: selectedColor,
            child: Text((group['title'] ?? 'G')
                .toString()
                .substring(0, 1)
                .toUpperCase()),
          ),
          title: Text('${group['title'] ?? 'Untitled Group'}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(
            'Creator: ${group['creator']?['email'] ?? 'Unknown'}\nMembers: ${members.length} • Expenses: ${expenses.length}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                    label: Text(
                        group['isActive'] == false ? 'Inactive' : 'Active')),
                Chip(
                    label: Text(
                        'Total ${_groupTotal(expenses).toStringAsFixed(2)}')),
                Chip(label: Text('Balances ${balances.length}')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final title = TextEditingController(
                          text: '${group['title'] ?? ''}');
                      var pickedColor = selectedColor;
                      bool isActive = group['isActive'] != false;
                      await showDialog(
                        context: context,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setDialogState) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            contentPadding: EdgeInsets.zero,
                            content: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF4FBFD), Colors.white],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF003049),
                                          Color(0xFF00B4D8)
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit_rounded,
                                            color: Colors.white),
                                        SizedBox(width: 10),
                                        Text(
                                          'Edit Group',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextField(
                                    controller: title,
                                    decoration: const InputDecoration(
                                      labelText: 'Title',
                                      prefixIcon: Icon(Icons.title_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _pickGroupColor(
                                      initialColor: pickedColor,
                                      onPicked: (color) {
                                        setDialogState(
                                            () => pickedColor = color);
                                      },
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: pickedColor.withOpacity(0.35),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              color: pickedColor,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              '#${pickedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const Icon(Icons.palette_outlined),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SwitchListTile(
                                    value: isActive,
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Active'),
                                    subtitle:
                                        const Text('Disable without deleting'),
                                    onChanged: (value) =>
                                        setDialogState(() => isActive = value),
                                  ),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel')),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _updateGroup(group['_id'], {
                                    'title': title.text.trim(),
                                    'color':
                                        '#${pickedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                                    'isActive': isActive,
                                  });
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showDeleteConfirmationDialog(group['_id']),
                    icon: const Icon(Icons.delete_rounded, color: Colors.red),
                    label: const Text('Delete',
                        style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
                  Text('Created: ${_formatDate(group['createdAt'])}'),
                  const SizedBox(height: 4),
                  Text('Color: ${group['color'] ?? 'Default'}'),
                  const SizedBox(height: 4),
                  Text('Group ID: ${group['_id']}'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Members (${members.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () {
                    final emailController = TextEditingController();
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        contentPadding: EdgeInsets.zero,
                        content: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF4FBFD), Colors.white],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF003049),
                                      Color(0xFF00B4D8)
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.person_add_alt_1_rounded,
                                        color: Colors.white),
                                    SizedBox(width: 10),
                                    Text(
                                      'Add Member',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Member Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _addMember(group['_id'],
                                            emailController.text.trim());
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF00B4D8),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: const Text('Add'),
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
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add'),
                ),
              ],
            ),
            ...members.map((member) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        member['leftAt'] == null ? Colors.green : Colors.grey,
                    child: Icon(
                      member['leftAt'] == null
                          ? Icons.person_rounded
                          : Icons.person_off_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: Text('${member['email']}'),
                  subtitle: Text(
                    member['leftAt'] == null
                        ? 'Joined ${_formatDate(member['joinedAt'])}'
                        : 'Left ${_formatDate(member['leftAt'])}',
                  ),
                  trailing: member['leftAt'] == null
                      ? IconButton(
                          icon: const Icon(Icons.person_remove_rounded,
                              color: Colors.red),
                          onPressed: () =>
                              _removeMember(group['_id'], '${member['_id']}'),
                        )
                      : null,
                )),
            const SizedBox(height: 14),
            Text('Balances (${members.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            ...members.map((member) {
              final email = (member['email'] ?? 'Unknown').toString();
              final memberId = '${member['_id']}';
              final calculatedAmount = _calculateMemberSplitAmount(
                expenses: expenses,
                memberId: memberId,
              );
              final amount = hasAnyStoredBalance
                  ? (balanceMap[memberId] ?? calculatedAmount)
                  : calculatedAmount;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  amount.abs() < 0.01
                      ? Icons.check_circle_rounded
                      : Icons.pending_actions_rounded,
                  color: amount.abs() < 0.01 ? Colors.green : Colors.orange,
                ),
                title: Text('$email'),
                trailing: Text(
                  amount.toStringAsFixed(2),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: amount.abs() < 0.01 ? Colors.green : Colors.red,
                  ),
                ),
              );
            }),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Expenses (${expenses.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: members.isEmpty
                      ? null
                      : () => _showExpenseDialog(
                            groupId: group['_id'],
                            members: members,
                          ),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Add'),
                ),
              ],
            ),
            ...expenses.map((expense) {
              final splitItems = expense['split'] as List<dynamic>? ?? const [];
              final unsettledMembers = <String>[];
              for (final split in splitItems) {
                if (split['settled'] != true) {
                  final member =
                      members.cast<Map<String, dynamic>>().firstWhere(
                            (m) => '${m['_id']}' == '${split['user']}',
                            orElse: () => <String, dynamic>{'email': ''},
                          );
                  if ((member['email'] ?? '').toString().isNotEmpty) {
                    unsettledMembers.add(member['email'].toString());
                  }
                }
              }
              return Card(
                margin: const EdgeInsets.only(top: 8),
                color: const Color(0xFFF9FBFE),
                child: ListTile(
                  title: Text('${expense['description'] ?? 'No description'}'),
                  subtitle: Text(
                    'Added by ${expense['addedBy'] ?? 'Unknown'}\n'
                    'Amount ${((expense['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}\n'
                    'Date ${_formatDate(expense['date'] ?? expense['createdAt'])}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit_rounded,
                            color: Colors.orange),
                        onPressed: () => _showExpenseDialog(
                          groupId: group['_id'],
                          members: members,
                          expense: Map<String, dynamic>.from(expense),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.check_box_rounded,
                            color: Colors.green),
                        onPressed: unsettledMembers.isEmpty
                            ? null
                            : () async {
                                final confirm =
                                    await _showExpenseActionConfirmation(
                                  title: 'Settle Expense',
                                  message:
                                      'Mark the pending selected splits as settled?',
                                  color: Colors.green,
                                  icon: Icons.check_box_rounded,
                                  confirmLabel: 'Settle',
                                );
                                if (!confirm) return;
                                _settleExpenseSplits(
                                  group['_id'],
                                  expense['_id'],
                                  unsettledMembers,
                                );
                              },
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.delete_rounded, color: Colors.red),
                        onPressed: () async {
                          final confirm = await _showExpenseActionConfirmation(
                            title: 'Delete Expense',
                            message:
                                'Are you sure you want to delete this expense?',
                            color: Colors.red,
                            icon: Icons.delete_rounded,
                            confirmLabel: 'Delete',
                          );
                          if (!confirm) return;
                          _deleteExpense(group['_id'], expense['_id']);
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.5,
        size.width * 0.5, size.height * 0.4);
    path.quadraticBezierTo(
        size.width * 0.75, size.height * 0.3, size.width, size.height * 0.4);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
