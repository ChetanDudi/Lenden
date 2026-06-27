import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_colors.dart';
import '../../../widgets/app_widgets.dart';

class RecurringTemplatesPage extends StatefulWidget {
  const RecurringTemplatesPage({super.key});

  @override
  State<RecurringTemplatesPage> createState() => _RecurringTemplatesPageState();
}

class _RecurringTemplatesPageState extends State<RecurringTemplatesPage> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
  }

  Future<void> _fetchTemplates() async {
    setState(() => _loading = true);
    try {
      final res = await ApiClient.get('/api/recurring-templates/mine');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _templates = List<Map<String, dynamic>>.from(data['templates'] ?? []);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> template) async {
    try {
      final res = await ApiClient.patch('/api/recurring-templates/${template['_id']}',
          body: {'isActive': !(template['isActive'] == true)});
      if (res.statusCode == 200) {
        _fetchTemplates();
      } else {
        showSnack(context, 'Failed to update template.', isError: true);
      }
    } catch (e) {
      showSnack(context, 'Error: $e', isError: true);
    }
  }

  Future<void> _deleteTemplate(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Template', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will stop future automatic quick transactions for this template.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await ApiClient.delete('/api/recurring-templates/$id');
      if (res.statusCode == 200) {
        _fetchTemplates();
      } else {
        showSnack(context, 'Failed to delete template.', isError: true);
      }
    } catch (e) {
      showSnack(context, 'Error: $e', isError: true);
    }
  }

  void _showCreateDialog() {
    final emailController = TextEditingController();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String role = 'lender';
    String frequency = 'weekly';
    DateTime startDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New Recurring Template',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.cyan)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Counterparty Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'lender', child: Text('I am lending')),
                      DropdownMenuItem(value: 'borrower', child: Text('I am borrowing')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => role = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: frequency,
                    decoration: InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => frequency = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('First run date'),
                    subtitle: Text(DateFormat('MMM dd, yyyy').format(startDate)),
                    trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setDialogState(() => startDate = picked);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final amount = double.tryParse(amountController.text.trim());
                          if (emailController.text.trim().isEmpty || amount == null || amount <= 0) {
                            showSnack(context, 'Enter a valid email and amount.', isError: true);
                            return;
                          }
                          Navigator.of(context).pop();
                          await _createTemplate(
                            counterpartyEmail: emailController.text.trim(),
                            amount: amount,
                            description: descriptionController.text.trim(),
                            role: role,
                            frequency: frequency,
                            startDate: startDate,
                          );
                        },
                        child: const Text('Create', style: TextStyle(color: Colors.white)),
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

  Future<void> _createTemplate({
    required String counterpartyEmail,
    required double amount,
    required String description,
    required String role,
    required String frequency,
    required DateTime startDate,
  }) async {
    try {
      final res = await ApiClient.post('/api/recurring-templates', body: {
        'counterpartyEmail': counterpartyEmail,
        'amount': amount,
        'currency': 'INR',
        'description': description,
        'role': role,
        'frequency': frequency,
        'startDate': startDate.toIso8601String(),
      });
      if (res.statusCode == 201) {
        showSnack(context, 'Recurring template created.');
        _fetchTemplates();
      } else {
        final data = jsonDecode(res.body);
        showSnack(context, data['error'] ?? 'Failed to create template.', isError: true);
      }
    } catch (e) {
      showSnack(context, 'Error: $e', isError: true);
    }
  }

  String _label(String value) => value
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text('Recurring Templates',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.cyan,
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _templates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.repeat_rounded, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No recurring templates yet.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Tap + to automate a recurring quick transaction.',
                          style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchTemplates,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _templates.length,
                    itemBuilder: (context, index) {
                      final t = _templates[index];
                      final isActive = t['isActive'] == true;
                      final nextRun = DateTime.tryParse((t['nextRunAt'] ?? '').toString());
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
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
                                  child: Text(
                                    '${t['currency'] ?? ''} ${t['amount']} • ${t['counterpartyEmail']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                Switch(
                                  value: isActive,
                                  activeColor: AppColors.cyan,
                                  onChanged: (_) => _toggleActive(t),
                                ),
                              ],
                            ),
                            if ((t['description'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(t['description'], style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${_label((t['role'] ?? '').toString())} • ${_label((t['frequency'] ?? '').toString())}'
                              '${nextRun != null ? ' • Next: ${DateFormat('MMM dd, yyyy').format(nextRun)}' : ''}',
                              style: TextStyle(color: Colors.grey[500], fontSize: 11),
                            ),
                            if (!isActive && (t['pausedReason'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('Paused: ${t['pausedReason']}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A00))),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _deleteTemplate(t['_id']),
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
