import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

class ManageUpdatesPage extends StatefulWidget {
  const ManageUpdatesPage({super.key});

  @override
  State<ManageUpdatesPage> createState() => _ManageUpdatesPageState();
}

class _ManageUpdatesPageState extends State<ManageUpdatesPage>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _bodyController = TextEditingController();
  final _versionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _platformsController = TextEditingController();

  late final TabController _tabController;
  bool _pinned = false;
  bool _loading = true;
  bool _submitting = false;
  bool _showAll = false;
  String _filter = 'all';
  String? _error;
  String? _editingId;
  String _category = 'general';
  String _importance = 'normal';
  String _targetAudience = 'all';
  String _status = 'published';
  final _scheduledForController = TextEditingController();
  List<Map<String, dynamic>> _updates = [];

  bool get _isEditing => _editingId != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUpdates();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _summaryController.dispose();
    _bodyController.dispose();
    _versionController.dispose();
    _tagsController.dispose();
    _platformsController.dispose();
    _scheduledForController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUpdates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/app-updates');
      final data = jsonDecode(res.body);
      if (res.statusCode != 200) {
        throw Exception((data['error'] ?? 'Failed to load updates').toString());
      }
      setState(() {
        _updates = List<Map<String, dynamic>>.from(
          (data['updates'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startEditing(Map<String, dynamic> update) {
    setState(() {
      _editingId = update['_id']?.toString();
      _titleController.text = (update['title'] ?? '').toString();
      _summaryController.text = (update['summary'] ?? '').toString();
      _bodyController.text = (update['body'] ?? '').toString();
      _versionController.text = (update['versionTag'] ?? '').toString();
      _tagsController.text =
          ((update['tags'] as List?) ?? const []).map((e) => '$e').join(', ');
      _category = (update['category'] ?? 'general').toString();
      _importance = (update['importance'] ?? 'normal').toString();
      _targetAudience = (update['targetAudience'] ?? 'all').toString();
      _status = (update['status'] ?? 'published').toString();
      _platformsController.text =
          ((update['platforms'] as List?) ?? const ['all']).map((e) => '$e').join(', ');
      _scheduledForController.text = _toEditableDateTime(update['scheduledFor']);
      _pinned = update['pinned'] == true;
      _error = null;
    });
    _tabController.animateTo(0);
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _titleController.clear();
      _summaryController.clear();
      _bodyController.clear();
      _versionController.clear();
      _tagsController.clear();
      _platformsController.text = 'all';
      _scheduledForController.clear();
      _category = 'general';
      _importance = 'normal';
      _targetAudience = 'all';
      _status = 'published';
      _pinned = false;
      _error = null;
    });
  }

  Future<void> _submitUpdate() async {
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      setState(() => _error = 'Title and body are required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final body = {
        'title': _titleController.text.trim(),
        'summary': _summaryController.text.trim(),
        'body': _bodyController.text.trim(),
        'versionTag': _versionController.text.trim(),
        'category': _category,
        'importance': _importance,
        'targetAudience': _targetAudience,
        'status': _status,
        'scheduledFor': _scheduledForController.text.trim(),
        'platforms': _platformsController.text.trim(),
        'tags': _tagsController.text.trim(),
        'pinned': _pinned,
      };

      final res = _isEditing
          ? await ApiClient.put('/api/admin/app-updates/$_editingId', body: body)
          : await ApiClient.post('/api/admin/app-updates', body: body);
      final data = jsonDecode(res.body);
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw Exception((data['error'] ?? 'Failed to save update').toString());
      }

      final message = _isEditing
          ? 'Update edited successfully.'
          : 'Update published successfully.';
      _resetForm();
      await _loadUpdates();
      if (!mounted) return;
      _showStylishMessage(message, false);
      _tabController.animateTo(1);
    } catch (e) {
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = errorMessage);
      if (mounted) _showStylishMessage(errorMessage, true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _toEditableDateTime(dynamic rawValue) {
    final parsed = DateTime.tryParse(rawValue?.toString() ?? '')?.toLocal();
    if (parsed == null) return '';
    return _toApiDateTime(parsed);
  }

  String _toApiDateTime(DateTime value) => value.toUtc().toIso8601String();

  Future<void> _pickDateTime({
    required TextEditingController controller,
    required String title,
  }) async {
    final initial =
        DateTime.tryParse(controller.text.trim())?.toLocal() ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      helpText: title,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '$title Time',
    );
    if (time == null || !mounted) return;

    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      controller.text = _toApiDateTime(combined);
    });
  }

  Future<void> _confirmDelete(Map<String, dynamic> update) async {
    final shouldDelete = await _showConfirmDialog(
      title: 'Delete Update?',
      message:
          'Are you sure you want to delete "${(update['title'] ?? '').toString()}"?',
      confirmLabel: 'Delete',
      confirmColor: Colors.redAccent,
    );

    if (shouldDelete == true) {
      final res =
          await ApiClient.delete('/api/admin/app-updates/${update['_id']}');
      final data = jsonDecode(res.body);
      if (res.statusCode != 200) {
        if (!mounted) return;
        _showStylishMessage(
          (data['error'] ?? 'Failed to delete update').toString(),
          true,
        );
        return;
      }
      await _loadUpdates();
      if (!mounted) return;
      _showStylishMessage('Update deleted successfully.', false);
      if (_editingId == update['_id']?.toString()) _resetForm();
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.help_outline, color: confirmColor, size: 42),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: 18),
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
                        style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
                        child: Text(confirmLabel),
                      ),
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

  void _showStylishMessage(String message, bool isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: isError ? Colors.redAccent : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isError ? Colors.redAccent : Colors.green.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredUpdates {
    final items = _updates.where((update) {
      switch (_filter) {
        case 'mine':
          return _canManageUpdate(update);
        case 'pinned':
          return update['pinned'] == true;
        case 'draft':
          return (update['status'] ?? 'published').toString() == 'draft';
        case 'scheduled':
          return (update['status'] ?? 'published').toString() == 'scheduled';
        case 'critical':
          return (update['importance'] ?? 'normal').toString() == 'critical';
        default:
          return true;
      }
    }).toList();

    return _showAll ? items : items.take(3).toList();
  }

  bool _canManageUpdate(Map<String, dynamic> update) {
    if (update['canManage'] == true) return true;

    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentAdmin = session.user ?? const <String, dynamic>{};
    if (currentAdmin['isSuperAdmin'] == true) return true;

    final createdBy = update['createdBy'];
    final createdById =
        createdBy is Map ? createdBy['_id']?.toString() : createdBy?.toString();
    final currentAdminId = currentAdmin['_id']?.toString();
    return createdById != null && createdById == currentAdminId;
  }

  Map<String, int> get _updateSummary {
    final summary = {
      'published': 0,
      'draft': 0,
      'scheduled': 0,
      'reads': 0,
      'critical': 0,
    };

    for (final update in _updates) {
      final status = (update['status'] ?? 'published').toString();
      if (summary.containsKey(status)) {
        summary[status] = summary[status]! + 1;
      }
      summary['reads'] =
          summary['reads']! + (((update['stats'] ?? {})['readCount'] ?? 0) as int);
      if ((update['importance'] ?? 'normal').toString() == 'critical') {
        summary['critical'] = summary['critical']! + 1;
      }
    }

    return summary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 165,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      const Expanded(
                        child: Text(
                          'Manage Updates',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF00B4D8),
                        unselectedLabelColor: Colors.black54,
                        indicator: BoxDecoration(
                          color: const Color(0xFFEAF5FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        tabs: const [
                          Tab(text: 'Create'),
                          Tab(text: 'Manage'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      RefreshIndicator(
                        onRefresh: _loadUpdates,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [_buildComposer()],
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadUpdates,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildManageHeader(),
                            const SizedBox(height: 12),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(top: 40),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00B4D8),
                                  ),
                                ),
                              )
                            else if (_filteredUpdates.isEmpty)
                              _buildEmptyState()
                            else
                              ..._filteredUpdates.map(_buildUpdateCard),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit Update' : 'Publish New Update',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryController,
              decoration: const InputDecoration(
                labelText: 'Short Summary',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _versionController,
              decoration: const InputDecoration(
                labelText: 'Version Tag',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General')),
                DropdownMenuItem(value: 'feature', child: Text('Feature')),
                DropdownMenuItem(value: 'bug_fix', child: Text('Bug Fix')),
                DropdownMenuItem(value: 'security', child: Text('Security')),
                DropdownMenuItem(value: 'maintenance', child: Text('Maintenance')),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'general'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _importance,
              decoration: const InputDecoration(
                labelText: 'Importance',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'normal', child: Text('Normal')),
                DropdownMenuItem(value: 'important', child: Text('Important')),
                DropdownMenuItem(value: 'critical', child: Text('Critical')),
              ],
              onChanged: (value) =>
                  setState(() => _importance = value ?? 'normal'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _targetAudience,
              decoration: const InputDecoration(
                labelText: 'Audience',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Users')),
                DropdownMenuItem(value: 'subscribed', child: Text('Subscribed Only')),
                DropdownMenuItem(value: 'nonsubscribed', child: Text('Non-Subscribed Only')),
              ],
              onChanged: (value) =>
                  setState(() => _targetAudience = value ?? 'all'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Publish Status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'published', child: Text('Publish Now')),
                DropdownMenuItem(value: 'draft', child: Text('Save as Draft')),
                DropdownMenuItem(value: 'scheduled', child: Text('Schedule for Later')),
              ],
              onChanged: (value) =>
                  setState(() => _status = value ?? 'published'),
            ),
            if (_status == 'scheduled') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _scheduledForController,
                readOnly: true,
                onTap: () => _pickDateTime(
                  controller: _scheduledForController,
                  title: 'Select Schedule Date',
                ),
                decoration: InputDecoration(
                  labelText: 'Scheduled For',
                  hintText: 'Tap to choose date and time',
                  border: const OutlineInputBorder(),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_scheduledForController.text.trim().isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () =>
                              setState(() => _scheduledForController.clear()),
                        ),
                      IconButton(
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: () => _pickDateTime(
                          controller: _scheduledForController,
                          title: 'Select Schedule Date',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'security, release, dashboard',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _platformsController,
              decoration: const InputDecoration(
                labelText: 'Platforms',
                hintText: 'all, windows, android, ios, web',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Update Details',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              title: const Text('Pin this update'),
              onChanged: (value) => setState(() => _pinned = value),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              children: [
                if (_isEditing)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : _resetForm,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel Edit'),
                    ),
                  ),
                if (_isEditing) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _submitting
                          ? (_isEditing ? 'Saving...' : 'Publishing...')
                          : (_isEditing ? 'Save Changes' : 'Publish Update'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Published Updates',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildSummaryChip('Published', '${_updateSummary['published']}'),
              _buildSummaryChip('Drafts', '${_updateSummary['draft']}'),
              _buildSummaryChip('Scheduled', '${_updateSummary['scheduled']}'),
              _buildSummaryChip('Reads', '${_updateSummary['reads']}'),
              _buildSummaryChip('Critical', '${_updateSummary['critical']}'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFilterChip('all', 'All'),
              _buildFilterChip('mine', 'Mine'),
              _buildFilterChip('pinned', 'Pinned'),
              _buildFilterChip('draft', 'Drafts'),
              _buildFilterChip('scheduled', 'Scheduled'),
              _buildFilterChip('critical', 'Critical'),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? 'Show Latest 3' : 'View All'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFFEAF5FF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF00B4D8) : Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: Color(0xFF00B4D8),
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Text(
        'No updates found for this filter.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
      ),
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final createdBy = update['createdBy'];
    final createdByEmail =
        createdBy is Map ? (createdBy['email'] ?? '').toString() : '';
    final publishedAt = _formatDateTime(update['publishedAt']);
    final editedAt = _formatDateTime(update['updatedAt']);
    final wasEdited = (update['updatedAt'] ?? '').toString() !=
        (update['createdAt'] ?? '').toString();
    final canManage = _canManageUpdate(update);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (update['title'] ?? '').toString(),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                if (update['pinned'] == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF4FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Pinned',
                      style: TextStyle(
                        color: Color(0xFF0E5A8A),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if ((update['versionTag'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Version ${update['versionTag']}',
                style: const TextStyle(
                  color: Color(0xFF00B4D8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if ((update['summary'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                (update['summary'] ?? '').toString(),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              (update['body'] ?? '').toString(),
              style: const TextStyle(height: 1.45, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildMetaChip(Icons.person_outline, 'Published by: $createdByEmail'),
                _buildMetaChip(Icons.schedule, 'Published: $publishedAt'),
                _buildMetaChip(Icons.category_outlined, 'Category: ${(update['category'] ?? 'general').toString()}'),
                _buildMetaChip(Icons.priority_high, 'Importance: ${(update['importance'] ?? 'normal').toString()}'),
                _buildMetaChip(Icons.event_note, 'Status: ${(update['status'] ?? 'published').toString()}'),
                _buildMetaChip(Icons.visibility, 'Reads: ${((update['stats'] ?? {})['readCount'] ?? 0)}'),
                if (wasEdited)
                  _buildMetaChip(Icons.edit_outlined, 'Edited: $editedAt'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canManage ? () => _startEditing(update) : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canManage ? () => _confirmDelete(update) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
            if (!canManage) ...[
              const SizedBox(height: 10),
              Text(
                'Only the creator admin or a superadmin can edit or delete this update.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FB),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF00B4D8)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Unknown';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour =
        date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final meridiem = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} ${date.year}, $hour:$minute $meridiem';
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
