import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'api_client.dart';

// ════════════════════════════════════════════════════════════════════════════
// APP INVITE LINK HELPER
// ════════════════════════════════════════════════════════════════════════════

String? _cachedAppInviteLink;
String? _cachedReferralCode;

/// Call on logout so the next user gets their own referral data.
void clearReferralCache() {
  _cachedAppInviteLink = null;
  _cachedReferralCode = null;
}

/// Returns the admin-configured app invite/download link from the referral API.
/// The link is cached in memory after the first successful fetch.
/// Falls back to an empty string on failure so callers can safely append it.
Future<String> fetchAppInviteLink() async {
  if (_cachedAppInviteLink != null) return _cachedAppInviteLink!;
  try {
    final res = await ApiClient.get('/api/referral/me');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final link = (data['inviteLink'] ?? '').toString().trim();
      final code = (data['referralCode'] ?? '').toString().trim();
      if (link.isNotEmpty) _cachedAppInviteLink = link;
      if (code.isNotEmpty) _cachedReferralCode = code;
      if (link.isNotEmpty) return link;
    }
  } catch (_) {}
  return '';
}

/// Returns the current user's referral code. Cached after first fetch.
Future<String> fetchReferralCode() async {
  if (_cachedReferralCode != null) return _cachedReferralCode!;
  try {
    final res = await ApiClient.get('/api/referral/me');
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final code = (data['referralCode'] ?? '').toString().trim();
      final link = (data['inviteLink'] ?? '').toString().trim();
      if (code.isNotEmpty) _cachedReferralCode = code;
      if (link.isNotEmpty) _cachedAppInviteLink = link;
      return code;
    }
  } catch (_) {}
  return '';
}

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
