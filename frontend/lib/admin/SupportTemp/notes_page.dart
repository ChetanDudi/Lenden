import 'package:flutter/material.dart';
import 'dart:convert';
import '../../api_config.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

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
              (note['title'] ?? '').toLowerCase().contains(query.toLowerCase()))
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
          error = 'Failed to load notes';
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = 'Failed to load notes';
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
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
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
                      isEdit ? 'Edit Note' : 'New Note',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextField(
                      controller: titleController,
                      style: TextStyle(color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Title',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[100],
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.black87),
                        ),
                        counterStyle: TextStyle(color: Colors.grey[600]),
                      ),
                      maxLength: 50,
                    ),
                  ),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: TextField(
                      controller: contentController,
                      style: TextStyle(color: Colors.black87),
                      maxLines: 5,
                      decoration: InputDecoration(
                        hintText: 'Enter note...',
                        hintStyle: TextStyle(color: Colors.grey[400]),
                        filled: true,
                        fillColor: Colors.grey[100],
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.black87),
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
                          child: Text('Cancel',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16)),
                        ),
                        SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
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
                            isEdit ? 'Update' : 'Create',
                            style: TextStyle(
                                color: Colors.white,
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
      final session = Provider.of<SessionProvider>(context, listen: false);
      final token = session.token;
      if (isEdit) {
        final url = '${ApiConfig.baseUrl}/api/notes/${note!['_id']}';
        final res = await ApiClient.put(
          '/api/notes/${note!['_id']}',
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
        final url = '${ApiConfig.baseUrl}/api/notes';
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, color: Colors.red, size: 24),
            ),
            SizedBox(width: 12),
            Text('Delete Note',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this note? This action cannot be undone.',
          style: TextStyle(fontSize: 15, color: Colors.grey[700]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text('Cancel',
                style: TextStyle(
                    color: Colors.grey[600],
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
            child: Text('Delete',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final token = session.token;
      final url = '${ApiConfig.baseUrl}/api/notes/$id';
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
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
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
                color: Colors.grey[300],
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.sort, color: Colors.blue, size: 20),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Sort By',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
            _buildSortOption(
                'created_desc', 'Newest First', Icons.new_releases),
            _buildSortOption('created_asc', 'Oldest First', Icons.access_time),
            _buildSortOption('updated_desc', 'Recently Updated', Icons.update),
            _buildSortOption('updated_asc', 'Least Updated', Icons.history),
            _buildSortOption('title_az', 'Title A-Z', Icons.sort_by_alpha),
            _buildSortOption('title_za', 'Title Z-A', Icons.sort_by_alpha),
            SizedBox(height: 20),
          ],
        ),
      ),
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
              isSelected ? Colors.blue.withOpacity(0.05) : Colors.transparent,
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
              color: isSelected ? Colors.blue : Colors.grey[600],
              size: 20,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  color: isSelected ? Colors.blue : Colors.grey[800],
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
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                          context, '/admin/dashboard');
                    },
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Admin Notes',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 48), // Balance the back button
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
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[400], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          onChanged: filterNotes,
                          decoration: InputDecoration(
                            hintText: 'Search notes...',
                            hintStyle: TextStyle(
                                color: Colors.grey[400], fontSize: 15),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      if (searchQuery.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.clear,
                              color: Colors.grey[400], size: 20),
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
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.filter_list,
                                color: Colors.black87, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Sort',
                              style: TextStyle(
                                color: Colors.black87,
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
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.black87))
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
                                      size: 64, color: Colors.grey[300]),
                                  SizedBox(height: 16),
                                  Text(
                                    'No notes yet',
                                    style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Tap + to create your first note',
                                    style: TextStyle(
                                        color: Colors.grey[400], fontSize: 14),
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
                                          color: Colors.black.withOpacity(0.08),
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
                                                        '(No Title)',
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
                                                          .withOpacity(0.05),
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
                                                                    .withOpacity(
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
                                                              'Edit Note',
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: Colors
                                                                    .black87,
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
                                                                    .withOpacity(
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
                                                              'Delete Note',
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
                                                  'Created: ${_formatDate(note['createdAt'])}',
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
                                                  'Updated: ${_formatDate(note['updatedAt'])}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            SingleChildScrollView(
                                              scrollDirection: Axis.vertical,
                                              child: SingleChildScrollView(
                                                scrollDirection:
                                                    Axis.horizontal,
                                                child: Text(
                                                  note['content'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[700],
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
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
              color: Colors.black.withOpacity(0.2),
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
