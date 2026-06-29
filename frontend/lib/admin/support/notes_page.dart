import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

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

  @override
  void initState() {
    super.initState();
    fetchNotes();
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
    final titleController = TextEditingController(text: note?['title'] ?? '');
    final contentController =
        TextEditingController(text: note?['content'] ?? '');
    final isEdit = note != null;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) {
        final t = AppLocalizations.of(context).t;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: AppThemeColors.cardBg(context),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Text(
                      isEdit ? t('edit_note') : t('new_note'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextField(
                      controller: titleController,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      decoration: InputDecoration(
                        hintText: t('title'),
                        hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                        filled: true,
                        fillColor: AppThemeColors.surfaceBg(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppThemeColors.border(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppThemeColors.primaryText(context)),
                        ),
                        counterStyle: TextStyle(color: AppThemeColors.secondaryText(context)),
                      ),
                      maxLength: 50,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextField(
                      controller: contentController,
                      style: TextStyle(color: AppThemeColors.primaryText(context)),
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: t('enter_note'),
                        hintStyle: TextStyle(color: AppThemeColors.mutedText(context)),
                        filled: true,
                        fillColor: AppThemeColors.surfaceBg(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppThemeColors.border(context)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppThemeColors.primaryText(context)),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(t('cancel'),
                              style: TextStyle(
                                  color: AppThemeColors.secondaryText(context), fontSize: 16)),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppThemeColors.primaryText(context),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                          onPressed: () {
                            final title = titleController.text.trim();
                            final content = contentController.text.trim();
                            if (title.isEmpty || content.isEmpty) return;
                            Navigator.pop(
                                context, {'title': title, 'content': content});
                          },
                          child: Text(
                            isEdit ? t('update') : t('create'),
                            style: TextStyle(
                                color: AppThemeColors.cardBg(context),
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (result != null &&
        result['title']!.isNotEmpty &&
        result['content']!.isNotEmpty) {
      if (isEdit) {
        final res = await ApiClient.put(
          '/api/notes/${note['_id']}',
          body: {'title': result['title'], 'content': result['content']},
        );
        if (res.statusCode == 200) {
          final updatedNote = Map<String, dynamic>.from(note);
          updatedNote['title'] = result['title'];
          updatedNote['content'] = result['content'];
          updatedNote['updatedAt'] = DateTime.now().toIso8601String();

          setState(() {
            final index = notes.indexWhere((n) => n['_id'] == note['_id']);
            if (index != -1) {
              notes[index] = updatedNote;
              filterNotes(searchQuery);
            }
          });
        }
      } else {
        final res = await ApiClient.post(
          '/api/notes',
          body: {'title': result['title'], 'content': result['content']},
        );
        if (res.statusCode == 201) {
          final newNote = json.decode(res.body)['note'];
          setState(() {
            notes.insert(0, newNote);
            filterNotes(searchQuery);
          });
        }
      }
    }
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
                  SizedBox(width: 48),
                ],
              ),
            ),

            // Search Bar with Tricolor Border
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(27),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: AppThemeColors.mutedText(context), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          onChanged: filterNotes,
                          decoration: InputDecoration(
                            hintText: t('search_notes'),
                            hintStyle: TextStyle(
                                color: AppThemeColors.mutedText(context), fontSize: 15),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          style: TextStyle(fontSize: 15, color: AppThemeColors.primaryText(context)),
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear,
                              color: AppThemeColors.mutedText(context), size: 20),
                          onPressed: () => filterNotes(''),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ),
              ),
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
                      ? Center(
                          child: Text(error!,
                              style: const TextStyle(color: Colors.red)))
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
                                        color: _getNoteColor(i),
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
                                                    style: const TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
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
                                                        color: Colors.grey[700],
                                                        size: 20),
                                                  ),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16)),
                                                  elevation: 8,
                                                  offset: Offset(0, 8),
                                                  itemBuilder: (context) => [
                                                    PopupMenuItem(
                                                      child: Container(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                vertical: 4),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(8),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .blue
                                                                    .withValues(alpha: 
                                                                        0.1),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              child: Icon(
                                                                  Icons.edit,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .blue),
                                                            ),
                                                            SizedBox(width: 12),
                                                            Text(
                                                              t('edit_note'),
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: AppThemeColors
                                                                    .primaryText(context),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Future.delayed(
                                                            Duration.zero,
                                                            () =>
                                                                createOrEditNote(
                                                                    note:
                                                                        note));
                                                      },
                                                    ),
                                                    PopupMenuItem(
                                                      child: Container(
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                vertical: 4),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(8),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .red
                                                                    .withValues(alpha: 
                                                                        0.1),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            8),
                                                              ),
                                                              child: Icon(
                                                                  Icons.delete,
                                                                  size: 18,
                                                                  color: Colors
                                                                      .red),
                                                            ),
                                                            SizedBox(width: 12),
                                                            Text(
                                                              t('delete_note'),
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color:
                                                                    Colors.red,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      onTap: () {
                                                        Future.delayed(
                                                            Duration.zero,
                                                            () => deleteNote(
                                                                note['_id']));
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                Icon(Icons.calendar_today,
                                                    size: 12,
                                                    color: Colors.grey[600]),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${t('created')}: ${_formatDate(note['createdAt'])}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Icon(Icons.update,
                                                    size: 12,
                                                    color: Colors.grey[600]),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${t('updated')}: ${_formatDate(note['updatedAt'])}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              note['content'] ?? '',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[700],
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

  Color _getNoteColor(int index) {
    final colors = [
      Color(0xFFFFF4E6), // Cream
      Color(0xFFE8F5E9), // Light green
      Color(0xFFFCE4EC), // Light pink
      Color(0xFFE3F2FD), // Light blue
      Color(0xFFFFF9C4), // Light yellow
      Color(0xFFF3E5F5), // Light purple
    ];
    return colors[index % colors.length];
  }
}
