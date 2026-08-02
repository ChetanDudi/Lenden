import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../../utils/api_client.dart';
import '../../../utils/theme_helper.dart';
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
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _fetchTemplates();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      final res = await ApiClient.get('/api/friends');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
        });
      }
    } catch (_) {}
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF00BCD4), Color(0xFF4CAF50), Color(0xFFFF9800),
      Color(0xFF9C27B0), Color(0xFFE91E63), Color(0xFF2196F3),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name, String email) {
    final src = name.isNotEmpty ? name : email;
    final parts = src.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return src.isNotEmpty ? src[0].toUpperCase() : '?';
  }

  Future<void> _pickFriend(TextEditingController ctrl, StateSetter setDialogState) async {
    if (_friends.isEmpty) return;
    String q = '';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = _friends.where((f) {
            final email = (f['email'] ?? '').toString().toLowerCase();
            final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
            return q.isEmpty || email.contains(q) || name.contains(q);
          }).toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.65,
            minChildSize: 0.4,
            maxChildSize: 0.92,
            builder: (_, scrollController) => Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.cyan.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.people_rounded, color: AppColors.cyan, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text('Select Friend',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: Icon(Icons.close, color: AppThemeColors.mutedText(ctx), size: 22),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: false,
                      onChanged: (v) => setSheetState(() => q = v.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search by name or email',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('No friends found', style: TextStyle(color: AppThemeColors.mutedText(ctx))))
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, idx) {
                              final f = filtered[idx];
                              final email = (f['email'] ?? '').toString();
                              final name = (f['name'] ?? f['username'] ?? '').toString();
                              final color = _avatarColor(name.isNotEmpty ? name : email);
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() => ctrl.text = email);
                                  Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppThemeColors.surfaceBg(ctx),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppThemeColors.border(ctx)),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: color.withValues(alpha: 0.18),
                                        child: Text(_initials(name, email),
                                            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name.isNotEmpty ? name : email,
                                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (name.isNotEmpty)
                                              Text(email,
                                                  style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(ctx)),
                                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
    List<Map<String, dynamic>> suggestions = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          backgroundColor: AppThemeColors.cardBg(context),
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
                    onChanged: (val) {
                      final q = val.trim().toLowerCase();
                      final matches = _friends.where((f) {
                        final email = (f['email'] ?? '').toString().toLowerCase();
                        final name = (f['name'] ?? f['username'] ?? '').toString().toLowerCase();
                        return q.isNotEmpty && (email.contains(q) || name.contains(q));
                      }).take(5).toList();
                      setDialogState(() => suggestions = matches);
                    },
                    decoration: InputDecoration(
                      labelText: 'Counterparty Email',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.people_rounded, color: AppColors.cyan),
                        tooltip: 'Pick from friends',
                        onPressed: () => _pickFriend(emailController, setDialogState),
                      ),
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.surfaceBg(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppThemeColors.border(context)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: suggestions.map((f) {
                          final email = (f['email'] ?? '').toString();
                          final name = (f['name'] ?? f['username'] ?? '').toString();
                          final color = _avatarColor(name.isNotEmpty ? name : email);
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: color.withValues(alpha: 0.18),
                              child: Text(_initials(name, email),
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            title: Text(name.isNotEmpty ? name : email,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            subtitle: name.isNotEmpty
                                ? Text(email, style: const TextStyle(fontSize: 11))
                                : null,
                            onTap: () => setDialogState(() {
                              emailController.text = email;
                              suggestions = [];
                            }),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
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
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text('Recurring Templates',
            style: TextStyle(color: AppThemeColors.primaryText(context), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppThemeColors.primaryText(context)),
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
                              Text(t['description'], style: TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13)),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              '${_label((t['role'] ?? '').toString())} • ${_label((t['frequency'] ?? '').toString())}'
                              '${nextRun != null ? ' • Next: ${DateFormat('MMM dd, yyyy').format(nextRun)}' : ''}',
                              style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 11),
                            ),
                            if (!isActive && (t['pausedReason'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppThemeColors.tinted(context, light: const Color(0xFFFFF3E0), dark: const Color(0xFF2B1A00)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('Paused: ${t['pausedReason']}',
                                    style: TextStyle(fontSize: 12, color: AppThemeColors.isDark(context) ? Colors.orange[400]! : const Color(0xFF8A5A00))),
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
