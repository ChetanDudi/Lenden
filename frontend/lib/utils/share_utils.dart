import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ════════════════════════════════════════════════════════════════════════════
// FILE SHARING UTILITY
// ════════════════════════════════════════════════════════════════════════════

/// Writes [content] to a temp file named [filename] and opens the system share
/// sheet via [Share.shareXFiles].
///
/// Replaces the identical write-then-share pattern repeated in 7 files:
///   - admin_data_export_page.dart
///   - admin_backup_restore_page.dart
///   - admin/manage_users/user_management_page.dart
///   - user/transaction/secure_transactions/secure_transaction_detail_page.dart
///   - user/transaction/secure_transactions/secure_transaction_page.dart
///   - user/transaction/group_transactions/view_group_transactions_page.dart
///   - user/transaction/group_transactions/group_expenses_page.dart
///
/// Parameters:
///   [content]  — the text to write (typically CSV or plain text).
///   [filename] — the temp file name, e.g. `'users_export.csv'`.
///   [subject]  — optional share sheet subject line.
///   [text]     — optional body text shown alongside the file.
///   [mimeType] — MIME type of the file (default: `'text/csv'`).
///
/// Returns `true` on success, `false` on failure (also rethrows if [rethrowErrors]
/// is true).
///
/// Usage:
/// ```dart
/// final ok = await shareTextFile(
///   content: csvBody,
///   filename: 'transactions.csv',
///   subject: 'LenDen Export',
/// );
/// if (!ok && mounted) showSnack(context, 'Share failed', isError: true);
/// ```
Future<bool> shareTextFile({
  required String content,
  required String filename,
  String? subject,
  String? text,
  String mimeType = 'text/csv',
  bool rethrowErrors = false,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: subject,
      text: text,
    );
    return true;
  } catch (e) {
    if (rethrowErrors) rethrow;
    return false;
  }
}

/// Convenience wrapper for sharing a bytes buffer (e.g. a PDF or image).
Future<bool> shareBytesFile({
  required List<int> bytes,
  required String filename,
  String? subject,
  String? text,
  String mimeType = 'application/octet-stream',
  bool rethrowErrors = false,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: subject,
      text: text,
    );
    return true;
  } catch (e) {
    if (rethrowErrors) rethrow;
    return false;
  }
}
