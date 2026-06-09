import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

class ManageAdsPage extends StatefulWidget {
  const ManageAdsPage({super.key});

  @override
  State<ManageAdsPage> createState() => _ManageAdsPageState();
}

class _ManageAdsPageState extends State<ManageAdsPage>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _ctaTextController = TextEditingController();
  final _ctaUrlController = TextEditingController();
  final _startsAtController = TextEditingController();
  final _endsAtController = TextEditingController();
  final _tagsController = TextEditingController();
  final _placementsController = TextEditingController(text: 'dashboard');

  late final TabController _tabController;
  PlatformFile? _selectedMedia;
  int _videoCloseAtPercent = 100;
  int _priorityWeight = 1;
  int _dailyCapPerUser = 3;
  String _audience = 'nonsubscribed';
  bool _active = true;
  bool _loading = true;
  bool _submitting = false;
  bool _showAll = false;
  String _filter = 'all';
  String? _editingId;
  String? _error;
  List<Map<String, dynamic>> _ads = [];

  bool get _isEditing => _editingId != null;

  Map<String, dynamic> _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  String _extractApiError(String body, String fallback) {
    final data = _decodeJsonObject(body);
    final message =
        (data['error'] ?? data['message'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;
    if (body.trimLeft().startsWith('<!DOCTYPE html>')) {
      return 'The server returned an unexpected upload error page. Please try again.';
    }
    return fallback;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAds();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _ctaTextController.dispose();
    _ctaUrlController.dispose();
    _startsAtController.dispose();
    _endsAtController.dispose();
    _tagsController.dispose();
    _placementsController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAds() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient.get('/api/admin/ads');
      final data = _decodeJsonObject(res.body);
      if (res.statusCode != 200) {
        throw Exception(_extractApiError(res.body, 'Failed to load ads'));
      }
      setState(() {
        _ads = List<Map<String, dynamic>>.from(
          (data['ads'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'mp4',
        'mov',
        'mkv',
        'avi',
        'webm'
      ],
      withData: false,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedMedia = result.files.first);
    }
  }

  MediaType? _contentTypeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return MediaType('image', 'jpeg');
    }
    if (lower.endsWith('.gif')) return MediaType('image', 'gif');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.mp4')) return MediaType('video', 'mp4');
    if (lower.endsWith('.mov')) return MediaType('video', 'quicktime');
    if (lower.endsWith('.mkv')) return MediaType('video', 'x-matroska');
    if (lower.endsWith('.avi')) return MediaType('video', 'x-msvideo');
    if (lower.endsWith('.webm')) return MediaType('video', 'webm');
    return null;
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

  void _startEditing(Map<String, dynamic> ad) {
    setState(() {
      _editingId = ad['_id']?.toString();
      _titleController.text = (ad['title'] ?? '').toString();
      _bodyController.text = (ad['body'] ?? '').toString();
      _ctaTextController.text = (ad['callToActionText'] ?? '').toString();
      _ctaUrlController.text = (ad['callToActionUrl'] ?? '').toString();
      _startsAtController.text = _toEditableDateTime(ad['startsAt']);
      _endsAtController.text = _toEditableDateTime(ad['endsAt']);
      _tagsController.text =
          ((ad['tags'] as List?) ?? const []).map((e) => '$e').join(', ');
      _placementsController.text =
          ((ad['placements'] as List?) ?? const ['dashboard']).map((e) => '$e').join(', ');
      _audience = (ad['audience'] ?? 'nonsubscribed').toString();
      _priorityWeight =
          int.tryParse((ad['priorityWeight'] ?? '1').toString()) ?? 1;
      _dailyCapPerUser =
          int.tryParse((ad['dailyCapPerUser'] ?? '3').toString()) ?? 3;
      _videoCloseAtPercent =
          int.tryParse((ad['videoCloseAtPercent'] ?? '100').toString()) ?? 100;
      _active = ad['active'] == true;
      _selectedMedia = null;
      _error = null;
    });
    _tabController.animateTo(0);
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _titleController.clear();
      _bodyController.clear();
      _ctaTextController.clear();
      _ctaUrlController.clear();
      _startsAtController.clear();
      _endsAtController.clear();
      _tagsController.clear();
      _placementsController.text = 'dashboard';
      _selectedMedia = null;
      _audience = 'nonsubscribed';
      _priorityWeight = 1;
      _dailyCapPerUser = 3;
      _videoCloseAtPercent = 100;
      _active = true;
      _error = null;
    });
  }

  Future<void> _submitAd() async {
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Ad title is required.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final files = <ApiMultipartFile>[];
      if (_selectedMedia?.path != null && _selectedMedia!.path!.isNotEmpty) {
        files.add(
          ApiMultipartFile(
            field: 'media',
            filename: _selectedMedia!.name,
            path: _selectedMedia!.path,
            contentType: _contentTypeFor(_selectedMedia!.name),
          ),
        );
      }

      final fields = {
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'callToActionText': _ctaTextController.text.trim(),
        'callToActionUrl': _ctaUrlController.text.trim(),
        'startsAt': _startsAtController.text.trim(),
        'endsAt': _endsAtController.text.trim(),
        'audience': _audience,
        'tags': _tagsController.text.trim(),
        'placements': _placementsController.text.trim(),
        'priorityWeight': _priorityWeight.toString(),
        'dailyCapPerUser': _dailyCapPerUser.toString(),
        'videoCloseAtPercent': _videoCloseAtPercent.toString(),
        'active': _active.toString(),
      };

      final res = _isEditing
          ? await ApiClient.putMultipart(
              '/api/admin/ads/$_editingId',
              fields: fields,
              files: files,
            )
          : await ApiClient.postMultipart(
              '/api/admin/ads',
              fields: fields,
              files: files,
            );

      final validCodes = _isEditing ? [200] : [201];
      if (!validCodes.contains(res.statusCode)) {
        throw Exception(_extractApiError(res.body, 'Failed to save ad'));
      }

      final message =
          _isEditing ? 'Ad edited successfully.' : 'Ad created successfully.';
      _resetForm();
      await _loadAds();
      if (!mounted) return;
      _showStylishMessage(message, false);
      _tabController.animateTo(1);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = message);
      if (mounted) _showStylishMessage(message, true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _toggleAd(Map<String, dynamic> ad) async {
    final res = await ApiClient.patch(
      '/api/admin/ads/${ad['_id']}',
      body: {'active': !(ad['active'] == true)},
    );
    if (res.statusCode != 200) {
      if (!mounted) return;
      _showStylishMessage(
        _extractApiError(res.body, 'Failed to update ad status'),
        true,
      );
      return;
    }
    await _loadAds();
    if (!mounted) return;
    _showStylishMessage('Ad status updated.', false);
  }

  Future<void> _confirmDelete(Map<String, dynamic> ad) async {
    final shouldDelete = await _showConfirmDialog(
      title: 'Delete Ad?',
      message: 'Are you sure you want to delete "${(ad['title'] ?? '').toString()}"?',
      confirmLabel: 'Delete',
      confirmColor: Colors.redAccent,
    );

    if (shouldDelete == true) {
      final res = await ApiClient.delete('/api/admin/ads/${ad['_id']}');
      if (res.statusCode != 200) {
        if (!mounted) return;
        _showStylishMessage(
          _extractApiError(res.body, 'Failed to delete ad'),
          true,
        );
        return;
      }
      await _loadAds();
      if (!mounted) return;
      _showStylishMessage('Ad deleted successfully.', false);
      if (_editingId == ad['_id']?.toString()) _resetForm();
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

  List<Map<String, dynamic>> get _filteredAds {
    final items = _ads.where((ad) {
      switch (_filter) {
        case 'mine':
          return _canManageAd(ad);
        case 'active':
          return ad['active'] == true;
        case 'image':
          return ad['mediaKind'] == 'image';
        case 'video':
          return ad['mediaKind'] == 'video';
        case 'text':
          return ad['mediaKind'] == 'none';
        case 'reported':
          return ((ad['stats'] ?? {})['reports'] ?? 0) > 0;
        default:
          return true;
      }
    }).toList();
    return _showAll ? items : items.take(3).toList();
  }

  bool _canManageAd(Map<String, dynamic> ad) {
    if (ad['canManage'] == true) return true;

    final session = Provider.of<SessionProvider>(context, listen: false);
    final currentAdmin = session.user ?? const <String, dynamic>{};
    if (currentAdmin['isSuperAdmin'] == true) return true;

    final createdBy = ad['createdBy'];
    final createdById =
        createdBy is Map ? createdBy['_id']?.toString() : createdBy?.toString();
    final currentAdminId = currentAdmin['_id']?.toString();
    return createdById != null && createdById == currentAdminId;
  }

  Map<String, num> get _adSummary {
    var active = 0;
    var impressions = 0;
    var clicks = 0;
    var reports = 0;
    var hides = 0;
    var totalWatch = 0;

    for (final ad in _ads) {
      if (ad['active'] == true) active += 1;
      final stats = Map<String, dynamic>.from((ad['stats'] ?? {}) as Map);
      impressions += (stats['impressions'] ?? 0) as int;
      clicks += (stats['clicks'] ?? 0) as int;
      reports += (stats['reports'] ?? 0) as int;
      hides += (stats['hides'] ?? 0) as int;
      totalWatch += (stats['totalWatchSeconds'] ?? 0) as int;
    }

    final ctr = impressions > 0 ? (clicks / impressions) * 100 : 0.0;
    return {
      'active': active,
      'impressions': impressions,
      'clicks': clicks,
      'reports': reports,
      'hides': hides,
      'ctr': ctr,
      'watch': totalWatch,
    };
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
                          'Manage Ads',
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
                        onRefresh: _loadAds,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [_buildComposer()],
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAds,
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
                            else if (_filteredAds.isEmpty)
                              _buildEmptyState()
                            else
                              ..._filteredAds.map(_buildAdCard),
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
              _isEditing ? 'Edit Ad' : 'Create New Ad',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Ad Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Ad Text',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctaTextController,
              decoration: const InputDecoration(
                labelText: 'Call-To-Action Text',
                helperText:
                    'Optional. This becomes the button text users tap, like Learn More or Open Offer.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctaUrlController,
              decoration: const InputDecoration(
                labelText: 'Call-To-Action URL',
                helperText:
                    'Optional. Add the full link starting with http:// or https:// for the CTA button.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _audience,
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
                  setState(() => _audience = value ?? 'nonsubscribed'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _startsAtController,
              readOnly: true,
              onTap: () => _pickDateTime(
                controller: _startsAtController,
                title: 'Select Start Date',
              ),
              decoration: InputDecoration(
                labelText: 'Starts At',
                helperText:
                    'Choose when this ad should start appearing to eligible users.',
                hintText: 'Tap to choose date and time',
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_month_outlined),
                  onPressed: () => _pickDateTime(
                    controller: _startsAtController,
                    title: 'Select Start Date',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _endsAtController,
              readOnly: true,
              onTap: () => _pickDateTime(
                controller: _endsAtController,
                title: 'Select End Date',
              ),
              decoration: InputDecoration(
                labelText: 'Ends At',
                helperText:
                    'Optional. Choose when this ad should stop appearing.',
                hintText: 'Tap to choose date and time',
                border: OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_endsAtController.text.trim().isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _endsAtController.clear()),
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: () => _pickDateTime(
                        controller: _endsAtController,
                        title: 'Select End Date',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _placementsController,
              decoration: const InputDecoration(
                labelText: 'Placements',
                hintText: 'dashboard, home, offers',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags',
                hintText: 'festival, finance, rewards',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _priorityWeight,
                    decoration: const InputDecoration(
                      labelText: 'Priority Weight',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 8, child: Text('8')),
                    ],
                    onChanged: (value) =>
                        setState(() => _priorityWeight = value ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _dailyCapPerUser,
                    decoration: const InputDecoration(
                      labelText: 'Daily Cap / User',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 10, child: Text('10')),
                    ],
                    onChanged: (value) =>
                        setState(() => _dailyCapPerUser = value ?? 3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Video close button timing',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildVideoCloseChip(25, '25%'),
                _buildVideoCloseChip(50, '50%'),
                _buildVideoCloseChip(75, '75%'),
                _buildVideoCloseChip(100, 'At End'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'For video ads, the close button appears after the selected part of the video has played. Text and image ads can be closed immediately.',
              style: TextStyle(
                color: Colors.grey.shade700,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: const Text('Keep ad active'),
              onChanged: (value) => setState(() => _active = value),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickMedia,
              icon: const Icon(Icons.attach_file),
              label: Text(
                _selectedMedia == null
                    ? 'Pick Image / Video'
                    : _selectedMedia!.name,
              ),
            ),
            const SizedBox(height: 12),
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
                    onPressed: _submitting ? null : _submitAd,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _submitting
                          ? (_isEditing ? 'Saving...' : 'Uploading...')
                          : (_isEditing ? 'Save Changes' : 'Create Ad'),
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
            'Manage Ads',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildSummaryChip('Active', '${_adSummary['active']}'),
              _buildSummaryChip('Views', '${_adSummary['impressions']}'),
              _buildSummaryChip('Clicks', '${_adSummary['clicks']}'),
              _buildSummaryChip('Reports', '${_adSummary['reports']}'),
              _buildSummaryChip(
                'CTR',
                '${(_adSummary['ctr'] as double).toStringAsFixed(1)}%',
              ),
              _buildSummaryChip('Watch', '${_adSummary['watch']}s'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildFilterChip('all', 'All'),
              _buildFilterChip('mine', 'Mine'),
              _buildFilterChip('active', 'Active'),
              _buildFilterChip('reported', 'Reported'),
              _buildFilterChip('image', 'Images'),
              _buildFilterChip('video', 'Videos'),
              _buildFilterChip('text', 'Text'),
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
        'No ads found for this filter.',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
      ),
    );
  }

  Widget _buildAdCard(Map<String, dynamic> ad) {
    final createdBy = ad['createdBy'];
    final createdByEmail =
        createdBy is Map ? (createdBy['email'] ?? '').toString() : '';
    final canManage = _canManageAd(ad);
    final wasEdited = (ad['updatedAt'] ?? '').toString() !=
        (ad['createdAt'] ?? '').toString();
    final moderation =
        Map<String, dynamic>.from((ad['moderation'] ?? {}) as Map);
    final recentReports = List<Map<String, dynamic>>.from(
      (moderation['recentReports'] ?? [])
          .map((item) => Map<String, dynamic>.from(item)),
    );

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
                    (ad['title'] ?? '').toString(),
                    style:
                        const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ad['active'] == true
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    ad['active'] == true ? 'Active' : 'Inactive',
                    style: TextStyle(
                      color: ad['active'] == true ? Colors.green.shade800 : Colors.redAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${(ad['mediaKind'] ?? 'none').toString().toUpperCase()} media',
              style: const TextStyle(
                color: Color(0xFF00B4D8),
                fontWeight: FontWeight.w700,
              ),
            ),
            if ((ad['body'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                (ad['body'] ?? '').toString(),
                style: const TextStyle(height: 1.45, color: Colors.black87),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildMetaChip(Icons.person_outline, 'By: $createdByEmail'),
                _buildMetaChip(Icons.schedule, 'Published: ${_formatDateTime(ad['createdAt'])}'),
                _buildMetaChip(Icons.filter_alt_outlined, 'Audience: ${(ad['audience'] ?? 'nonsubscribed')}'),
                _buildMetaChip(Icons.remove_red_eye_outlined, 'Views: ${((ad['stats'] ?? {})['impressions'] ?? 0)}'),
                _buildMetaChip(Icons.ads_click, 'Clicks: ${((ad['stats'] ?? {})['clicks'] ?? 0)}'),
                _buildMetaChip(Icons.report_gmailerrorred_outlined, 'Reports: ${((ad['stats'] ?? {})['reports'] ?? 0)}'),
                _buildMetaChip(Icons.visibility_off_outlined, 'Hides: ${((ad['stats'] ?? {})['hides'] ?? 0)}'),
                _buildMetaChip(Icons.group_outlined, 'Reach: ${((ad['stats'] ?? {})['uniqueUsers'] ?? 0)} users'),
                _buildMetaChip(Icons.av_timer_outlined, 'Avg watch: ${((ad['stats'] ?? {})['averageWatchSeconds'] ?? 0)}s'),
                if (wasEdited)
                  _buildMetaChip(Icons.edit_outlined, 'Edited: ${_formatDateTime(ad['updatedAt'])}'),
                if ((ad['mediaKind'] ?? 'none').toString() == 'video')
                  _buildMetaChip(
                    Icons.timer_outlined,
                    'Close at: ${_videoCloseLabel(ad['videoCloseAtPercent'])}',
                  ),
                _buildMetaChip(Icons.speed_outlined, 'Weight: ${(ad['priorityWeight'] ?? 1)}'),
                _buildMetaChip(Icons.today_outlined, 'Cap: ${(ad['dailyCapPerUser'] ?? 3)}/day'),
              ],
            ),
            if (recentReports.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Recent report reasons',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF00B4D8),
                ),
              ),
              const SizedBox(height: 8),
              ...recentReports.map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '• ${(report['reason'] ?? '').toString().trim().isEmpty ? 'No reason provided' : report['reason']}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canManage ? () => _startEditing(ad) : null,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canManage ? () => _confirmDelete(ad) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: ad['active'] == true,
              onChanged: canManage ? (_) => _toggleAd(ad) : null,
              title: const Text('Show this ad to users'),
            ),
            if (!canManage)
              Text(
                'Only the creator admin or a superadmin can edit or delete this ad.',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
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

  Widget _buildVideoCloseChip(int value, String label) {
    final selected = _videoCloseAtPercent == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _videoCloseAtPercent = value),
      selectedColor: const Color(0xFFEAF5FF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF00B4D8) : Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  String _videoCloseLabel(dynamic value) {
    final percent = int.tryParse(value?.toString() ?? '') ?? 100;
    switch (percent) {
      case 25:
        return '25% played';
      case 50:
        return '50% played';
      case 75:
        return '75% played';
      default:
        return 'End of video';
    }
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
