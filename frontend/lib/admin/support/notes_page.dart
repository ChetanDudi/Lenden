import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import '../../widgets/share_as_note_sheet.dart';
import 'dart:async';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../session.dart';
import 'note_form_page.dart';

class AdminNotesPage extends StatefulWidget {
  const AdminNotesPage({Key? key}) : super(key: key);
  @override
  State<AdminNotesPage> createState() => _AdminNotesPageState();
}

class _AdminNotesPageState extends State<AdminNotesPage> with TickerProviderStateMixin {
  // Own notes
  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> filteredNotes = [];
  bool loading = true;
  String? error;

  // Shared notes (received from other admins)
  List<Map<String, dynamic>> sharedNotes = [];
  List<Map<String, dynamic>> filteredSharedNotes = [];
  bool loadingShared = true;
  String? errorShared;

  String searchQuery = '';
  String sortBy = 'created_desc';
  final _searchCtrl = TextEditingController();
  late TabController _tabController;

  bool get _isSharedTab => _tabController.index == 1;

  List<Map<String, dynamic>> get _displayedNotes =>
      _isSharedTab ? filteredSharedNotes : filteredNotes;

  bool get _activeLoading => _isSharedTab ? loadingShared : loading;
  String? get _activeError => _isSharedTab ? errorShared : error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    fetchNotes();
    fetchSharedNotes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _sortList(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      switch (sortBy) {
        case 'created_asc':  return (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? '');
        case 'created_desc': return (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? '');
        case 'updated_asc':  return (a['updatedAt'] ?? '').compareTo(b['updatedAt'] ?? '');
        case 'updated_desc': return (b['updatedAt'] ?? '').compareTo(a['updatedAt'] ?? '');
        case 'title_az':     return (a['title'] ?? '').toLowerCase().compareTo((b['title'] ?? '').toLowerCase());
        case 'title_za':     return (b['title'] ?? '').toLowerCase().compareTo((a['title'] ?? '').toLowerCase());
        default:             return 0;
      }
    });
  }

  void sortNotes() {
    setState(() {
      _sortList(filteredNotes);
      _sortList(filteredSharedNotes);
    });
  }

  void filterNotes(String query) {
    setState(() {
      searchQuery = query;
      final q = query.toLowerCase();
      filteredNotes = notes
          .where((n) =>
              (n['title'] ?? '').toLowerCase().contains(q) ||
              (n['content'] ?? '').toLowerCase().contains(q))
          .toList();
      filteredSharedNotes = sharedNotes
          .where((n) =>
              (n['title'] ?? '').toLowerCase().contains(q) ||
              (n['content'] ?? '').toLowerCase().contains(q))
          .toList();
      _sortList(filteredNotes);
      _sortList(filteredSharedNotes);
    });
  }

  Future<void> fetchNotes() async {
    setState(() { loading = true; error = null; });
    try {
      final res = await ApiClient.get('/api/notes');
      if (res.statusCode == 200) {
        final fetched = List<Map<String, dynamic>>.from(json.decode(res.body)['notes']);
        setState(() {
          notes = fetched;
          filteredNotes = fetched;
          _sortList(filteredNotes);
          loading = false;
        });
      } else {
        setState(() {
          error = AppLocalizations.of(context).t('failed_to_load_notes');
          loading = false;
        });
      }
    } catch (_) {
      setState(() {
        error = AppLocalizations.of(context).t('failed_to_load_notes');
        loading = false;
      });
    }
  }

  Future<void> fetchSharedNotes() async {
    setState(() { loadingShared = true; errorShared = null; });
    try {
      final res = await ApiClient.get('/api/notes/shared');
      if (res.statusCode == 200) {
        final fetched = List<Map<String, dynamic>>.from(json.decode(res.body)['notes']);
        setState(() {
          sharedNotes = fetched;
          filteredSharedNotes = fetched;
          _sortList(filteredSharedNotes);
          loadingShared = false;
        });
      } else {
        setState(() { errorShared = 'Failed to load shared notes'; loadingShared = false; });
      }
    } catch (_) {
      setState(() { errorShared = 'Failed to load shared notes'; loadingShared = false; });
    }
  }

  Future<void> createOrEditNote({Map<String, dynamic>? note}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage(note: note)),
    );
    if (result == true) {
      if (note != null && note['isShared'] == true) {
        fetchSharedNotes();
      } else {
        fetchNotes();
      }
    }
  }

  PopupMenuItem _noteMenuItem(IconData icon, String label, Color color, VoidCallback onTap) {
    return PopupMenuItem(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppThemeColors.primaryText(context))),
        ],
      ),
    );
  }

  Future<void> deleteNote(String id) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.red, size: 24),
            ),
            const SizedBox(width: 12),
            Text(t('delete_note'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppThemeColors.primaryText(dialogContext))),
          ],
        ),
        content: Text(t('delete_note_confirm'),
            style: TextStyle(fontSize: 15, color: AppThemeColors.secondaryText(dialogContext))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
            child: Text(t('cancel'),
                style: TextStyle(
                    color: AppThemeColors.secondaryText(dialogContext),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t('delete'),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await ApiClient.delete('/api/notes/$id');
      if (res.statusCode == 200 && mounted) {
        setState(() {
          if (_isSharedTab) {
            sharedNotes.removeWhere((n) => n['_id'] == id);
          } else {
            notes.removeWhere((n) => n['_id'] == id);
          }
          filterNotes(searchQuery);
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${m[dt.month - 1]}, ${dt.year.toString().substring(2)}';
  }

  void _copyAllNotes() {
    final loc = AppLocalizations.of(context).t;
    final toCopy = _displayedNotes;
    if (toCopy.isEmpty) { showSnack(context, loc('no_notes_to_copy'), isError: true); return; }
    final buf = StringBuffer();
    for (int i = 0; i < toCopy.length; i++) {
      buf.write('--- Note ${i + 1}: ${toCopy[i]['title'] ?? ''} ---\n${toCopy[i]['content'] ?? ''}');
      if (i < toCopy.length - 1) buf.write('\n\n');
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    showSnack(context, loc('copied_to_clipboard_message'));
  }

  Future<void> _deleteAllNotes() async {
    final toDelete = List<Map<String, dynamic>>.from(_displayedNotes);
    if (toDelete.isEmpty) { showSnack(context, 'No notes to delete.', isError: true); return; }
    final loc = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 12),
          Text('Delete All Notes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppThemeColors.primaryText(ctx))),
        ]),
        content: Text(
          'This will permanently delete all ${toDelete.length} note${toDelete.length == 1 ? '' : 's'}.',
          style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    int deleted = 0;
    for (final note in toDelete) {
      final res = await ApiClient.delete('/api/notes/${note['_id']}');
      if (res.statusCode == 200) {
        deleted++;
        if (mounted) {
          setState(() {
            if (_isSharedTab) {
              sharedNotes.removeWhere((n) => n['_id'] == note['_id']);
            } else {
              notes.removeWhere((n) => n['_id'] == note['_id']);
            }
            filterNotes(searchQuery);
          });
        }
      }
    }
    if (mounted) showSnack(context, 'Deleted $deleted note${deleted == 1 ? '' : 's'}.', isError: deleted < toDelete.length);
  }

  void _showSortBottomSheet() {
    final t = AppLocalizations.of(context).t;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(sheetCtx),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppThemeColors.divider(sheetCtx), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.sort, color: Colors.blue, size: 20),
                ),
                const SizedBox(width: 12),
                Text(t('sort_by'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(sheetCtx))),
              ]),
            ),
            Divider(height: 1, thickness: 1, color: AppThemeColors.divider(sheetCtx)),
            _buildSortOption('created_desc', t('newest_first'), Icons.new_releases),
            _buildSortOption('created_asc', t('oldest_first'), Icons.access_time),
            _buildSortOption('updated_desc', t('recently_updated'), Icons.update),
            _buildSortOption('updated_asc', t('least_updated'), Icons.history),
            _buildSortOption('title_az', t('title_a_z'), Icons.sort_by_alpha),
            _buildSortOption('title_za', t('title_z_a'), Icons.sort_by_alpha),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String value, String label, IconData icon) {
    final isSelected = sortBy == value;
    return InkWell(
      onTap: () {
        setState(() { sortBy = value; sortNotes(); });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withValues(alpha: 0.05) : Colors.transparent,
          border: Border(left: BorderSide(color: isSelected ? Colors.blue : Colors.transparent, width: 3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.blue : AppThemeColors.secondaryText(context), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label, style: TextStyle(
                  fontSize: 15,
                  color: isSelected ? Colors.blue : AppThemeColors.primaryText(context),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
      ),
    );
  }

  String _myEmail() =>
      Provider.of<SessionProvider>(context, listen: false).user?['email']?.toString() ?? '';

  void _shareAllSystem() {
    final toCopy = _displayedNotes;
    if (toCopy.isEmpty) { showSnack(context, AppLocalizations.of(context).t('no_notes_to_share'), isError: true); return; }
    final buffer = StringBuffer();
    for (int i = 0; i < toCopy.length; i++) {
      buffer.write('--- Note ${i + 1}: ${toCopy[i]['title'] ?? ''} ---\n${toCopy[i]['content'] ?? ''}');
      if (i < toCopy.length - 1) buffer.write('\n\n');
    }
    Share.share(buffer.toString());
  }

  Future<void> _shareAllAsSingle() async {
    final toCopy = _displayedNotes;
    if (toCopy.isEmpty) { showSnack(context, AppLocalizations.of(context).t('no_notes_to_share'), isError: true); return; }
    final buffer = StringBuffer();
    for (int i = 0; i < toCopy.length; i++) {
      buffer.write('--- Note ${i + 1}: ${toCopy[i]['title'] ?? ''} ---\n${toCopy[i]['content'] ?? ''}');
      if (i < toCopy.length - 1) buffer.write('\n\n');
    }
    await showShareAsNoteSheet(
      context,
      title: 'All Notes (${toCopy.length})',
      content: buffer.toString(),
      adminOnly: true,
      currentUserEmail: _myEmail(),
    );
  }

  Future<void> _showShareAllIndividualSheet(List<Map<String, dynamic>> notesToShare) async {
    if (notesToShare.isEmpty) { showSnack(context, AppLocalizations.of(context).t('no_notes_to_share'), isError: true); return; }
    final searchCtrl = TextEditingController();
    Timer? debounce;
    List<Map<String, dynamic>> users = [];
    bool sheetLoading = false;
    bool _initialLoaded = false;
    String? sendingEmail;

    Future<void> loadUsers(String q, StateSetter setSheet) async {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), () async {
        setSheet(() => sheetLoading = true);
        try {
          final res = await ApiClient.get('/api/notes/recipients?q=${Uri.encodeComponent(q.trim())}');
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            setSheet(() => users = List<Map<String, dynamic>>.from(data['users'] ?? []));
          }
        } catch (_) {} finally {
          setSheet(() => sheetLoading = false);
        }
      });
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (ctx2, setSheet) {
            if (!_initialLoaded) { _initialLoaded = true; Future.microtask(() => loadUsers('', setSheet)); }
            return Container(
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(ctx2),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(children: [
                const SizedBox(height: 12),
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppThemeColors.divider(ctx2), borderRadius: BorderRadius.circular(2)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.tricolorGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.note_add_rounded, color: AppColors.tricolorGreen, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Share All as Individual Notes',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(ctx2))),
                      Text('${notesToShare.length} notes will be sent separately',
                        style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx2))),
                    ])),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  child: TextField(
                    controller: searchCtrl,
                    onChanged: (q) => loadUsers(q, setSheet),
                    decoration: InputDecoration(
                      hintText: 'Search admins by name or email...',
                      hintStyle: TextStyle(color: AppThemeColors.secondaryText(ctx2), fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: AppThemeColors.surfaceBg(ctx2),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                  ),
                ),
                Expanded(
                  child: sheetLoading
                    ? const Center(child: CircularProgressIndicator())
                    : users.isEmpty
                      ? Center(child: Text(
                          searchCtrl.text.isEmpty ? 'No admins found — search by name or email' : 'No admins found',
                          style: TextStyle(color: AppThemeColors.secondaryText(ctx2), fontSize: 14),
                          textAlign: TextAlign.center))
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          itemCount: users.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: AppThemeColors.divider(ctx2)),
                          itemBuilder: (_, i) {
                            final u = users[i];
                            final email = (u['email'] ?? '').toString();
                            final name = (u['name'] ?? email).toString();
                            final username = (u['username'] ?? '').toString();
                            final isSending = sendingEmail == email;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.bold)),
                              ),
                              title: Text(name, style: TextStyle(fontWeight: FontWeight.w600, color: AppThemeColors.primaryText(ctx2))),
                              subtitle: Text(username.isNotEmpty ? '@$username  ·  $email' : email,
                                style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(ctx2)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: isSending
                                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                : ElevatedButton(
                                    onPressed: sendingEmail != null ? null : () async {
                                      setSheet(() => sendingEmail = email);
                                      int sent = 0;
                                      for (final note in notesToShare) {
                                        try {
                                          final res = await ApiClient.post('/api/notes/share-content', body: {
                                            'title': (note['title'] ?? '').toString(),
                                            'content': (note['content'] ?? '').toString(),
                                            'targetEmail': email,
                                          });
                                          if (res.statusCode == 201) sent++;
                                        } catch (_) {}
                                      }
                                      setSheet(() => sendingEmail = null);
                                      if (mounted) {
                                        Navigator.pop(ctx);
                                        showSnack(context, 'Sent $sent of ${notesToShare.length} notes to $name.');
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.tricolorGreen,
                                      disabledBackgroundColor: AppColors.tricolorGreen.withValues(alpha: 0.4),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 0,
                                      minimumSize: const Size(60, 34),
                                    ),
                                    child: const Text('Send', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ),
                            );
                          }),
                ),
              ]),
            );
          },
        ),
      ),
    );
    debounce?.cancel();
    searchCtrl.dispose();
  }

  List<PopupMenuEntry> _buildNoteMenu(Map<String, dynamic> note) {
    final t = AppLocalizations.of(context).t;
    final noteId = note['_id']?.toString() ?? '';
    final noteTitle = (note['title'] ?? '').toString();
    final noteContent = (note['content'] ?? '').toString();
    return [
      _noteMenuItem(Icons.edit, t('edit_note'), Colors.blue,
          () => Future.delayed(Duration.zero, () => createOrEditNote(note: note))),
      _noteMenuItem(Icons.copy_rounded, t('copy'), Colors.teal, () {
        Clipboard.setData(ClipboardData(text: '$noteTitle\n\n$noteContent'));
        showSnack(context, t('copied_to_clipboard_message'));
      }),
      _noteMenuItem(Icons.share_rounded, t('share'), Colors.indigo,
          () => Share.share('$noteTitle\n\n$noteContent')),
      _noteMenuItem(Icons.note_add_rounded, AppLocalizations.of(context).t('share_as_note'), AppColors.tricolorGreen,
          () => Future.delayed(
            Duration.zero,
            () => showShareAsNoteSheet(
              context,
              title: noteTitle,
              content: noteContent,
              noteId: noteId,
              adminOnly: true,
              currentUserEmail: _myEmail(),
            ),
          )),
      _noteMenuItem(Icons.copy_all_rounded, t('duplicate'), Colors.orange,
          () => Future.delayed(Duration.zero, () async {
            final res = await ApiClient.post('/api/notes', body: {'title': '$noteTitle (copy)', 'content': noteContent});
            if (res.statusCode == 201) {
              final newNote = json.decode(res.body)['note'];
              setState(() { notes.insert(0, newNote); filterNotes(searchQuery); });
              if (_isSharedTab) _tabController.animateTo(0);
            }
          })),
      _noteMenuItem(Icons.delete_rounded, t('delete_note'), Colors.red,
          () => Future.delayed(Duration.zero, () => deleteNote(noteId))),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0, left: 0, right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(colors: [AppColors.cyan, Color(0xFF48CAE4)]),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pushReplacementNamed(context, '/admin/dashboard'),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(t('admin_notes'),
                              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                                  color: AppThemeColors.primaryText(context), letterSpacing: 1.2)),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: AppThemeColors.primaryText(context)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        color: AppThemeColors.cardBg(context),
                        onSelected: (v) async {
                          switch (v) {
                            case 'copy_all':
                              _copyAllNotes();
                              break;
                            case 'share_all':
                              _shareAllSystem();
                              break;
                            case 'share_single':
                              _shareAllAsSingle();
                              break;
                            case 'share_individual':
                              _showShareAllIndividualSheet(List<Map<String, dynamic>>.from(_displayedNotes));
                              break;
                            case 'delete_all':
                              _deleteAllNotes();
                              break;
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem<String>(
                            value: 'copy_all',
                            child: Row(children: [
                              Container(padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.copy_all_rounded, color: Colors.teal, size: 17)),
                              const SizedBox(width: 12),
                              Text(t('copy_all_notes'), style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'share_all',
                            child: Row(children: [
                              Container(padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: Colors.indigo.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.share_rounded, color: Colors.indigo, size: 17)),
                              const SizedBox(width: 12),
                              Text(t('share_all_notes'), style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'share_single',
                            child: Row(children: [
                              Container(padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: AppColors.tricolorGreen.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.note_add_rounded, color: AppColors.tricolorGreen, size: 17)),
                              const SizedBox(width: 12),
                              Flexible(child: Text(t('share_all_as_single_note'), style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context)))),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'share_individual',
                            child: Row(children: [
                              Container(padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.note_alt_rounded, color: Colors.orange, size: 17)),
                              const SizedBox(width: 12),
                              Flexible(child: Text(t('share_all_as_individual_notes'), style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context)))),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete_all',
                            child: Row(children: [
                              Container(padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 17)),
                              const SizedBox(width: 12),
                              Text(t('delete_all'), style: TextStyle(fontSize: 14, color: AppThemeColors.primaryText(context))),
                            ]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Tab bar
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: AppThemeColors.surfaceBg(context),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4, offset: const Offset(0, 2))],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: AppThemeColors.primaryText(context),
                    unselectedLabelColor: AppThemeColors.secondaryText(context),
                    labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    unselectedLabelStyle: const TextStyle(fontSize: 14),
                    tabs: [
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.notes_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Yours'),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: AppColors.cyan.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                              child: Text('${notes.length}', style: const TextStyle(fontSize: 11, color: AppColors.cyan)),
                            ),
                          ],
                        ]),
                      ),
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.share_rounded, size: 16),
                          const SizedBox(width: 6),
                          const Text('Shared'),
                          if (sharedNotes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: AppColors.tricolorGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                              child: Text('${sharedNotes.length}', style: TextStyle(fontSize: 11, color: AppColors.tricolorGreen)),
                            ),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Search Bar
                AppSearchBar(
                  controller: _searchCtrl,
                  hintText: t('search_notes'),
                  onChanged: filterNotes,
                  margin: const EdgeInsets.symmetric(horizontal: 20.0),
                ),

                const SizedBox(height: 12),

                // Sort button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _showSortBottomSheet,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Colors.orange, Colors.white, Colors.green],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(color: AppThemeColors.cardBg(context), borderRadius: BorderRadius.circular(18)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.filter_list, color: AppThemeColors.primaryText(context), size: 18),
                                const SizedBox(width: 6),
                                Text(t('sort'), style: TextStyle(color: AppThemeColors.primaryText(context), fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Notes list
                Expanded(
                  child: _activeLoading
                      ? Center(child: CircularProgressIndicator(color: AppThemeColors.primaryText(context)))
                      : _activeError != null
                          ? errorStateWidget(context, _activeError!, _isSharedTab ? fetchSharedNotes : fetchNotes)
                          : _displayedNotes.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isSharedTab ? Icons.inbox_rounded : Icons.note_outlined,
                                        size: 64, color: AppThemeColors.mutedText(context),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _isSharedTab ? 'No notes shared with you yet' : t('no_notes_yet'),
                                        style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 18, fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _isSharedTab
                                            ? 'When another admin shares a note with you it appears here'
                                            : t('tap_plus_to_create_note'),
                                        style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () async {
                                    if (_isSharedTab) await fetchSharedNotes(); else await fetchNotes();
                                  },
                                  color: AppColors.cyan,
                                  child: ListView.separated(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                                    itemCount: _displayedNotes.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                                    itemBuilder: (context, i) {
                                      final note = _displayedNotes[i];
                                      return GestureDetector(
                                        onTap: () => createOrEditNote(note: note),
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(22),
                                            gradient: const LinearGradient(
                                              colors: [Colors.orange, Colors.white, Colors.green],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(color: _getNoteColor(i, context), borderRadius: BorderRadius.circular(20)),
                                            child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (note['isShared'] == true && note['sharedFrom'] != null) ...[
                                                    Container(
                                                      margin: const EdgeInsets.only(bottom: 10),
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.tricolorGreen.withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(20),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(Icons.share_rounded, size: 12, color: AppColors.tricolorGreen),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            'From ${note['sharedFrom']['senderName'] ?? note['sharedFrom']['senderEmail'] ?? 'Unknown'}',
                                                            style: TextStyle(fontSize: 11, color: AppColors.tricolorGreen, fontWeight: FontWeight.w600),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          note['title'] ?? t('no_title_label'),
                                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(context)),
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                      ),
                                                      PopupMenuButton(
                                                        icon: Container(
                                                          padding: const EdgeInsets.all(4),
                                                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8)),
                                                          child: Icon(Icons.more_vert, color: AppThemeColors.secondaryText(context), size: 20),
                                                        ),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                        elevation: 8,
                                                        offset: const Offset(0, 8),
                                                        itemBuilder: (_) => _buildNoteMenu(note),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      Icon(Icons.calendar_today, size: 12, color: AppThemeColors.mutedText(context)),
                                                      const SizedBox(width: 4),
                                                      Text('${t('created')}: ${_formatDate(note['createdAt'])}',
                                                          style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                                      const SizedBox(width: 12),
                                                      Icon(Icons.update, size: 12, color: AppThemeColors.mutedText(context)),
                                                      const SizedBox(width: 4),
                                                      Text('${t('updated')}: ${_formatDate(note['updatedAt'])}',
                                                          style: TextStyle(fontSize: 11, color: AppThemeColors.mutedText(context))),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    note['content'] ?? '',
                                                    style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context), height: 1.4),
                                                    maxLines: 4,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: !_isSharedTab
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Colors.orange, Colors.green], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: FloatingActionButton(
                onPressed: () => createOrEditNote(),
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: const Icon(Icons.add, color: Colors.white, size: 28),
              ),
            )
          : null,
    );
  }

  Color _getNoteColor(int index, BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    final colors = isDark
        ? [const Color(0xFF2C2418), const Color(0xFF192519), const Color(0xFF2A1A1E),
           const Color(0xFF161E2C), const Color(0xFF26240E), const Color(0xFF221628)]
        : [const Color(0xFFFFF4E6), const Color(0xFFE8F5E9), const Color(0xFFFCE4EC),
           const Color(0xFFE3F2FD), const Color(0xFFFFF9C4), const Color(0xFFF3E5F5)];
    return colors[index % colors.length];
  }
}
