import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/pickers.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import 'update_history_page.dart';

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
    final t = AppLocalizations.of(context).t;
    if (_titleController.text.trim().isEmpty || _bodyController.text.trim().isEmpty) {
      setState(() => _error = t('title_and_body_required'));
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
        throw Exception((data['error'] ?? t('failed_to_save_update')).toString());
      }

      final message = _isEditing
          ? t('update_edited_successfully')
          : t('update_published_successfully');
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
    final date = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;

    final time = await showAppTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
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
    final t = AppLocalizations.of(context).t;
    final shouldDelete = await _showConfirmDialog(
      title: t('delete_update_question'),
      message:
          '${t('delete_update_confirm_prefix')} "${(update['title'] ?? '').toString()}"?',
      confirmLabel: t('delete'),
      confirmColor: Colors.redAccent,
    );

    if (shouldDelete == true) {
      final res =
          await ApiClient.delete('/api/admin/app-updates/${update['_id']}');
      final data = jsonDecode(res.body);
      if (res.statusCode != 200) {
        if (!mounted) return;
        _showStylishMessage(
          (data['error'] ?? t('failed_to_delete_update')).toString(),
          true,
        );
        return;
      }
      await _loadUpdates();
      if (!mounted) return;
      _showStylishMessage(t('update_deleted_successfully'), false);
      if (_editingId == update['_id']?.toString()) _resetForm();
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    final t = AppLocalizations.of(context).t;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
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
              color: AppThemeColors.cardBg(dialogContext),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.help_outline, color: confirmColor, size: 42),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppThemeColors.primaryText(dialogContext),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    height: 1.45,
                    color: AppThemeColors.primaryText(dialogContext),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(t('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
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

  void _showStylishMessage(String message, bool isError) =>
      showStylishSnackBar(context, message, isError: isError);

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
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.cyan, Color(0xFF48CAE4)],
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
                        icon: Icon(Icons.arrow_back,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      Expanded(
                        child: Text(
                          t('manage_updates'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                AppTabBar(
                  controller: _tabController,
                  tabs: [
                    AppTabItem(label: t('create')),
                    AppTabItem(label: t('manage')),
                  ],
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
                                    color: AppColors.cyan,
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
    final t = AppLocalizations.of(context).t;
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? t('edit_update') : t('publish_new_update'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: t('title'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _summaryController,
              decoration: InputDecoration(
                labelText: t('short_summary'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _versionController,
              decoration: InputDecoration(
                labelText: t('version_tag'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                labelText: t('category'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'general', child: Text(t('general'))),
                DropdownMenuItem(value: 'feature', child: Text(t('feature'))),
                DropdownMenuItem(value: 'bug_fix', child: Text(t('bug_fix'))),
                DropdownMenuItem(value: 'security', child: Text(t('security'))),
                DropdownMenuItem(value: 'maintenance', child: Text(t('maintenance'))),
              ],
              onChanged: (value) => setState(() => _category = value ?? 'general'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _importance,
              decoration: InputDecoration(
                labelText: t('importance'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'normal', child: Text(t('normal'))),
                DropdownMenuItem(value: 'important', child: Text(t('important'))),
                DropdownMenuItem(value: 'critical', child: Text(t('critical'))),
              ],
              onChanged: (value) =>
                  setState(() => _importance = value ?? 'normal'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _targetAudience,
              decoration: InputDecoration(
                labelText: t('audience'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'all', child: Text(t('all_users'))),
                DropdownMenuItem(value: 'subscribed', child: Text(t('subscribed_only'))),
                DropdownMenuItem(value: 'nonsubscribed', child: Text(t('non_subscribed_only'))),
              ],
              onChanged: (value) =>
                  setState(() => _targetAudience = value ?? 'all'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: InputDecoration(
                labelText: t('publish_status'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 'published', child: Text(t('publish_now'))),
                DropdownMenuItem(value: 'draft', child: Text(t('save_as_draft'))),
                DropdownMenuItem(value: 'scheduled', child: Text(t('schedule_for_later'))),
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
                  title: t('select_schedule_date'),
                ),
                decoration: InputDecoration(
                  labelText: t('scheduled_for'),
                  hintText: t('tap_to_choose_date_time'),
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
                          title: t('select_schedule_date'),
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
              decoration: InputDecoration(
                labelText: t('tags'),
                hintText: 'security, release, dashboard',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _platformsController,
              decoration: InputDecoration(
                labelText: t('platforms'),
                hintText: 'all, windows, android, ios, web',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: t('update_details'),
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _pinned,
              title: Text(t('pin_this_update')),
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
                      child: Text(t('cancel_edit')),
                    ),
                  ),
                if (_isEditing) const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitUpdate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _submitting
                          ? (_isEditing ? t('saving') : t('publishing_ellipsis'))
                          : (_isEditing ? t('save_changes') : t('publish_update')),
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
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('manage_published_updates'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppThemeColors.primaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildSummaryChip(t('published'), '${_updateSummary['published']}'),
              _buildSummaryChip(t('drafts'), '${_updateSummary['draft']}'),
              _buildSummaryChip(t('scheduled'), '${_updateSummary['scheduled']}'),
              _buildSummaryChip(t('reads'), '${_updateSummary['reads']}'),
              _buildSummaryChip(t('critical'), '${_updateSummary['critical']}'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFilterChip('all', t('all')),
              _buildFilterChip('mine', t('mine')),
              _buildFilterChip('pinned', t('pinned')),
              _buildFilterChip('draft', t('drafts')),
              _buildFilterChip('scheduled', t('scheduled')),
              _buildFilterChip('critical', t('critical')),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? t('show_latest_3') : t('view_all')),
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
      selectedColor: AppThemeColors.tinted(context,
          light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A4A)),
      labelStyle: TextStyle(
        color: selected ? AppColors.cyan : AppThemeColors.primaryText(context),
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A4A)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: AppThemeColors.primaryText(context)),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: AppColors.cyan,
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
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        t('no_updates_found_for_filter'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppThemeColors.secondaryText(context),
        ),
      ),
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final t = AppLocalizations.of(context).t;
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
          color: AppThemeColors.cardBg(context),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                ),
                if (update['pinned'] == true)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: const Color(0xFFEAF4FF),
                          dark: const Color(0xFF1B3A4A)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      t('pinned'),
                      style: const TextStyle(
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
                '${t('version_label')} ${update['versionTag']}',
                style: const TextStyle(
                  color: AppColors.cyan,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if ((update['summary'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                (update['summary'] ?? '').toString(),
                style: TextStyle(
                  color: AppThemeColors.secondaryText(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              (update['body'] ?? '').toString(),
              style: TextStyle(
                height: 1.45,
                color: AppThemeColors.primaryText(context),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildMetaChip(Icons.person_outline, '${t('published_by_label')} $createdByEmail'),
                _buildMetaChip(Icons.schedule, '${t('published_label')} $publishedAt'),
                _buildMetaChip(Icons.category_outlined, '${t('category')}: ${(update['category'] ?? 'general').toString()}'),
                _buildMetaChip(Icons.priority_high, '${t('importance')}: ${(update['importance'] ?? 'normal').toString()}'),
                _buildMetaChip(Icons.event_note, '${t('status')}: ${(update['status'] ?? 'published').toString()}'),
                _buildMetaChip(Icons.visibility, '${t('reads')}: ${((update['stats'] ?? {})['readCount'] ?? 0)}'),
                if (wasEdited)
                  _buildMetaChip(Icons.edit_outlined, '${t('edited_label')} $editedAt'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canManage ? () => _startEditing(update) : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(t('edit')),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminUpdateHistoryPage(update: update),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded,
                      size: 16, color: AppColors.cyan),
                  label: const Text('History',
                      style: TextStyle(color: AppColors.cyan)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.cyan),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canManage ? () => _confirmDelete(update) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(t('delete')),
                  ),
                ),
              ],
            ),
            if (!canManage) ...[
              const SizedBox(height: 10),
              Text(
                t('only_creator_or_superadmin_can_manage_update'),
                style: TextStyle(
                  color: AppThemeColors.secondaryText(context),
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
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF4F8FB), dark: const Color(0xFF223240)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.cyan),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppThemeColors.primaryText(context),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return AppLocalizations.of(context).t('unknown');
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
