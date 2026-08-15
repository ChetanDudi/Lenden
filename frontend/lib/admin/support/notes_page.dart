import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/search_tab_bar.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';
import 'note_form_page.dart';

class AdminNotesPage extends StatefulWidget {
  const AdminNotesPage({Key? key}) : super(key: key);
  @override
  State<AdminNotesPage> createState() => _AdminNotesPageState();
}

class _AdminNotesPageState extends State<AdminNotesPage> {
  List<Map<String, dynamic>> notes = [];
  List<Map<String, dynamic>> filteredNotes = [];
  bool loading = true;
  String? error;
  String searchQuery = '';
  String sortBy = 'created_desc';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void sortNotes() {
    setState(() {
      filteredNotes.sort((a, b) {
        switch (sortBy) {
          case 'created_asc':
            return (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? '');
          case 'created_desc':
            return (b['createdAt'] ?? '').compareTo(a['createdAt'] ?? '');
          case 'updated_asc':
            return (a['updatedAt'] ?? '').compareTo(b['updatedAt'] ?? '');
          case 'updated_desc':
            return (b['updatedAt'] ?? '').compareTo(a['updatedAt'] ?? '');
          case 'title_az':
            return (a['title'] ?? '')
                .toLowerCase()
                .compareTo((b['title'] ?? '').toLowerCase());
          case 'title_za':
            return (b['title'] ?? '')
                .toLowerCase()
                .compareTo((a['title'] ?? '').toLowerCase());
          default:
            return 0;
        }
      });
    });
  }

  void filterNotes(String query) {
    setState(() {
      searchQuery = query;
      filteredNotes = notes
          .where((note) =>
              (note['title'] ?? '').toLowerCase().contains(query.toLowerCase()) ||
              (note['content'] ?? '').toLowerCase().contains(query.toLowerCase()))
          .toList();
      sortNotes();
    });
  }

  Future<void> fetchNotes() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await ApiClient.get('/api/notes');
      if (res.statusCode == 200) {
        final fetchedNotes =
            List<Map<String, dynamic>>.from(json.decode(res.body)['notes']);
        setState(() {
          notes = fetchedNotes;
          filteredNotes = fetchedNotes;
          sortNotes();
          loading = false;
        });
      } else {
        setState(() {
          error = AppLocalizations.of(context).t('failed_to_load_notes');
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = AppLocalizations.of(context).t('failed_to_load_notes');
        loading = false;
      });
    }
  }

  Future<void> createOrEditNote({Map<String, dynamic>? note}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NoteFormPage(note: note)),
    );
    if (result == true) fetchNotes();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final t = AppLocalizations.of(context).t;
        return AlertDialog(
        backgroundColor: AppThemeColors.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: Colors.red, size: 24),
            ),
            SizedBox(width: 12),
            Text(t('delete_note'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: AppThemeColors.primaryText(context))),
          ],
        ),
        content: Text(
          t('delete_note_confirm'),
          style: TextStyle(fontSize: 15, color: AppThemeColors.secondaryText(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(t('cancel'),
                style: TextStyle(
                    color: AppThemeColors.secondaryText(context),
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('delete'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      );
      },
    );

    if (confirmed == true) {
      final res = await ApiClient.delete('/api/notes/$id');
      if (res.statusCode == 200) {
        setState(() {
          notes.removeWhere((note) => note['_id'] == id);
          filterNotes(searchQuery);
        });
      }
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return '';
    return '${dt.day} ${_getMonthName(dt.month)}, ${dt.year.toString().substring(2)}';
  }

  String _getMonthName(int month) {
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
      'Dec'
    ];
    return months[month - 1];
  }

  void _copyAllNotes() {
    final loc = AppLocalizations.of(context).t;
    if (filteredNotes.isEmpty) {
      showSnack(context, loc('no_notes_to_copy'), isError: true);
      return;
    }
    final buffer = StringBuffer();
    for (int i = 0; i < filteredNotes.length; i++) {
      final note = filteredNotes[i];
      buffer.write('--- Note ${i + 1}: ${note['title'] ?? ''} ---\n');
      buffer.write('${note['content'] ?? ''}');
      if (i < filteredNotes.length - 1) buffer.write('\n\n');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    showSnack(context, loc('copied_to_clipboard_message'));
  }

  Future<void> _deleteAllNotes() async {
    final toDelete = List<Map<String, dynamic>>.from(filteredNotes);
    if (toDelete.isEmpty) {
      showSnack(context, 'No notes to delete.', isError: true);
      return;
    }
    final loc = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_sweep_rounded, color: Colors.red, size: 24),
          ),
          const SizedBox(width: 12),
          Text('Delete All Notes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18,
                  color: AppThemeColors.primaryText(ctx))),
        ]),
        content: Text(
          'This will permanently delete all ${toDelete.length} note${toDelete.length == 1 ? '' : 's'}. This cannot be undone.',
          style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
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
            notes.removeWhere((n) => n['_id'] == note['_id']);
            filterNotes(searchQuery);
          });
        }
      }
    }
    if (mounted) {
      showSnack(context, 'Deleted $deleted note${deleted == 1 ? '' : 's'}.',
          isError: deleted < toDelete.length);
    }
  }

  void _showSortBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final t = AppLocalizations.of(context).t;
        return Container(
        decoration: BoxDecoration(
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(25),
            topRight: Radius.circular(25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppThemeColors.divider(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.sort, color: Colors.blue, size: 20),
                  ),
                  SizedBox(width: 12),
                  Text(
                    t('sort_by'),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context)),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: AppThemeColors.divider(context)),
            _buildSortOption(
                'created_desc', t('newest_first'), Icons.new_releases),
            _buildSortOption('created_asc', t('oldest_first'), Icons.access_time),
            _buildSortOption('updated_desc', t('recently_updated'), Icons.update),
            _buildSortOption('updated_asc', t('least_updated'), Icons.history),
            _buildSortOption('title_az', t('title_a_z'), Icons.sort_by_alpha),
            _buildSortOption('title_za', t('title_z_a'), Icons.sort_by_alpha),
            SizedBox(height: 20),
          ],
        ),
      );
      },
    );
  }

  Widget _buildSortOption(String value, String label, IconData icon) {
    final isSelected = sortBy == value;
    return InkWell(
      onTap: () {
        setState(() {
          sortBy = value;
          sortNotes();
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color:
              isSelected ? Colors.blue.withValues(alpha: 0.05) : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue : AppThemeColors.secondaryText(context),
              size: 20,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isSelected ? Colors.blue : AppThemeColors.primaryText(context),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(156),
                decoration: BoxDecoration(
                  color: AppThemeColors.waveSolid(context),
                  gradient: AppThemeColors.isDark(context)
                      ? null
                      : const LinearGradient(
                          colors: [AppColors.cyan, Color(0xFF48CAE4)],
                        ),
                ),
              ),
            ),
          ),
          SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                          context, '/admin/dashboard');
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        t('admin_notes'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppThemeColors.primaryText(context),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_all_rounded, color: AppThemeColors.primaryText(context)),
                    onPressed: _copyAllNotes,
                    tooltip: AppLocalizations.of(context).t('copy_all_notes'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
                    onPressed: _deleteAllNotes,
                    tooltip: 'Delete all notes',
                  ),
                ],
              ),
            ),

            // Search Bar
            AppSearchBar(
              controller: _searchCtrl,
              hintText: t('search_notes'),
              onChanged: filterNotes,
              margin: const EdgeInsets.symmetric(horizontal: 20.0),
            ),

            const SizedBox(height: 16),

            // Sort button with Tricolor Border
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppThemeColors.cardBg(context),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list,
                                color: AppThemeColors.primaryText(context), size: 18),
                            SizedBox(width: 6),
                            Text(
                              t('sort'),
                              style: TextStyle(
                                color: AppThemeColors.primaryText(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Notes List
            Expanded(
              child: loading
                  ? Center(
                      child: CircularProgressIndicator(color: AppThemeColors.primaryText(context)))
                  : error != null
                      ? errorStateWidget(context, error!, fetchNotes)
                      : filteredNotes.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.note_outlined,
                                      size: 64, color: AppThemeColors.mutedText(context)),
                                  SizedBox(height: 16),
                                  Text(
                                    t('no_notes_yet'),
                                    style: TextStyle(
                                        color: AppThemeColors.mutedText(context),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    t('tap_plus_to_create_note'),
                                    style: TextStyle(
                                        color: AppThemeColors.mutedText(context), fontSize: 14),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20.0, vertical: 8),
                              itemCount: filteredNotes.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, i) {
                                final note = filteredNotes[i];
                                return GestureDetector(
                                  onTap: () => createOrEditNote(note: note),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(22),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.orange,
                                          Colors.white,
                                          Colors.green
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.08),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _getNoteColor(i, context),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    note['title'] ??
                                                        t('no_title_label'),
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: AppThemeColors.primaryText(context),
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                PopupMenuButton(
                                                  icon: Container(
                                                    padding: EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black
                                                          .withValues(alpha: 0.05),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Icon(Icons.more_vert,
                                                        color: AppThemeColors.secondaryText(context),
                                                        size: 20),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16)),
                                                  elevation: 8,
                                                  offset: Offset(0, 8),
                                                  itemBuilder: (context) => [
                                                    _noteMenuItem(Icons.edit, t('edit_note'), Colors.blue,
                                                        () => Future.delayed(Duration.zero, () => createOrEditNote(note: note))),
                                                    _noteMenuItem(Icons.copy_rounded, t('copy'), Colors.teal,
                                                        () {
                                                          Clipboard.setData(ClipboardData(
                                                              text: '${note['title'] ?? ''}\n\n${note['content'] ?? ''}'));
                                                          showSnack(context, t('copied_to_clipboard_message'));
                                                        }),
                                                    _noteMenuItem(Icons.share_rounded, t('share'), Colors.indigo,
                                                        () => Share.share('${note['title'] ?? ''}\n\n${note['content'] ?? ''}')),
                                                    _noteMenuItem(Icons.copy_all_rounded, t('duplicate'), Colors.orange,
                                                        () => Future.delayed(Duration.zero, () async {
                                                          final res = await ApiClient.post('/api/notes', body: {
                                                            'title': '${note['title']} (copy)',
                                                            'content': note['content'],
                                                          });
                                                          if (res.statusCode == 201) {
                                                            final newNote = json.decode(res.body)['note'];
                                                            setState(() { notes.insert(0, newNote); filterNotes(searchQuery); });
                                                          }
                                                        })),
                                                    _noteMenuItem(Icons.delete_rounded, t('delete_note'), Colors.red,
                                                        () => Future.delayed(Duration.zero, () => deleteNote(note['_id']))),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Icon(Icons.calendar_today,
                                                    size: 12,
                                                    color: AppThemeColors.mutedText(context)),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${t('created')}: ${_formatDate(note['createdAt'])}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppThemeColors.mutedText(context),
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Icon(Icons.update,
                                                    size: 12,
                                                    color: AppThemeColors.mutedText(context)),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${t('updated')}: ${_formatDate(note['updatedAt'])}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppThemeColors.mutedText(context),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              note['content'] ?? '',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: AppThemeColors.secondaryText(context),
                                                height: 1.4,
                                              ),
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
          ],
        ),
      ),
      ],
    ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.orange, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () => createOrEditNote(),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: const Icon(Icons.add, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Color _getNoteColor(int index, BuildContext context) {
    final isDark = AppThemeColors.isDark(context);
    final colors = isDark
        ? [
            const Color(0xFF2C2418), // Dark cream
            const Color(0xFF192519), // Dark green
            const Color(0xFF2A1A1E), // Dark pink
            const Color(0xFF161E2C), // Dark blue
            const Color(0xFF26240E), // Dark yellow
            const Color(0xFF221628), // Dark purple
          ]
        : [
            const Color(0xFFFFF4E6), // Cream
            const Color(0xFFE8F5E9), // Light green
            const Color(0xFFFCE4EC), // Light pink
            const Color(0xFFE3F2FD), // Light blue
            const Color(0xFFFFF9C4), // Light yellow
            const Color(0xFFF3E5F5), // Light purple
          ];
    return colors[index % colors.length];
  }
}
