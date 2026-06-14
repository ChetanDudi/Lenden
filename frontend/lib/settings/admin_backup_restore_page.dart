import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/api_client.dart';

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

  static const _cyan = Color(0xFF00B4D8);
  static const _blue = Color(0xFF0077B6);

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
    setState(() => _isLoading = true);
    try {
      final types = ['users', 'transactions', 'support'];
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
        _showSnack('No data to backup.', isError: true);
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
      _showSnack(
          'Backup created! ${(totalBytes / 1024).toStringAsFixed(1)} KB');
    } catch (e) {
      _showSnack('Backup failed: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── CSV helpers ───────────────────────────────────────────────────────────

  ({List<String> headers, List<List<String>> rows}) _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.isEmpty) return (headers: [], rows: []);
    return (
      headers: _splitLine(lines.first),
      rows: lines.skip(1).map(_splitLine).toList(),
    );
  }

  List<String> _splitLine(String line) {
    final result = <String>[];
    bool inQuote = false;
    final buf = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuote = !inQuote;
        }
      } else if (c == ',' && !inQuote) {
        result.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    result.add(buf.toString().trim());
    return result;
  }

  // ── Table builder ─────────────────────────────────────────────────────────

  Widget _buildTable(List<String> headers, List<List<String>> rows) {
    final colWidths = List.generate(headers.length, (i) {
      double w = headers[i].length * 8.0 + 24;
      for (final row in rows) {
        if (i < row.length) {
          final cw = row[i].length * 7.0 + 24;
          if (cw > w) w = cw;
        }
      }
      return w.clamp(70.0, 200.0);
    });

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (int i = 0; i < colWidths.length; i++)
          i: FixedColumnWidth(colWidths[i]),
      },
      border: TableBorder.all(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: _blue),
          children: headers
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Text(h,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white)),
                  ))
              .toList(),
        ),
        ...rows.asMap().entries.map((e) {
          final row = e.value;
          return TableRow(
            decoration: BoxDecoration(
              color: e.key.isEven
                  ? Colors.white
                  : _cyan.withValues(alpha: 0.04),
            ),
            children: List.generate(headers.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 9),
                child: Text(
                  i < row.length ? row[i] : '',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  // ── View sheet ────────────────────────────────────────────────────────────

  void _viewBackup(_BackupEntry entry, String type) async {
    final filePath = entry.filePaths[type];
    if (filePath == null || !File(filePath).existsSync()) {
      _showSnack('File not found on disk.', isError: true);
      return;
    }
    final csv = await File(filePath).readAsString();
    final parsed = _parseCsv(csv);
    final label = '${type[0].toUpperCase()}${type.substring(1)}';
    const typeColors = {
      'users': _cyan,
      'transactions': Colors.green,
      'support': Colors.orange,
    };
    const typeIcons = {
      'users': Icons.people_outline,
      'transactions': Icons.swap_horiz_rounded,
      'support': Icons.support_agent_outlined,
    };
    final accent = typeColors[type] ?? _cyan;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFAF9F6),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(typeIcons[type] ?? Icons.table_chart,
                          color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$label Data',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          Text(
                            '${parsed.rows.length} record${parsed.rows.length == 1 ? '' : 's'} '
                            '• ${(csv.length / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Share.shareXFiles(
                          [XFile(filePath, mimeType: 'text/csv')],
                          subject: 'LenDen $label Export',
                        );
                      },
                      icon: const Icon(Icons.share_rounded,
                          color: Colors.white, size: 15),
                      label: const Text('Share',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: parsed.rows.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                color: Colors.grey, size: 48),
                            SizedBox(height: 8),
                            Text('No records found.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildTable(
                              parsed.headers, parsed.rows),
                        ),
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: accent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Close',
                          style: TextStyle(color: accent)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareBackup(_BackupEntry entry) async {
    final existing = entry.filePaths.values
        .where((p) => File(p).existsSync())
        .map((p) => XFile(p, mimeType: 'text/csv'))
        .toList();
    if (existing.isEmpty) {
      _showSnack('Backup files not found on disk.', isError: true);
      return;
    }
    await Share.shareXFiles(existing,
        subject: 'LenDen Backup — ${entry.label}');
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── UI helpers ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadHistory().then((_) => _fetchStats());
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: _cyan, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: _blue)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(_BackupEntry entry) {
    const typeColors = {
      'users': _cyan,
      'transactions': Colors.green,
      'support': Colors.orange,
    };
    const typeIcons = {
      'users': Icons.people_outline,
      'transactions': Icons.swap_horiz_rounded,
      'support': Icons.support_agent_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        '${(entry.totalBytes / 1024).toStringAsFixed(1)} KB  •  '
                        '${entry.filePaths.keys.join(', ')}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share_rounded, color: _cyan),
                  tooltip: 'Share all files',
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
                final color = typeColors[type] ?? _cyan;
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
                        Text('View $label',
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text('Backup & Restore',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _cyan,
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
                  const Text('System Snapshot',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _blue)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _statCard('Users',
                          '${_stats?['users'] ?? '--'}',
                          Icons.people_outline),
                      _statCard('Transactions',
                          '${_stats?['transactions'] ?? '--'}',
                          Icons.swap_horiz),
                      _statCard('Support',
                          '${_stats?['supportQueries'] ?? '--'}',
                          Icons.support_agent_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Create backup
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
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
                        const Row(
                          children: [
                            Icon(Icons.backup_outlined, color: _cyan),
                            SizedBox(width: 10),
                            Text('Create Backup',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Exports users, transactions, and support queries as CSV files '
                          'saved on this device. History persists across app restarts.',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _createBackup,
                            icon: const Icon(Icons.cloud_upload_outlined,
                                color: Colors.white),
                            label: const Text('Create Backup Now',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _cyan,
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
                      const Text('Backup History',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _blue)),
                      const Spacer(),
                      if (_history.isNotEmpty)
                        Text(
                          '${_history.length} backup${_history.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_history.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.history, color: Colors.grey, size: 40),
                          SizedBox(height: 8),
                          Text(
                            'No backups yet.\nCreate your first backup above.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._history.map(_buildHistoryCard),
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
