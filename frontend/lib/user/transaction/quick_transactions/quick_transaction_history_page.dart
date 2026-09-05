import 'dart:convert';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../utils/share_utils.dart';
import '../../../utils/api_client.dart';
import '../../../widgets/app_colors.dart';
import '../../../utils/theme_helper.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/wave_widget.dart';
import '../../../widgets/share_as_note_sheet.dart';
import '../../../utils/transaction_constants.dart';

String _catLabel(String? key) => txCatLabel(key);
String _sym(String code) => txCurrencySymbol(code);

String _fmtAmount(dynamic amount, String? currency) {
  final d = double.tryParse(amount?.toString() ?? '') ?? 0;
  final c = (currency ?? 'INR').toUpperCase();
  return '${_sym(c)}${d.toStringAsFixed(2)} $c';
}

String _fmtDate(dynamic raw) {
  final dt = raw is String ? DateTime.tryParse(raw) : null;
  if (dt == null) return '—';
  return DateFormat('d MMM yyyy').format(dt.toLocal());
}

String _fmtDateTime(dynamic raw) {
  final dt = raw is String ? DateTime.tryParse(raw) : null;
  if (dt == null) return '—';
  return DateFormat('d MMM yyyy, h:mm a').format(dt.toLocal());
}

class QuickTransactionHistoryPage extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final String currentUserEmail;

  const QuickTransactionHistoryPage({
    super.key,
    required this.transaction,
    required this.currentUserEmail,
  });

  @override
  State<QuickTransactionHistoryPage> createState() =>
      _QuickTransactionHistoryPageState();
}

class _QuickTransactionHistoryPageState
    extends State<QuickTransactionHistoryPage> {
  bool _isSharing = false;
  bool _isRefreshing = false;
  late Map<String, dynamic> _freshTx;
  final Set<int> _expandedEdits = {};

  @override
  void initState() {
    super.initState();
    _freshTx = Map<String, dynamic>.from(widget.transaction);
  }

  Map<String, dynamic> get _tx => _freshTx;

  Future<void> _refreshFromApi() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final res = await ApiClient.get('/quick-transactions/$_txId');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _freshTx = Map<String, dynamic>.from(body['quickTransaction'] as Map);
          });
          ElegantNotification.success(
            title: const Text('Refreshed',
                style: TextStyle(fontWeight: FontWeight.bold)),
            description: const Text('Latest history loaded'),
          ).show(context);
        }
      } else {
        if (mounted) {
          ElegantNotification.error(
            title: const Text('Refresh Failed',
                style: TextStyle(fontWeight: FontWeight.bold)),
            description: const Text('Could not load latest data'),
          ).show(context);
        }
      }
    } catch (_) {
      if (mounted) {
        ElegantNotification.error(
          title: const Text('Network Error',
              style: TextStyle(fontWeight: FontWeight.bold)),
          description: const Text('Check your connection and try again'),
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  List<Map<String, dynamic>> get _history {
    final raw = _tx['editHistory'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  String get _txId => (_tx['_id'] ?? '').toString();
  String get _shortId => _txId.length > 8 ? _txId.substring(_txId.length - 8) : _txId;

  String get _myRole {
    final creator = (_tx['creatorEmail'] ?? '').toString().toLowerCase().trim();
    final role = (_tx['role'] ?? 'lender').toString();
    if (widget.currentUserEmail.toLowerCase().trim() == creator) return role;
    return role == 'lender' ? 'borrower' : 'lender';
  }

  String get _counterpartyName {
    final rawList = (_tx['users'] as List? ?? []);
    for (final user in rawList) {
      if (user is Map) {
        final email = (user['email'] ?? '').toString().toLowerCase().trim();
        if (email.isNotEmpty && email != widget.currentUserEmail.toLowerCase()) {
          final name = (user['name'] ?? user['username'] ?? '').toString();
          return name.isNotEmpty ? name : email;
        }
      } else if (user is String) {
        final email = user.toLowerCase().trim();
        if (email.isNotEmpty && email != widget.currentUserEmail.toLowerCase()) {
          return email;
        }
      }
    }
    return '—';
  }

  // ─── Timeline helpers ────────────────────────────────────────────────────────

  String _timeAgo(dynamic raw) {
    final dt = raw is String ? DateTime.tryParse(raw) : null;
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
    if (diff.inDays > 30)  return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0)   return '${diff.inDays}d ago';
    if (diff.inHours > 0)  return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min ago';
    return 'Just now';
  }

  // Returns all editable fields as structured diff maps with 'changed' flag.
  // oldState = editHistory snapshot, newState = next snapshot or current _tx.
  List<Map<String, dynamic>> _allFields(
      Map<String, dynamic> oldState, Map<String, dynamic> newState) {
    final oldAmt = double.tryParse(oldState['amount']?.toString() ?? '') ?? 0;
    final newAmt = double.tryParse(newState['amount']?.toString() ?? '') ?? 0;
    final oldCur = (oldState['currency'] ?? 'INR').toString();
    final newCur = (newState['currency'] ?? 'INR').toString();
    final oldDesc = (oldState['description'] ?? '').toString();
    final newDesc = (newState['description'] ?? '').toString();
    final oldRole = (oldState['role'] ?? 'lender').toString();
    final newRole = (newState['role'] ?? 'lender').toString();
    final oldDate = _fmtDate(oldState['date']);
    final newDate = _fmtDate(newState['date']);
    final oldTime = (oldState['time'] ?? '—').toString();
    final newTime = (newState['time'] ?? '—').toString();

    final oldCat = _catLabel(oldState['category']?.toString());
    final newCat = _catLabel(newState['category']?.toString());

    return [
      {
        'label': 'Amount',
        'old': _fmtAmount(oldAmt, oldCur),
        'new': _fmtAmount(newAmt, newCur),
        'changed': oldAmt != newAmt || oldCur != newCur,
      },
      {
        'label': 'Description',
        'old': oldDesc.isNotEmpty ? oldDesc : '—',
        'new': newDesc.isNotEmpty ? newDesc : '—',
        'changed': oldDesc != newDesc,
      },
      {
        'label': 'Category',
        'old': oldCat,
        'new': newCat,
        'changed': oldCat != newCat,
      },
      {
        'label': 'Role',
        'old': _roleLbl(oldRole),
        'new': _roleLbl(newRole),
        'changed': oldRole != newRole,
      },
      {
        'label': 'Date',
        'old': oldDate,
        'new': newDate,
        'changed': oldDate != newDate,
      },
      {
        'label': 'Time',
        'old': oldTime,
        'new': newTime,
        'changed': oldTime != newTime,
      },
    ];
  }

  String _roleLbl(String r) => r == 'lender' ? 'Lender (you lent)' : 'Borrower (you owe)';

  // ─── Copy helpers ────────────────────────────────────────────────────────────

  String _buildCurrentStateText() {
    final buf = StringBuffer();
    final desc = (_tx['description'] ?? '').toString();
    buf.writeln('CURRENT STATE — "${desc.isNotEmpty ? desc : 'Quick Transaction'}"');
    buf.writeln('-' * 40);
    buf.writeln('Amount      : ${_fmtAmount(_tx['amount'], _tx['currency'])}');
    buf.writeln('Description : ${_tx['description'] ?? '—'}');
    buf.writeln('Role        : ${_roleLbl(_myRole)}');
    buf.writeln('Category    : ${_catLabel(_tx['category']?.toString())}');
    buf.writeln('Date        : ${_fmtDate(_tx['date'])}');
    buf.writeln('Time        : ${_tx['time'] ?? '—'}');
    buf.writeln('Status      : ${(_tx['cleared'] == true) ? 'Cleared ✓' : 'Active'}');
    buf.writeln('Settlement  : ${(_tx['settlementStatus'] ?? 'none').toString().toUpperCase()}');
    buf.writeln('With        : $_counterpartyName');
    buf.writeln('Last updated: ${_fmtDateTime(_tx['updatedAt'])}');
    return buf.toString();
  }

  String _buildFullHistoryText() {
    final buf = StringBuffer();
    buf.writeln('LENDEN — Quick Transaction History');
    buf.writeln('Transaction : ${(_tx['description'] ?? 'Quick Transaction').toString()}');
    buf.writeln('Generated   : ${_fmtDateTime(DateTime.now().toIso8601String())}');
    buf.writeln('');
    buf.writeln(_buildCurrentStateText());
    buf.writeln('');
    buf.writeln('EDIT HISTORY (${_history.length} edit${_history.length == 1 ? '' : 's'})');
    buf.writeln('-' * 40);
    if (_history.isEmpty) {
      buf.writeln('No edits recorded.');
    } else {
      for (int i = 0; i < _history.length; i++) {
        final entry = _history[i];
        final nextState = i + 1 < _history.length ? _history[i + 1] : _tx;
        buf.writeln('');
        buf.writeln('[Edit ${i + 1}] ${_fmtDateTime(entry['editedAt'])}');
        buf.writeln('By: ${entry['editedBy'] ?? '—'}');
        final allF = _allFields(entry, nextState);
        for (final f in allF) {
          final changed = f['changed'] as bool;
          if (changed) {
            buf.writeln('  [CHANGED] ${f['label']}: ${f['old']}  →  ${f['new']}');
          } else {
            buf.writeln('  [same]    ${f['label']}: ${f['new']}');
          }
        }
      }
      buf.writeln('');
      buf.writeln('[Original state at creation]');
      final orig = _history.first;
      buf.writeln('  Amount     : ${_fmtAmount(orig['amount'], orig['currency'])}');
      buf.writeln('  Description: ${orig['description'] ?? '—'}');
      buf.writeln('  Role       : ${_roleLbl((orig['role'] ?? 'lender').toString())}');
      buf.writeln('  Date       : ${_fmtDate(orig['date'])}');
      buf.writeln('  Time       : ${orig['time'] ?? '—'}');
    }
    return buf.toString();
  }

  // ─── PDF ────────────────────────────────────────────────────────────────────

  Future<List<int>> _buildPdf() async {
    const darkBg = PdfColor.fromInt(0xFF0D1B2A);
    const cyan = PdfColor.fromInt(0xFF00BCD4);
    const lightGrey = PdfColor.fromInt(0xFFF5F5F5);
    const textDark = PdfColor.fromInt(0xFF1A1A1A);
    const green = PdfColor.fromInt(0xFF4CAF50);
    const orange = PdfColor.fromInt(0xFFF06322);
    const white70 = PdfColor(1, 1, 1, 0.7);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          // ── Header ──
          pw.Container(
            decoration: const pw.BoxDecoration(
              color: darkBg,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
            ),
            padding: const pw.EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('LenDen',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('Quick Transaction Edit History',
                    style: pw.TextStyle(color: cyan, fontSize: 13)),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text((_tx['description'] ?? 'Quick Transaction').toString(),
                        style: pw.TextStyle(
                            color: white70, fontSize: 10)),
                    pw.Text(
                        'Generated: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
                        style: pw.TextStyle(
                            color: white70, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Current State ──
          pw.Text('Current State',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.4),
              1: const pw.FlexColumnWidth(2.6),
            },
            children: [
              _pdfRow('Amount',
                  _fmtAmount(_tx['amount'], _tx['currency']),
                  lightGrey: true),
              _pdfRow('Description', _tx['description']?.toString() ?? '—'),
              _pdfRow('Role', _roleLbl(_myRole), lightGrey: true),
              _pdfRow('Category', _catLabel(_tx['category']?.toString())),
              _pdfRow('Date', _fmtDate(_tx['date']), lightGrey: true),
              _pdfRow('Time', _tx['time']?.toString() ?? '—'),
              _pdfRow(
                  'Status',
                  (_tx['cleared'] == true) ? 'Cleared' : 'Active',
                  valueColor: (_tx['cleared'] == true) ? green : orange,
                  lightGrey: true),
              _pdfRow(
                  'Settlement',
                  (_tx['settlementStatus'] ?? 'none').toString().toUpperCase()),
              _pdfRow('With', _counterpartyName, lightGrey: true),
              _pdfRow('Last Updated', _fmtDateTime(_tx['updatedAt'])),
              _pdfRow('Created', _fmtDateTime(_tx['createdAt']), lightGrey: true),
            ],
          ),
          pw.SizedBox(height: 24),

          // ── Edit History ──
          pw.Text(
              'Edit History (${_history.length} edit${_history.length == 1 ? '' : 's'})',
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: textDark)),
          pw.SizedBox(height: 8),
          if (_history.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightGrey,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Text('No edits recorded for this transaction.',
                  style: pw.TextStyle(color: PdfColors.grey700)),
            )
          else ...[
            // Original state row
            pw.Container(
              decoration: const pw.BoxDecoration(color: darkBg,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6))),
              padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: pw.Row(children: [
                pw.Text('Original at Creation  ',
                    style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11)),
                pw.Text(
                    '${_fmtAmount(_history.first['amount'], _history.first['currency'])}  |  ${_history.first['description'] ?? '—'}',
                    style: pw.TextStyle(color: white70, fontSize: 10)),
              ]),
            ),
            pw.SizedBox(height: 8),
            for (int i = 0; i < _history.length; i++) ...[
              () {
                final entry = _history[i];
                final nextState =
                    i + 1 < _history.length ? _history[i + 1] : _tx;
                final editDate = _fmtDateTime(entry['editedAt']);
                final editBy = (entry['editedBy'] ?? '—').toString();
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                    borderRadius:
                        const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: const pw.BoxDecoration(
                          color: lightGrey,
                          borderRadius: pw.BorderRadius.only(
                              topLeft: pw.Radius.circular(6),
                              topRight: pw.Radius.circular(6)),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('Edit ${i + 1}',
                                style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 11,
                                    color: textDark)),
                            pw.Text(editDate,
                                style: pw.TextStyle(
                                    fontSize: 10, color: PdfColors.grey700)),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(12, 6, 12, 10),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('By: $editBy',
                                style: pw.TextStyle(
                                    fontSize: 9, color: PdfColors.grey700)),
                            pw.SizedBox(height: 6),
                            // Show ALL fields; highlight changed ones
                            pw.Table(
                              border: pw.TableBorder.all(
                                  color: PdfColors.grey200, width: 0.5),
                              columnWidths: {
                                0: const pw.FlexColumnWidth(1.0),
                                1: const pw.FlexColumnWidth(1.5),
                                2: const pw.FlexColumnWidth(1.5),
                              },
                              children: [
                                pw.TableRow(
                                  decoration: const pw.BoxDecoration(
                                      color: PdfColor.fromInt(0xFFF5F5F5)),
                                  children: [
                                    _pdfCell('Field', bold: true),
                                    _pdfCell('Before', bold: true),
                                    _pdfCell('After', bold: true),
                                  ],
                                ),
                                for (final f in _allFields(entry, nextState))
                                  pw.TableRow(
                                    decoration: (f['changed'] as bool)
                                        ? const pw.BoxDecoration(
                                            color: PdfColor.fromInt(0xFFFFF3E0))
                                        : null,
                                    children: [
                                      _pdfCell(f['label'] as String,
                                          color: (f['changed'] as bool)
                                              ? const PdfColor(0.94, 0.39, 0.13)
                                              : PdfColors.grey700),
                                      _pdfCell(f['old'] as String,
                                          strikethrough:
                                              f['changed'] as bool),
                                      _pdfCell(f['new'] as String,
                                          bold: f['changed'] as bool,
                                          color: (f['changed'] as bool)
                                              ? const PdfColor(0.94, 0.39, 0.13)
                                              : null),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }(),
            ],
          ],
          pw.SizedBox(height: 20),
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 8),
          pw.Text('Generated by LenDen • ${DateTime.now().year}',
              style: pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey500)),
        ],
      ),
    );
    return doc.save();
  }

  pw.TableRow _pdfRow(String label, String value,
      {bool lightGrey = false, PdfColor? valueColor}) {
    const textDark = PdfColor.fromInt(0xFF1A1A1A);
    const lightGreyColor = PdfColor.fromInt(0xFFF5F5F5);
    return pw.TableRow(
      decoration: lightGrey
          ? const pw.BoxDecoration(color: lightGreyColor)
          : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: valueColor ?? textDark)),
        ),
      ],
    );
  }

  pw.Widget _pdfCell(String text,
      {bool bold = false,
      bool strikethrough = false,
      PdfColor? color}) {
    const textDark = PdfColor.fromInt(0xFF1A1A1A);
    return pw.Padding(
      padding: const pw.EdgeInsets.fromLTRB(6, 5, 6, 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? textDark,
          decoration: strikethrough
              ? pw.TextDecoration.lineThrough
              : pw.TextDecoration.none,
        ),
      ),
    );
  }

  // ─── Share sheet ─────────────────────────────────────────────────────────────

  void _showShareSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share Transaction History',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              _shareOption(
                icon: Icons.picture_as_pdf_outlined,
                color: Colors.red,
                label: 'Share as PDF',
                subtitle: 'Full history in a formatted PDF',
                onTap: () async {
                  Navigator.pop(context);
                  await _sharePdf();
                },
              ),
              const Divider(height: 1),
              _shareOption(
                icon: Icons.text_snippet_outlined,
                color: Colors.blue,
                label: 'Share as Text',
                subtitle: 'Send via WhatsApp, email, or any app',
                onTap: () async {
                  Navigator.pop(context);
                  await _shareText();
                },
              ),
              const Divider(height: 1),
              _shareOption(
                icon: Icons.copy_outlined,
                color: Colors.teal,
                label: 'Copy Current State',
                subtitle: 'Copy only the current values',
                onTap: () async {
                  Navigator.pop(context);
                  await Clipboard.setData(
                      ClipboardData(text: _buildCurrentStateText()));
                  if (mounted) {
                    ElegantNotification.success(
                      title: const Text('Copied!',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      description: const Text('Current state copied to clipboard'),
                    ).show(context);
                  }
                },
              ),
              const Divider(height: 1),
              _shareOption(
                icon: Icons.history_outlined,
                color: const Color(0xFFF06322),
                label: 'Copy Full History',
                subtitle: 'Copy current state + all edit history',
                onTap: () async {
                  Navigator.pop(context);
                  await Clipboard.setData(
                      ClipboardData(text: _buildFullHistoryText()));
                  if (mounted) {
                    ElegantNotification.success(
                      title: const Text('Copied!',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      description: const Text('Full history copied to clipboard'),
                    ).show(context);
                  }
                },
              ),
              const Divider(height: 1),
              _shareOption(
                icon: Icons.note_add_rounded,
                color: AppColors.tricolorGreen,
                label: 'Share as Note',
                subtitle: 'Send to a LenDen user as a note',
                onTap: () async {
                  Navigator.pop(context);
                  final desc = (_tx['description'] ?? 'Quick Transaction').toString();
                  await showShareAsNoteSheet(context, title: desc, content: _buildCurrentStateText());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareOption({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppThemeColors.mutedText(context))),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: AppThemeColors.mutedText(context), size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _sharePdf() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final bytes = await _buildPdf();
      await shareBytesFile(
        bytes: bytes,
        filename: 'qt_history_$_shortId.pdf',
        subject: 'Quick Transaction History – #$_shortId',
        text: 'Quick Transaction History from LenDen',
        mimeType: 'application/pdf',
      );
    } catch (_) {
      if (mounted) {
        ElegantNotification.error(
          title: const Text('PDF Failed',
              style: TextStyle(fontWeight: FontWeight.bold)),
          description: const Text('Could not generate PDF. Please try again.'),
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _shareText() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await shareTextFile(
        content: _buildFullHistoryText(),
        filename: 'qt_history_$_shortId.txt',
        subject: 'Quick Transaction History – #$_shortId',
        text: 'Quick Transaction History from LenDen',
        mimeType: 'text/plain',
      );
    } catch (_) {
      if (mounted) {
        ElegantNotification.error(
          title: const Text('Share Failed',
              style: TextStyle(fontWeight: FontWeight.bold)),
          description: const Text('Could not share text. Please try again.'),
        ).show(context);
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final history = _history;
    final editCount = history.length;
    final cleared = _tx['cleared'] == true;

    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Edit History',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_isRefreshing || _isSharing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else ...[
            IconButton(
              onPressed: _refreshFromApi,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
            IconButton(
              onPressed: _showShareSheet,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share',
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // ── Wave header ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: const TopWaveClipper(),
              child: Container(
                height: context.sh(180),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF00ACC1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          // ── Header content overlay ──
          Positioned(
            top: context.sh(72),
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fmtAmount(_tx['amount'], _tx['currency']),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    (_tx['description'] ?? '').toString(),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          // ── Scrollable body ──
          Padding(
            padding: EdgeInsets.only(top: context.sh(130)),
            child: RefreshIndicator(
              onRefresh: _refreshFromApi,
              color: AppColors.cyan,
              child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── View Current State button ──
                  GestureDetector(
                    onTap: () => _showStateSheet(
                        cleared ? 'Final State (Cleared)' : 'Current State',
                        _tx),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.info_outline_rounded,
                                color: AppColors.cyan, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cleared
                                      ? 'View Final State (Cleared)'
                                      : 'View Current State',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppThemeColors.primaryText(context),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tap to see all fields — ${_fmtAmount(_tx['amount'], _tx['currency'])}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppThemeColors.mutedText(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: AppThemeColors.mutedText(context)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Edit History section ──
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [AppColors.cyan, Color(0xFF0077B6)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Edit History  ($editCount)',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context)),
                      ),
                      const Spacer(),
                      if (editCount > 0) ...[
                        GestureDetector(
                          onTap: () => setState(() {
                            if (_expandedEdits.length == editCount) {
                              _expandedEdits.clear();
                            } else {
                              _expandedEdits.addAll(
                                  List.generate(editCount, (i) => i));
                            }
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.cyan.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _expandedEdits.length == editCount
                                      ? Icons.unfold_less_rounded
                                      : Icons.unfold_more_rounded,
                                  size: 13,
                                  color: AppColors.cyan,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _expandedEdits.length == editCount
                                      ? 'Collapse all'
                                      : 'Expand all',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.cyan),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'Pull to refresh',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppThemeColors.mutedText(context)),
                      ),
                    ],
                  ),
                  if (editCount > 0) ...[
                    const SizedBox(height: 10),
                    _statsRow(history),
                    const SizedBox(height: 10),
                    _amountJourneyCard(history),
                  ],
                  const SizedBox(height: 12),

                  if (editCount == 0)
                    _emptyHistory()
                  else
                    _buildTimeline(history),

                  const SizedBox(height: 24),
                ],
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(List<Map<String, dynamic>> history) {
    final firstEntry = history.first;
    final lastEntry = history.last;
    final editCount = history.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _statChip(
            Icons.edit_rounded,
            '$editCount edit${editCount == 1 ? '' : 's'}',
            const Color(0xFFF06322),
          ),
          const SizedBox(width: 8),
          _statChip(
            Icons.start_rounded,
            'First: ${_timeAgo(firstEntry['editedAt'])}',
            Colors.teal,
          ),
          const SizedBox(width: 8),
          _statChip(
            Icons.access_time_filled_rounded,
            'Last: ${_timeAgo(lastEntry['editedAt'])}',
            Colors.purple,
          ),
          if (firstEntry['editedBy'] != null) ...[
            const SizedBox(width: 8),
            _statChip(
              Icons.person_rounded,
              (firstEntry['editedBy'] as String).split('@').first,
              Colors.indigo,
            ),
          ],
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _emptyHistory() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.edit_off_outlined,
              size: 52, color: AppThemeColors.divider(context)),
          const SizedBox(height: 12),
          Text('No edits yet',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.primaryText(context))),
          const SizedBox(height: 6),
          Text('This transaction has not been edited.',
              style: TextStyle(
                  fontSize: 12,
                  color: AppThemeColors.mutedText(context))),
        ],
      ),
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> history) {
    final items = <Widget>[];

    // Created item — original state (editHistory[0] is the pre-first-edit snapshot)
    final orig = history.first;
    final createdAgo = _timeAgo(_tx['createdAt']);
    items.add(_timelineItem(
      icon: Icons.flag_circle_rounded,
      color: Colors.teal,
      label: 'Original Creation',
      date: '${_fmtDateTime(_tx['createdAt'])}${createdAgo.isNotEmpty ? '  •  $createdAgo' : ''}',
      onViewState: () => _showStateSheet('Original State', orig),
      viewStateLabel: 'View original state',
      isFirst: true,
    ));

    // Edit items
    for (int i = 0; i < history.length; i++) {
      final entry = history[i];
      final nextState = i + 1 < history.length ? history[i + 1] : _tx;
      final fields = _allFields(entry, nextState);
      final by = (entry['editedBy'] ?? '—').toString();
      final ago = _timeAgo(entry['editedAt']);
      final changedCount = fields.where((f) => f['changed'] == true).length;

      // Amount change chip label
      final amtBefore = _fmtAmount(entry['amount'], entry['currency']);
      final amtAfter = _fmtAmount(nextState['amount'], nextState['currency']);
      final amountDiff = amtBefore != amtAfter ? '$amtBefore → $amtAfter' : null;

      // Copy text for this edit
      final copyText = () {
        final buf = StringBuffer();
        buf.writeln('[Edit ${i + 1}] ${_fmtDateTime(entry['editedAt'])}');
        buf.writeln('By: ${entry['editedBy'] ?? '—'}');
        for (final f in fields) {
          final changed = f['changed'] as bool;
          buf.writeln(changed
              ? '  [CHANGED] ${f['label']}: ${f['old']} → ${f['new']}'
              : '  [same]    ${f['label']}: ${f['new']}');
        }
        return buf.toString();
      }();

      final idx = i;
      items.add(_timelineItem(
        icon: Icons.edit_rounded,
        color: const Color(0xFFF06322),
        label: 'Edit ${i + 1}',
        date: '${_fmtDateTime(entry['editedAt'])}${ago.isNotEmpty ? '  •  $ago' : ''}',
        subtitle: 'by ${by.split('@').first}',
        fields: fields,
        changedCount: changedCount,
        amountDiff: amountDiff,
        isExpanded: _expandedEdits.contains(idx),
        onToggleExpand: () => setState(() {
          if (_expandedEdits.contains(idx)) {
            _expandedEdits.remove(idx);
          } else {
            _expandedEdits.add(idx);
          }
        }),
        onCopyEdit: () {
          Clipboard.setData(ClipboardData(text: copyText)).then((_) {
            if (mounted) {
              ElegantNotification.success(
                title: const Text('Copied',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                description:
                    Text('Edit ${idx + 1} details copied to clipboard'),
              ).show(context);
            }
          });
        },
        onViewState: () => _showStateSheet('State After Edit ${i + 1}', nextState),
        viewStateLabel: 'View state after this edit',
        isLast: i == history.length - 1,
      ));
    }

    // Current state anchor — tap to view
    final updatedAgo = _timeAgo(_tx['updatedAt']);
    final clearedNow = _tx['cleared'] == true;
    items.add(_timelineItem(
      icon: clearedNow ? Icons.check_circle_rounded : Icons.radio_button_checked,
      color: clearedNow ? Colors.green : AppColors.cyan,
      label: clearedNow ? 'Cleared' : 'Current State',
      date: '${_fmtDateTime(_tx['updatedAt'])}${updatedAgo.isNotEmpty ? '  •  $updatedAgo' : ''}',
      onViewState: () => _showStateSheet(
          clearedNow ? 'Final State (Cleared)' : 'Current State', _tx),
      viewStateLabel: clearedNow ? 'View final state' : 'View current state',
      isLast: true,
    ));

    return Column(children: items);
  }

  bool get cleared => _tx['cleared'] == true;

  Widget _timelineItem({
    required IconData icon,
    required Color color,
    required String label,
    required String date,
    String? subtitle,
    List<Map<String, dynamic>>? fields,
    int? changedCount,
    String? amountDiff,
    bool isExpanded = true,
    VoidCallback? onToggleExpand,
    VoidCallback? onCopyEdit,
    VoidCallback? onViewState,
    String? viewStateLabel,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon + connector ──
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppThemeColors.divider(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // ── Content ──
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row — tappable if collapsible
                  GestureDetector(
                    onTap: onToggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeColors.primaryText(context))),
                        ),
                        if (onToggleExpand != null)
                          Icon(
                            isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: AppThemeColors.mutedText(context),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(date,
                      style: TextStyle(
                          fontSize: 11,
                          color: AppThemeColors.mutedText(context))),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppThemeColors.secondaryText(context))),
                  ],
                  // Badges row: changed count + amount diff (always visible)
                  if (changedCount != null || amountDiff != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (changedCount != null)
                          _badge(
                            '$changedCount of 6 changed',
                            const Color(0xFFF06322),
                          ),
                        if (amountDiff != null)
                          _badge(amountDiff, Colors.deepPurple),
                      ],
                    ),
                  ],
                  // Full field table (edit entries only, collapsible)
                  if (fields != null && isExpanded) ...[
                    const SizedBox(height: 8),
                    _fieldTable(fields),
                  ],
                  // Action buttons row (copy + view state) — collapsible edit items only
                  if (onToggleExpand != null &&
                      isExpanded &&
                      (onCopyEdit != null || onViewState != null)) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (onCopyEdit != null)
                          _actionChip(
                            Icons.copy_rounded,
                            'Copy edit',
                            AppThemeColors.mutedText(context),
                            onCopyEdit,
                          ),
                        if (onViewState != null)
                          _actionChip(
                            Icons.visibility_outlined,
                            viewStateLabel ?? 'View state',
                            AppColors.cyan,
                            onViewState,
                          ),
                      ],
                    ),
                  ],
                  // For non-collapsible items (original/current), just show view button
                  if (onToggleExpand == null && onViewState != null) ...[
                    const SizedBox(height: 10),
                    _actionChip(
                      Icons.visibility_outlined,
                      viewStateLabel ?? 'View state',
                      AppColors.cyan,
                      onViewState,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Shows all 6 fields: changed ones highlighted with strikethrough old → bold new.
  Widget _fieldTable(List<Map<String, dynamic>> fields) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppThemeColors.divider(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: fields.asMap().entries.map((entry) {
            final i = entry.key;
            final f = entry.value;
            final changed = f['changed'] as bool;
            final isLastRow = i == fields.length - 1;
            return Column(
              children: [
                Container(
                  color: changed
                      ? const Color(0xFFF06322).withValues(alpha: 0.07)
                      : null,
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Row(
                    children: [
                      // Field label
                      SizedBox(
                        width: 76,
                        child: Row(
                          children: [
                            if (changed)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.circle,
                                    size: 6, color: Color(0xFFF06322)),
                              ),
                            Expanded(
                              child: Text(
                                f['label'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: changed
                                      ? const Color(0xFFF06322)
                                      : AppThemeColors.mutedText(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Value(s)
                      Expanded(
                        child: changed
                            ? Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      f['old'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: AppThemeColors.mutedText(context),
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 6),
                                    child: Icon(Icons.arrow_forward_rounded,
                                        size: 11, color: Color(0xFFF06322)),
                                  ),
                                  Flexible(
                                    child: Text(
                                      f['new'] as String,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF06322),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              )
                            : Text(
                                f['new'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppThemeColors.secondaryText(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),
                ),
                if (!isLastRow)
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppThemeColors.divider(context)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // Read-only snapshot for the "Original Creation" item.
  Widget _snapshotTable(Map<String, dynamic> snap) {
    final rows = [
      ('Amount',      _fmtAmount(snap['amount'], snap['currency'])),
      ('Description', (snap['description'] ?? '—').toString()),
      ('Category',    _catLabel(snap['category']?.toString())),
      ('Role',        _roleLbl((snap['role'] ?? 'lender').toString())),
      ('Date',        _fmtDate(snap['date'])),
      ('Time',        (snap['time'] ?? '—').toString()),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppThemeColors.divider(context)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: rows.asMap().entries.map((entry) {
            final i = entry.key;
            final (label, value) = entry.value;
            final isLastRow = i == rows.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppThemeColors.mutedText(context),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppThemeColors.secondaryText(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLastRow)
                  Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppThemeColors.divider(context)),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Small UI helpers ────────────────────────────────────────────────────────

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _actionChip(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _amountJourneyCard(List<Map<String, dynamic>> history) {
    final origAmount = double.tryParse(
            history.first['amount']?.toString() ?? '') ??
        0;
    final currAmount =
        double.tryParse(_tx['amount']?.toString() ?? '') ?? 0;
    final currency = (_tx['currency'] ?? 'INR').toString();
    final diff = currAmount - origAmount;
    final pct = origAmount != 0 ? (diff / origAmount * 100) : 0.0;
    final increased = diff > 0;
    final unchanged = diff == 0;
    final diffColor = unchanged
        ? AppThemeColors.mutedText(context)
        : increased
            ? Colors.green.shade600
            : Colors.red.shade600;
    final diffIcon = unchanged
        ? Icons.remove_rounded
        : increased
            ? Icons.arrow_upward_rounded
            : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeColors.divider(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.show_chart_rounded,
              size: 16, color: AppThemeColors.mutedText(context)),
          const SizedBox(width: 8),
          Text('Amount journey:',
              style: TextStyle(
                  fontSize: 11,
                  color: AppThemeColors.mutedText(context),
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_fmtAmount(history.first['amount'], currency)}  →  ${_fmtAmount(_tx['amount'], currency)}',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppThemeColors.primaryText(context)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: diffColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(diffIcon, size: 11, color: diffColor),
                const SizedBox(width: 2),
                Text(
                  unchanged
                      ? 'No change'
                      : '${pct.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 10,
                      color: diffColor,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── State bottom sheet ──────────────────────────────────────────────────────

  void _showStateSheet(String label, Map<String, dynamic> snap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.88,
        expand: false,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppThemeColors.divider(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.cyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                      color: AppThemeColors.mutedText(context),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: AppThemeColors.divider(context)),
              Expanded(
                child: SingleChildScrollView(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _snapshotTable(snap),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color: AppThemeColors.divider(context)),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppThemeColors.mutedText(context),
                        ),
                      ),
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
}
