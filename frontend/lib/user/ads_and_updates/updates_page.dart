import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';

class UserUpdatesPage extends StatefulWidget {
  const UserUpdatesPage({super.key});

  @override
  State<UserUpdatesPage> createState() => _UserUpdatesPageState();
}

class _UserUpdatesPageState extends State<UserUpdatesPage> {
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  String _filter = 'all';
  List<Map<String, dynamic>> _updates = [];

  List<Map<String, dynamic>> get _filteredUpdates {
    final query = _searchController.text.trim().toLowerCase();
    return _updates.where((update) {
      if (_filter == 'unread' && update['isRead'] == true) return false;
      if (_filter == 'critical' && update['importance'] != 'critical') return false;
      if (_filter == 'feature' && update['category'] != 'feature') return false;
      if (_filter == 'security' && update['category'] != 'security') return false;

      if (query.isEmpty) return true;
      final haystack = [
        update['title'],
        update['summary'],
        update['body'],
        update['versionTag'],
        (update['tags'] as List?)?.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  int get _unreadCount =>
      _updates.where((update) => update['isRead'] != true).length;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _loadUpdates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _loadUpdates() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await ApiClient.get('/api/app-updates');
      final data = _decodeJson(res.body);
      if (res.statusCode != 200) {
        throw Exception((data['error'] ?? 'Failed to load updates').toString());
      }
      setState(() {
        _updates = List<Map<String, dynamic>>.from(
          (data['updates'] ?? []).map((e) => Map<String, dynamic>.from(e)),
        );
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(Map<String, dynamic> update) async {
    final updateId = update['_id']?.toString();
    if (updateId == null || updateId.isEmpty || update['isRead'] == true) return;

    try {
      await ApiClient.post('/api/app-updates/$updateId/read');
      if (!mounted) return;
      setState(() {
        update['isRead'] = true;
        update['readAt'] = DateTime.now().toIso8601String();
      });
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await ApiClient.post('/api/app-updates/read-all');
      if (!mounted) return;
      setState(() {
        final now = DateTime.now().toIso8601String();
        for (final update in _updates) {
          update['isRead'] = true;
          update['readAt'] = now;
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'App Updates',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadUpdates,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _unreadCount == 0 ? null : _markAllRead,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Mark All Read'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _buildSearchCard(),
                  const SizedBox(height: 12),
                  _buildFilterRow(),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
                      ),
                    )
                  else if (_error != null)
                    _buildStateCard(_error!, Colors.redAccent)
                  else if (_filteredUpdates.isEmpty)
                    _buildStateCard('No updates matched this filter.', Colors.black54)
                  else
                    ..._filteredUpdates.map(_buildUpdateCard),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What\'s New',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Unread updates: $_unreadCount',
            style: const TextStyle(
              color: Color(0xFF0077B6),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Stay updated with features, bug fixes, security notices, and important announcements from the admin team.',
            style: TextStyle(height: 1.45, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search updates, tags, or version',
          filled: true,
          fillColor: Colors.white,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildFilterChip('all', 'All'),
        _buildFilterChip('unread', 'Unread'),
        _buildFilterChip('critical', 'Critical'),
        _buildFilterChip('feature', 'Features'),
        _buildFilterChip('security', 'Security'),
      ],
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: const Color(0xFFEAF5FF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0077B6) : Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildStateCard(String message, Color color) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final pinned = update['pinned'] == true;
    final isRead = update['isRead'] == true;
    final tags = ((update['tags'] as List?) ?? const [])
        .map((tag) => tag.toString())
        .where((tag) => tag.trim().isNotEmpty)
        .toList();

    return GestureDetector(
      onTap: () => _markRead(update),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Colors.orange, Colors.white, Colors.green],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (update['title'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (pinned) _pill('Pinned', const Color(0xFF0E5A8A)),
                  if (!isRead) ...[
                    const SizedBox(width: 8),
                    _pill('Unread', Colors.redAccent),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _infoTag((update['category'] ?? 'general').toString()),
                  _infoTag((update['importance'] ?? 'normal').toString()),
                  if ((update['versionTag'] ?? '').toString().trim().isNotEmpty)
                    _infoTag('v${update['versionTag']}'),
                ],
              ),
              if ((update['summary'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  (update['summary'] ?? '').toString(),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                (update['body'] ?? '').toString(),
                style: const TextStyle(height: 1.45, color: Colors.black87),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tags.map((tag) => _tagChip('#$tag')).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDate(update['publishedAt']),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!isRead)
                    TextButton(
                      onPressed: () => _markRead(update),
                      child: const Text('Mark Read'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _infoTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0077B6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _tagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return 'Unknown date';
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
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class TopWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.4);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.5,
      size.width * 0.5,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.3,
      size.width,
      size.height * 0.4,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
