import 'dart:async';
import 'dart:convert';
import 'package:elegant_notification/elegant_notification.dart';
import 'package:flutter/material.dart';
import '../utils/api_client.dart';
import '../utils/theme_helper.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';

/// Opens a bottom sheet letting the current user pick a LenDen user (or admin,
/// when [adminOnly] is true) to receive [title]+[content] as a note.
///
/// If [noteId] is non-null the note is shared via POST /api/notes/:id/share
/// (the server copies the existing note). Otherwise content is sent via
/// POST /api/notes/share-content.
///
/// Returns the recipient email on success, null on cancel/failure.
Future<String?> showShareAsNoteSheet(
  BuildContext context, {
  required String title,
  required String content,
  String? noteId,
  bool adminOnly = false,
  String? currentUserEmail,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareAsNoteSheet(
      title: title,
      content: content,
      noteId: noteId,
      adminOnly: adminOnly,
      currentUserEmail: currentUserEmail,
    ),
  );
}

class _ShareAsNoteSheet extends StatefulWidget {
  final String title;
  final String content;
  final String? noteId;
  final bool adminOnly;
  final String? currentUserEmail;
  const _ShareAsNoteSheet({
    required this.title,
    required this.content,
    this.noteId,
    this.adminOnly = false,
    this.currentUserEmail,
  });
  @override
  State<_ShareAsNoteSheet> createState() => _ShareAsNoteSheetState();
}

class _ShareAsNoteSheetState extends State<_ShareAsNoteSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _isSelfSearch = false;
  String? _sharingEmail; // shows spinner on this user's Send button

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(q.trim()));
  }

  Future<void> _load(String q) async {
    if (!mounted) return;
    final selfEmail = widget.currentUserEmail?.toLowerCase().trim() ?? '';
    final isSelf = selfEmail.isNotEmpty && q.toLowerCase().trim() == selfEmail;
    if (isSelf) {
      setState(() { _loading = false; _isSelfSearch = true; _users = []; });
      return;
    }
    setState(() { _loading = true; _isSelfSearch = false; });
    try {
      final encoded = Uri.encodeComponent(q);
      final res = await ApiClient.get('/api/notes/recipients?q=$encoded');
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _users = List<Map<String, dynamic>>.from(data['users'] ?? []));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share(Map<String, dynamic> user) async {
    final email = (user['email'] ?? '').toString();
    if (email.isEmpty) return;
    setState(() => _sharingEmail = email);
    try {
      final res = widget.noteId != null
          ? await ApiClient.post(
              '/api/notes/${widget.noteId}/share',
              body: {'targetEmail': email},
            )
          : await ApiClient.post(
              '/api/notes/share-content',
              body: {
                'title': widget.title,
                'content': widget.content,
                'targetEmail': email,
              },
            );
      if (!mounted) return;
      if (res.statusCode == 201) {
        final name = (user['name'] ?? email).toString();
        Navigator.pop(context, email);
        ElegantNotification.success(
          title: const Text('Note Sent'),
          description: Text('Shared with $name'),
        ).show(context);
      } else {
        final body = jsonDecode(res.body);
        showSnack(context, (body['error'] ?? 'Failed to share').toString(), isError: true);
      }
    } catch (_) {
      if (mounted) showSnack(context, 'Failed to share', isError: true);
    } finally {
      if (mounted) setState(() => _sharingEmail = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppThemeColors.divider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.tricolorGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.note_add_rounded,
                        color: AppColors.tricolorGreen, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share as Note',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        Text(
                          '"${widget.title}"',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppThemeColors.secondaryText(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                decoration: InputDecoration(
                  hintText: widget.adminOnly
                      ? 'Search admins by name or email...'
                      : 'Search users by name, email or @username...',
                  hintStyle:
                      TextStyle(color: AppThemeColors.secondaryText(context), fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: AppThemeColors.surfaceBg(context),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                ),
              ),
            ),
            if (_searchCtrl.text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 6, bottom: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.adminOnly ? 'Other admins' : 'Your contacts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppThemeColors.secondaryText(context),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isSelfSearch ? Icons.info_outline_rounded : Icons.person_search_rounded,
                                  size: 48,
                                  color: _isSelfSearch ? Colors.amber : AppThemeColors.secondaryText(context),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _isSelfSearch
                                      ? "That's you! You already have this note — no need to share it with yourself."
                                      : (_searchCtrl.text.isEmpty
                                          ? (widget.adminOnly
                                              ? 'No other admins found'
                                              : 'No contacts yet — search by name or email')
                                          : 'No users found for "${_searchCtrl.text}"'),
                                  style: TextStyle(
                                      color: _isSelfSearch ? Colors.amber.shade700 : AppThemeColors.secondaryText(context),
                                      fontSize: 14,
                                      fontWeight: _isSelfSearch ? FontWeight.w500 : FontWeight.normal),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: AppThemeColors.divider(context)),
                          itemBuilder: (_, i) {
                            final u = _users[i];
                            final email = (u['email'] ?? '').toString();
                            final name = (u['name'] ?? email).toString();
                            final username = (u['username'] ?? '').toString();
                            final isSending = _sharingEmail == email;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppColors.cyan.withValues(alpha: 0.15),
                                child: Text(
                                  name.isNotEmpty
                                      ? name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      color: AppColors.cyan,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppThemeColors.primaryText(context),
                                ),
                              ),
                              subtitle: Text(
                                username.isNotEmpty
                                    ? '@$username  ·  $email'
                                    : email,
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        AppThemeColors.secondaryText(context)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: isSending
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : ElevatedButton(
                                      onPressed: _sharingEmail != null
                                          ? null
                                          : () => _share(u),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.tricolorGreen,
                                        disabledBackgroundColor: AppColors
                                            .tricolorGreen
                                            .withValues(alpha: 0.4),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 6),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        elevation: 0,
                                        minimumSize: const Size(60, 34),
                                      ),
                                      child: const Text('Send',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13)),
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
