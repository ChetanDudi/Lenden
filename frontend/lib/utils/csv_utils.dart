import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';

// ════════════════════════════════════════════════════════════════════════════
// CSV PARSING
// ════════════════════════════════════════════════════════════════════════════

/// Parses a CSV string into a typed record with [headers] and [rows].
/// Replaces the identical `_parseCsv` + `_splitCsvLine` helpers duplicated in
/// `admin_data_export_page.dart` and `admin_backup_restore_page.dart`.
///
/// Usage:
/// ```dart
/// final parsed = CsvUtils.parse(csvString);
/// // parsed.headers → List<String>
/// // parsed.rows    → List<List<String>>
/// ```
({List<String> headers, List<List<String>> rows}) parseCsv(String csv) {
  final lines = csv.trim().split('\n');
  if (lines.isEmpty) return (headers: [], rows: []);
  final headers = splitCsvLine(lines.first);
  final rows = lines.skip(1).map(splitCsvLine).toList();
  return (headers: headers, rows: rows);
}

/// Splits a single CSV line respecting RFC 4180 quoting rules.
List<String> splitCsvLine(String line) {
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

// ════════════════════════════════════════════════════════════════════════════
// CSV TABLE WIDGET
// ════════════════════════════════════════════════════════════════════════════

/// Builds a horizontally scrollable, zebra-striped [Table] widget from parsed
/// CSV data.  Replaces the identical `_buildTable()` methods in
/// `admin_data_export_page.dart` and `admin_backup_restore_page.dart`.
///
/// Usage:
/// ```dart
/// SingleChildScrollView(
///   scrollDirection: Axis.horizontal,
///   child: buildCsvTable(headers, rows),
/// )
/// ```
Widget buildCsvTable(
  List<String> headers,
  List<List<String>> rows, {
  Color headerColor = AppColors.blue,
  Color cyanAccent = AppColors.cyan,
}) {
  const headerStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Colors.white,
  );
  const cellStyle = TextStyle(fontSize: 12, color: Colors.black87);

  // Estimate column widths based on content length.
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
          color: headerColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        ),
        children: headers
            .map((h) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
            color: isEven ? Colors.white : cyanAccent.withValues(alpha: 0.04),
          ),
          children: List.generate(headers.length, (i) {
            final cell = i < row.length ? row[i] : '';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Text(
                cell,
                style: cellStyle,
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

// ════════════════════════════════════════════════════════════════════════════
// DRAGGABLE CSV BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════

/// Shows a [DraggableScrollableSheet] bottom sheet displaying parsed CSV data
/// with a share button in the header.
///
/// [onShare] is called when the user taps "Share / Email".
///
/// Replaces the near-identical `_showExportDialog` / preview sheet blocks in
/// `admin_data_export_page.dart` and `admin_backup_restore_page.dart`.
void showCsvBottomSheet({
  required BuildContext context,
  required String label,
  required IconData icon,
  required String csvBody,
  required List<String> headers,
  required List<List<String>> rows,
  required VoidCallback onShare,
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
            // Header row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppColors.cyan, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$label Export',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          '${rows.length} record${rows.length == 1 ? '' : 's'}'
                          ' • ${(csvBody.length / 1024).toStringAsFixed(1)} KB',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded,
                        color: Colors.white, size: 16),
                    label: const Text('Share / Email',
                        style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.cyan,
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
            // Table content
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
                        child: buildCsvTable(headers, rows),
                      ),
                    ),
            ),
            // Close button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.cyan),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close',
                        style: TextStyle(color: AppColors.cyan)),
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
