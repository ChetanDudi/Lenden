import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/api_client.dart';
import '../utils/csv_utils.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

// ── Persistent backup entry ───────────────────────────────────────────────

class _BackupEntry {
  final String label;
  final DateTime createdAt;
  final Map<String, String> filePaths; // type -> absolute path on disk
  final int totalBytes;

  const _BackupEntry({
    required this.label,
    required this.createdAt,
    required this.filePaths,
    required this.totalBytes,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'createdAt': createdAt.toIso8601String(),
        'filePaths': filePaths,
        'totalBytes': totalBytes,
      };

  factory _BackupEntry.fromJson(Map<String, dynamic> j) => _BackupEntry(
        label: j['label'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        filePaths: Map<String, String>.from(j['filePaths'] as Map),
        totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
      );
}

// ── Page ──────────────────────────────────────────────────────────────────

class AdminBackupRestorePage extends StatefulWidget {
  const AdminBackupRestorePage({super.key});

  @override
  State<AdminBackupRestorePage> createState() =>
      _AdminBackupRestorePageState();
}

class _AdminBackupRestorePageState extends State<AdminBackupRestorePage> {
  bool _isLoading = false;
  Map<String, dynamic>? _stats;
  List<_BackupEntry> _history = [];


  // ── Disk helpers ─────────────────────────────────────────────────────────

  Future<Directory> _backupDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/lenden_backups');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<File> _historyFile() async {
    final dir = await _backupDir();
    return File('${dir.path}/backup_history.json');
  }

  Future<void> _saveHistory() async {
    final file = await _historyFile();
    final json = jsonEncode(_history.map((e) => e.toJson()).toList());
    await file.writeAsString(json);
  }

  Future<void> _loadHistory() async {
    try {
      final file = await _historyFile();
      if (!file.existsSync()) return;
      final raw = jsonDecode(await file.readAsString()) as List;
      // Filter entries whose CSV files still exist on disk
      final valid = raw
          .map((j) => _BackupEntry.fromJson(j as Map<String, dynamic>))
          .where((e) => e.filePaths.values.every((p) => File(p).existsSync()))
          .toList();
      setState(() => _history = valid);
    } catch (_) {}
  }

  // ── Network ───────────────────────────────────────────────────────────────

  Future<void> _fetchStats() async {
    setState(() => _isLoading = true);
    try {
      final r = await ApiClient.get('/api/admin/data/stats');
      if (r.statusCode == 200) {
        setState(() => _stats = jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createBackup() async {
    final t = AppLocalizations.of(context).t;
    setState(() => _isLoading = true);
    try {
      final types = ['users', 'transactions', 'quick_transactions', 'group_transactions', 'support'];
      final dir = await _backupDir();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final paths = <String, String>{};
      int totalBytes = 0;

      for (final type in types) {
        final r = await ApiClient.get('/api/admin/data/export?type=$type');
        if (r.statusCode == 200 && r.body.isNotEmpty) {
          final file = File('${dir.path}/${type}_$ts.csv');
          await file.writeAsString(r.body);
          paths[type] = file.path;
          totalBytes += r.body.length;
        }
      }

      if (paths.isEmpty) {
        if (mounted) showSnack(context, t('no_data_to_backup'), isError: true);
        return;
      }

      final now = DateTime.now();
      final entry = _BackupEntry(
        label:
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
        createdAt: now,
        filePaths: paths,
        totalBytes: totalBytes,
      );

      setState(() => _history.insert(0, entry));
      await _saveHistory();

      if (!mounted) return;
      showSnack(context,
          '${t('backup_created')} ${(totalBytes / 1024).toStringAsFixed(1)} KB');
    } catch (e) {
      if (mounted) showSnack(context, '${t('backup_failed')} $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── View sheet ────────────────────────────────────────────────────────────

  void _viewBackup(_BackupEntry entry, String type) async {
    final t = AppLocalizations.of(context).t;
    final filePath = entry.filePaths[type];
    if (filePath == null || !File(filePath).existsSync()) {
      if (mounted) showSnack(context, t('file_not_found_on_disk'), isError: true);
      return;
    }
    final csv = await File(filePath).readAsString();
    final parsed = parseCsv(csv);
    final label = '${type[0].toUpperCase()}${type.substring(1)}';
    const typeIcons = {
      'users': Icons.people_outline,
      'transactions': Icons.lock_outline_rounded,
      'quick_transactions': Icons.flash_on_rounded,
      'group_transactions': Icons.group_outlined,
      'support': Icons.support_agent_outlined,
    };

    if (!mounted) return;
    showCsvBottomSheet(
      context: context,
      label: label,
      icon: typeIcons[type] ?? Icons.table_chart,
      csvBody: csv,
      headers: parsed.headers,
      rows: parsed.rows,
      onShare: () => Share.shareXFiles(
        [XFile(filePath, mimeType: 'text/csv')],
        subject: 'LenDen $label Export',
      ),
    );
  }

  Future<void> _shareBackup(_BackupEntry entry) async {
    final t = AppLocalizations.of(context).t;
    final existing = entry.filePaths.values
        .where((p) => File(p).existsSync())
        .map((p) => XFile(p, mimeType: 'text/csv'))
        .toList();
    if (existing.isEmpty) {
      showSnack(context, t('backup_files_not_found_on_disk'), isError: true);
      return;
    }
    await Share.shareXFiles(existing,
        subject: 'LenDen Backup — ${entry.label}');
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadHistory().then((_) => _fetchStats());
  }

  Widget _statCard(
      BuildContext context, String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.cyan, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.blue)),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: AppThemeColors.secondaryText(context))),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, _BackupEntry entry) {
    final t = AppLocalizations.of(context).t;
    const typeColors = {
      'users': AppColors.cyan,
      'transactions': Colors.purple,
      'quick_transactions': Colors.green,
      'group_transactions': Colors.teal,
      'support': Colors.orange,
    };
    const typeIcons = {
      'users': Icons.people_outline,
      'transactions': Icons.lock_outline_rounded,
      'quick_transactions': Icons.flash_on_rounded,
      'group_transactions': Icons.group_outlined,
      'support': Icons.support_agent_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.label,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppThemeColors.primaryText(context))),
                      Text(
                        '${(entry.totalBytes / 1024).toStringAsFixed(1)} KB  •  '
                        '${entry.filePaths.keys.join(', ')}',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppThemeColors.secondaryText(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: AppColors.cyan),
                  tooltip: t('share_all_files'),
                  onPressed: () => _shareBackup(entry),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: entry.filePaths.keys.map((type) {
                final color = typeColors[type] ?? AppColors.cyan;
                final icon = typeIcons[type] ?? Icons.table_chart;
                final label =
                    '${type[0].toUpperCase()}${type.substring(1)}';
                return InkWell(
                  onTap: () => _viewBackup(entry, type),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: color.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 14, color: color),
                        const SizedBox(width: 5),
                        Text('${t('view_label')} $label',
                            style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: AppBar(
        title: Text(t('backup_and_restore'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.cyan,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _fetchStats,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('system_snapshot'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.blue)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard(context, t('users_label'),
                          '${_stats?['users'] ?? '--'}',
                          Icons.people_outline),
                      _statCard(context, t('transactions_label'),
                          '${_stats?['transactions'] ?? '--'}',
                          Icons.swap_horiz),
                      _statCard(context, t('support_label'),
                          '${_stats?['supportQueries'] ?? '--'}',
                          Icons.support_agent_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Create backup
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8)
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.backup_outlined, color: AppColors.cyan),
                            const SizedBox(width: 10),
                            Text(t('create_backup'),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppThemeColors.primaryText(context))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('create_backup_desc'),
                          style: TextStyle(
                              color: AppThemeColors.secondaryText(context),
                              fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _createBackup,
                            icon: const Icon(Icons.cloud_upload_outlined,
                                color: Colors.white),
                            label: Text(t('create_backup_now'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Text(t('backup_history'),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.blue)),
                      const Spacer(),
                      if (_history.isNotEmpty)
                        Text(
                          '${_history.length} ${_history.length == 1 ? t('backup_singular') : t('backups_plural')}',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppThemeColors.secondaryText(context)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.history,
                              color: AppThemeColors.secondaryText(context),
                              size: 40),
                          const SizedBox(height: 8),
                          Text(
                            t('no_backups_yet'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppThemeColors.secondaryText(context)),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._history
                        .map((entry) => _buildHistoryCard(context, entry)),
                ],
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.15),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
