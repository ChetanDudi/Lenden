import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/api_client.dart';

class AdminDataExportPage extends StatefulWidget {
  const AdminDataExportPage({super.key});

  @override
  State<AdminDataExportPage> createState() => _AdminDataExportPageState();
}

class _AdminDataExportPageState extends State<AdminDataExportPage> {
  bool _isLoading = false;
  String? _lastExported;

  static const _cyan = Color(0xFF00B4D8);
  static const _blue = Color(0xFF0077B6);

  // Parse CSV string → (headers, rows)
  ({List<String> headers, List<List<String>> rows}) _parseCsv(String csv) {
    final lines = csv.trim().split('\n');
    if (lines.isEmpty) return (headers: [], rows: []);
    final headers = _splitCsvLine(lines.first);
    final rows = lines.skip(1).map(_splitCsvLine).toList();
    return (headers: headers, rows: rows);
  }

  List<String> _splitCsvLine(String line) {
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

  Future<void> _export(String type, String label, IconData icon) async {
    setState(() => _isLoading = true);
    String csvBody = '';
    try {
      final response =
          await ApiClient.get('/api/admin/data/export?type=$type');
      if (response.statusCode != 200) {
        _showSnack('Export failed. Please try again.', isError: true);
        return;
      }
      csvBody = response.body;
      setState(() => _lastExported = label);
    } catch (e) {
      _showSnack('Network error: $e', isError: true);
      return;
    } finally {
      setState(() => _isLoading = false);
    }

    if (!mounted) return;
    final parsed = _parseCsv(csvBody);
    _showExportDialog(
      label: label,
      icon: icon,
      csvBody: csvBody,
      filename: '${type}_export.csv',
      headers: parsed.headers,
      rows: parsed.rows,
    );
  }

  Future<void> _shareFile(String csvBody, String filename) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csvBody);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'LenDen Export — $filename',
        text: 'Exported data from LenDen Admin Panel.',
      );
    } catch (e) {
      if (mounted) _showSnack('Share failed: $e', isError: true);
    }
  }

  void _showExportDialog({
    required String label,
    required IconData icon,
    required String csvBody,
    required String filename,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: _cyan, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$label Export',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('${rows.length} record${rows.length == 1 ? '' : 's'} • ${(csvBody.length / 1024).toStringAsFixed(1)} KB',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    // Share button
                    ElevatedButton.icon(
                      onPressed: () => _shareFile(csvBody, filename),
                      icon: const Icon(Icons.share_rounded,
                          color: Colors.white, size: 16),
                      label: const Text('Share / Email',
                          style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cyan,
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

              // Table
              Expanded(
                child: rows.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined,
                                color: Colors.grey, size: 48),
                            SizedBox(height: 8),
                            Text('No data found.',
                                style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _buildTable(headers, rows),
                        ),
                      ),
              ),
              // Bottom close bar
              SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _cyan),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Close',
                          style: TextStyle(color: _cyan)),
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

  Widget _buildTable(List<String> headers, List<List<String>> rows) {
    const headerStyle = TextStyle(
        fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white);
    const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

    // Estimate column widths
    final colWidths = headers.map((h) {
      double w = h.length * 8.0 + 24;
      for (final row in rows) {
        final idx = headers.indexOf(h);
        if (idx < row.length) {
          final cw = row[idx].length * 7.0 + 24;
          if (cw > w) w = cw;
        }
      }
      return w.clamp(70.0, 200.0);
    }).toList();

    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        for (int i = 0; i < colWidths.length; i++)
          i: FixedColumnWidth(colWidths[i]),
      },
      border: TableBorder.all(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: _blue,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          children: headers
              .map((h) => Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        // Data rows
        ...rows.asMap().entries.map((entry) {
          final isEven = entry.key.isEven;
          final row = entry.value;
          return TableRow(
            decoration: BoxDecoration(
              color: isEven
                  ? Colors.white
                  : _cyan.withValues(alpha: 0.04),
            ),
            children: List.generate(headers.length, (i) {
              final cell = i < row.length ? row[i] : '';
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 9),
                child: Text(cell,
                    style: cellStyle,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              );
            }),
          );
        }),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _exportCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
    required Color accent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _export(type, title, icon),
              icon: const Icon(Icons.download_rounded,
                  color: Colors.white, size: 16),
              label: const Text('Export',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      appBar: AppBar(
        title: const Text('Data Export',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _cyan,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _cyan.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cyan.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: _blue, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Tap Export to preview the data as a table. '
                          'Use Share / Email to send the CSV file.',
                          style:
                              TextStyle(fontSize: 13, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Available Exports',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _blue)),
                const SizedBox(height: 4),
                _sectionLabel('Users & Support'),
                const SizedBox(height: 8),
                _exportCard(
                  icon: Icons.people_outline,
                  title: 'Users',
                  subtitle: 'All user accounts — name, username, email, gender, joined date',
                  type: 'users',
                  accent: _cyan,
                ),
                _exportCard(
                  icon: Icons.support_agent_outlined,
                  title: 'Support Queries',
                  subtitle: 'All support tickets — user, topic, status, priority, date',
                  type: 'support',
                  accent: Colors.orange,
                ),
                _sectionLabel('Transactions'),
                const SizedBox(height: 8),
                _exportCard(
                  icon: Icons.flash_on_rounded,
                  title: 'Quick Transactions',
                  subtitle: 'Creator, participants, role, amount, settlement status',
                  type: 'quick_transactions',
                  accent: Colors.green,
                ),
                _exportCard(
                  icon: Icons.lock_outline_rounded,
                  title: 'Secure Transactions',
                  subtitle: 'User email, counterparty, role, amount, currency, place',
                  type: 'transactions',
                  accent: Colors.purple,
                ),
                _exportCard(
                  icon: Icons.group_outlined,
                  title: 'Group Transactions',
                  subtitle: 'Group title, creator, each expense with amount & date',
                  type: 'group_transactions',
                  accent: Colors.teal,
                ),
                if (_lastExported != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('Last exported: $_lastExported',
                            style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.18),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
