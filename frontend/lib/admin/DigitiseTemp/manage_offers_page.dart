import 'dart:convert';
import 'package:flutter/material.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';

class ManageOffersPage extends StatefulWidget {
  const ManageOffersPage({super.key});

  @override
  State<ManageOffersPage> createState() => _ManageOffersPageState();
}

class _ManageOffersPageState extends State<ManageOffersPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _offers = [];
  bool _loading = true;
  bool _submitting = false;

  String _statusFilter = 'all';
  String _sortBy = 'createdAt';
  String _order = 'desc';
  int _page = 1;
  int _limit = 20;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _fetchOffers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showStylishMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isError ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle,
                  color: isError ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _errorFromBody(String body, {String fallback = 'Request failed'}) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded['error'];
      if (error != null && error.toString().trim().isNotEmpty) {
        return error.toString();
      }
    } catch (_) {}
    return fallback;
  }

  String _fmtDate(dynamic v) {
    final d = DateTime.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d.toLocal().toString().substring(0, 16);
  }

  Widget _buildOverviewChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF0077B5),
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'scheduled':
        return Colors.orange;
      case 'active':
        return Colors.green;
      case 'ended':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> _fetchOffers() async {
    setState(() => _loading = true);
    final qp = <String>[
      'page=$_page',
      'limit=$_limit',
      'sortBy=$_sortBy',
      'order=$_order',
    ];
    final search = _searchController.text.trim();
    if (search.isNotEmpty) qp.add('search=${Uri.encodeQueryComponent(search)}');
    if (_statusFilter != 'all') qp.add('status=$_statusFilter');

    final res = await ApiClient.get('/api/admin/offers?${qp.join('&')}');
    if (!mounted) return;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final pagination = (data['pagination'] ?? {}) as Map<String, dynamic>;
      setState(() {
        _offers = List<dynamic>.from(data['items'] ?? []);
        _page = (pagination['page'] ?? _page) as int;
        _limit = (pagination['limit'] ?? _limit) as int;
        _totalPages = (pagination['totalPages'] ?? 1) as int;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = false);
    _showStylishMessage(
      _errorFromBody(res.body, fallback: 'Failed to fetch offers'),
      isError: true,
    );
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final res = await ApiClient.get('/api/admin/offers/users?search=$q&limit=20');
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['users'] ?? []);
  }

  Future<void> _deleteOffer(String offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Offer'),
        content: const Text('This will permanently delete the offer and claims. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final res = await ApiClient.delete('/api/admin/offers/$offerId');
    if (!mounted) return;
    if (res.statusCode == 200) {
      _showStylishMessage('Offer deleted successfully');
      await _fetchOffers();
      return;
    }
    _showStylishMessage(
      _errorFromBody(res.body, fallback: 'Failed to delete offer'),
      isError: true,
    );
  }

  Future<void> _openAnalytics(String offerId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final res = await ApiClient.get('/api/admin/offers/$offerId/analytics');
    if (!mounted) return;
    Navigator.of(context).pop();

    if (res.statusCode != 200) {
      _showStylishMessage(
        _errorFromBody(res.body, fallback: 'Failed to load analytics'),
        isError: true,
      );
      return;
    }

    final data = jsonDecode(res.body);
    final offer = (data['offer'] ?? {}) as Map<String, dynamic>;
    final metrics = (data['metrics'] ?? {}) as Map<String, dynamic>;
    final users = List<dynamic>.from(data['acceptedUsers'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
            ),
            child: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Analytics: ${offer['name'] ?? 'Offer'} (v${offer['version'] ?? 1})',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricChip('Targeted', '${metrics['targetedCount'] ?? 0}'),
                      _metricChip('Accepted', '${metrics['acceptedCount'] ?? 0}'),
                      _metricChip('Pending', '${metrics['pendingCount'] ?? 0}'),
                      _metricChip('Rate', '${metrics['acceptanceRate'] ?? 0}%'),
                      _metricChip('Coins', '${metrics['distributedCoins'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Accepted users (${users.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: users.isEmpty
                        ? const Center(child: Text('No accepted users yet.'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final row = (users[index] ?? {}) as Map<String, dynamic>;
                              final u = (row['user'] ?? {}) as Map<String, dynamic>;
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person),
                                title: Text((u['name'] ?? u['username'] ?? '-').toString()),
                                subtitle: Text((u['email'] ?? '-').toString()),
                                trailing: Text('+${row['coinsAwarded'] ?? 0}'),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openClaimsAudit(String offerId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final res = await ApiClient.get('/api/admin/offers/$offerId/claims?includeRevoked=true&limit=100');
    if (!mounted) return;
    Navigator.of(context).pop();

    if (res.statusCode != 200) {
      _showStylishMessage(
        _errorFromBody(res.body, fallback: 'Failed to load claims audit'),
        isError: true,
      );
      return;
    }
    final data = jsonDecode(res.body);
    final offer = (data['offer'] ?? {}) as Map<String, dynamic>;
    final items = List<dynamic>.from(data['items'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(14),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white,
            ),
            child: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Claims Audit: ${offer['name'] ?? 'Offer'}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: items.isEmpty
                        ? const Center(child: Text('No claims found.'))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = (items[index] ?? {}) as Map<String, dynamic>;
                              final user = (item['user'] ?? {}) as Map<String, dynamic>;
                              final revoked = item['revoked'] == true;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: revoked
                                      ? const Color(0xFFFFEBEE)
                                      : const Color(0xFFE8F5E9),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.receipt_long),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (user['name'] ?? user['username'] ?? '-').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          Text((user['email'] ?? '-').toString()),
                                          Text('Version: v${item['offerVersion'] ?? '-'}'),
                                          Text('Claimed: ${_fmtDate(item['claimedAt'])}'),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('+${item['coinsAwarded'] ?? 0}'),
                                        const SizedBox(height: 4),
                                        Chip(
                                          label: Text(revoked ? 'Revoked' : 'Active'),
                                          backgroundColor: revoked
                                              ? Colors.red.withValues(alpha: 0.12)
                                              : Colors.green.withValues(alpha: 0.12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFE3F2FD),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _openOfferDialog({Map<String, dynamic>? existing}) async {
    final bool isEdit = existing != null;

    final nameController = TextEditingController(text: existing?['name']?.toString() ?? '');
    final descriptionController =
        TextEditingController(text: existing?['description']?.toString() ?? '');
    final coinsController =
        TextEditingController(text: (existing?['coins'] ?? '').toString());
    final reasonController = TextEditingController(text: 'Offer updated');
    final emailController = TextEditingController();
    final userSearchController = TextEditingController();

    DateTime? startsAt = existing?['startsAt'] != null
        ? DateTime.tryParse(existing!['startsAt'].toString())?.toLocal()
        : DateTime.now().add(const Duration(minutes: 5));
    DateTime? endsAt = existing?['endsAt'] != null
        ? DateTime.tryParse(existing!['endsAt'].toString())?.toLocal()
        : DateTime.now().add(const Duration(days: 1));
    String status = (existing?['status'] ?? 'active').toString();
    bool isActive = (existing?['isActive'] ?? true) == true;
    String recipientType = (existing?['recipientType'] ?? 'all-users').toString();

    final List<Map<String, dynamic>> selectedUsers = List<Map<String, dynamic>>.from(
      (existing?['recipients'] ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    List<Map<String, dynamic>> searchResults = [];
    List<String> formErrors = [];

    Future<void> pickDateTime(bool start, StateSetter setDialogState) async {
      final current = (start ? startsAt : endsAt) ?? DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: DateTime(2024),
        lastDate: DateTime(2100),
      );
      if (date == null) return;
      if (!mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(current),
      );
      if (time == null) return;

      final composed = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      setDialogState(() {
        formErrors = [];
        if (start) {
          startsAt = composed;
        } else {
          endsAt = composed;
        }
      });
    }

    Future<void> searchUsers(StateSetter setDialogState) async {
      final q = userSearchController.text.trim();
      final users = await _searchUsers(q);
      setDialogState(() {
        formErrors = [];
        searchResults = users;
      });
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(14),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [Colors.orange, Colors.white, Colors.green],
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: SizedBox(
                    width: 640,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEdit ? 'Update Offer' : 'Add Offer',
                            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                          ),
                          if (formErrors.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.error_outline, color: Colors.red),
                                      SizedBox(width: 6),
                                      Text(
                                        'Please fix these errors:',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ...formErrors.map(
                                    (e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: Text('• $e'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          _sectionBox(
                            title: 'Offer Basics',
                            color: const Color(0xFFE3F2FD),
                            child: Column(
                              children: [
                                TextField(
                                  controller: nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Offer Name',
                                    prefixIcon: Icon(Icons.local_offer),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: descriptionController,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Description',
                                    prefixIcon: Icon(Icons.description),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _sectionBox(
                            title: 'Reward and Status',
                            color: const Color(0xFFE8F5E9),
                            child: Column(
                              children: [
                                TextField(
                                  controller: coinsController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Coins Value',
                                    prefixIcon: Icon(Icons.monetization_on),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: status,
                                        decoration: const InputDecoration(
                                          labelText: 'Status',
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'draft', child: Text('Draft')),
                                          DropdownMenuItem(
                                              value: 'scheduled', child: Text('Scheduled')),
                                          DropdownMenuItem(
                                              value: 'active', child: Text('Active')),
                                          DropdownMenuItem(
                                              value: 'ended', child: Text('Ended')),
                                        ],
                                        onChanged: (v) =>
                                            setDialogState(() => status = v ?? 'active'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SwitchListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                                        title: const Text('Enabled'),
                                        value: isActive,
                                        onChanged: (v) => setDialogState(() => isActive = v),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _sectionBox(
                            title: 'Timeline',
                            color: const Color(0xFFFFF3E0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _boxedTimelineTile(
                                    label: 'Starts At',
                                    value: startsAt == null ? '-' : _fmtDate(startsAt),
                                    onTap: () => pickDateTime(true, setDialogState),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _boxedTimelineTile(
                                    label: 'Ends At',
                                    value: endsAt == null ? '-' : _fmtDate(endsAt),
                                    onTap: () => pickDateTime(false, setDialogState),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _sectionBox(
                            title: 'Recipients',
                            color: const Color(0xFFFFF8E1),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  value: recipientType,
                                  decoration: const InputDecoration(
                                    labelText: 'Recipient Type',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all-users',
                                      child: Text('All Users'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'specific-users',
                                      child: Text('Specific Users'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    setDialogState(() {
                                      recipientType = v ?? 'all-users';
                                      if (recipientType == 'all-users') {
                                        selectedUsers.clear();
                                        searchResults = [];
                                        userSearchController.clear();
                                        emailController.clear();
                                      }
                                    });
                                  },
                                ),
                                if (recipientType == 'specific-users') ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: userSearchController,
                                          decoration: const InputDecoration(
                                            labelText: 'Search by name/username/email',
                                            prefixIcon: Icon(Icons.search),
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => searchUsers(setDialogState),
                                        icon: const Icon(Icons.person_search),
                                        label: const Text('Find'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFB3E5FC)),
                                    ),
                                    child: searchResults.isEmpty
                                        ? const Text('No searched users yet.')
                                        : Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: searchResults.map((u) {
                                              final id = (u['_id'] ?? '').toString();
                                              final already = selectedUsers
                                                  .any((e) => e['_id'].toString() == id);
                                              return FilterChip(
                                                selected: already,
                                                label: Text(
                                                  '${u['name'] ?? u['username'] ?? ''} (${u['email'] ?? ''})',
                                                ),
                                                onSelected: (_) {
                                                  setDialogState(() {
                                                    if (already) {
                                                      selectedUsers.removeWhere((e) =>
                                                          e['_id'].toString() == id);
                                                    } else {
                                                      selectedUsers.add(u);
                                                    }
                                                  });
                                                },
                                              );
                                            }).toList(),
                                          ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: emailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Extra recipient emails (comma-separated)',
                                      prefixIcon: Icon(Icons.email),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (selectedUsers.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFA5D6A7)),
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: selectedUsers.map((u) {
                                          final id = (u['_id'] ?? '').toString();
                                          return Chip(
                                            label: Text(
                                              '${u['name'] ?? u['username'] ?? ''}',
                                            ),
                                            deleteIcon: const Icon(Icons.close),
                                            onDeleted: () => setDialogState(() {
                                              selectedUsers.removeWhere(
                                                  (e) => e['_id'].toString() == id);
                                            }),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                          if (isEdit) ...[
                            const SizedBox(height: 10),
                            _sectionBox(
                              title: 'Update Metadata',
                              color: const Color(0xFFF3E5F5),
                              child: TextField(
                                controller: reasonController,
                                decoration: const InputDecoration(
                                  labelText: 'Update Reason',
                                  prefixIcon: Icon(Icons.history_toggle_off),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _submitting ? null : () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _submitting
                                    ? null
                                    : () async {
                                        final name = nameController.text.trim();
                                        final coins = int.tryParse(coinsController.text.trim());
                                        final errors = <String>[];
                                        if (name.isEmpty) {
                                          errors.add('Offer name is required.');
                                        }
                                        if (coins == null) {
                                          errors.add('Coins must be a valid number.');
                                        } else {
                                          if (coins <= 0) {
                                            errors.add('Coins must be greater than 0.');
                                          }
                                          if (coins > 10000) {
                                            errors.add('Coins cannot be more than 10000.');
                                          }
                                        }
                                        if (startsAt == null) {
                                          errors.add('Start date and time are required.');
                                        }
                                        if (endsAt == null) {
                                          errors.add('End date and time are required.');
                                        }

                                        if (startsAt != null && endsAt != null) {
                                          final startDateOnly = DateTime(
                                            startsAt!.year,
                                            startsAt!.month,
                                            startsAt!.day,
                                          );
                                          final endDateOnly = DateTime(
                                            endsAt!.year,
                                            endsAt!.month,
                                            endsAt!.day,
                                          );

                                          if (endDateOnly.isBefore(startDateOnly)) {
                                            errors.add(
                                              'End date must be same as or after start date.',
                                            );
                                          } else if (endDateOnly == startDateOnly &&
                                              !endsAt!.isAfter(startsAt!)) {
                                            errors.add(
                                              'For the same date, end time must be later than start time.',
                                            );
                                          } else if (!endsAt!.isAfter(startsAt!)) {
                                            errors.add(
                                              'End date/time must be later than start date/time.',
                                            );
                                          }
                                        }

                                        if (recipientType == 'specific-users' &&
                                            selectedUsers.isEmpty &&
                                            emailController.text.trim().isEmpty) {
                                          errors.add(
                                            'For specific users, select at least one user or add recipient email.',
                                          );
                                        }

                                        if (errors.isNotEmpty) {
                                          setDialogState(() => formErrors = errors);
                                          _scrollController.animateTo(
                                            0,
                                            duration: const Duration(milliseconds: 250),
                                            curve: Curves.easeOut,
                                          );
                                          return;
                                        }
                                        setDialogState(() => formErrors = []);

                                        final recipientUserIds = selectedUsers
                                            .map((e) => e['_id'].toString())
                                            .where((e) => e.isNotEmpty)
                                            .toList();
                                        final recipientEmails = emailController.text
                                            .split(',')
                                            .map((e) => e.trim())
                                            .where((e) => e.isNotEmpty)
                                            .toList();

                                        final payload = <String, dynamic>{
                                          'name': name,
                                          'description': descriptionController.text.trim(),
                                          'coins': coins,
                                          'startsAt': startsAt!.toUtc().toIso8601String(),
                                          'endsAt': endsAt!.toUtc().toIso8601String(),
                                          'status': status,
                                          'isActive': isActive,
                                          'recipientType': recipientType,
                                          'recipientUserIds': recipientUserIds,
                                          'recipientEmails': recipientEmails,
                                          if (isEdit)
                                            'updateReason': reasonController.text.trim().isEmpty
                                                ? 'Offer updated'
                                                : reasonController.text.trim(),
                                        };

                                        setState(() => _submitting = true);
                                        final res = isEdit
                                            ? await ApiClient.put(
                                                '/api/admin/offers/${existing['_id']}',
                                                body: payload,
                                              )
                                            : await ApiClient.post(
                                                '/api/admin/offers',
                                                body: payload,
                                              );
                                        if (!mounted) return;
                                        setState(() => _submitting = false);

                                        if (res.statusCode == 200 || res.statusCode == 201) {
                                          Navigator.pop(ctx);
                                          if (isEdit) {
                                            final body = jsonDecode(res.body);
                                            final rb = (body['rollbackSummary'] ?? {})
                                                as Map<String, dynamic>;
                                            _showStylishMessage(
                                              'Offer updated. Reverted ${rb['revertedClaims'] ?? 0} claims and ${rb['revertedCoins'] ?? 0} coins for re-accept.',
                                            );
                                          } else {
                                            _showStylishMessage('Offer created successfully');
                                          }
                                          await _fetchOffers();
                                          return;
                                        }

                                        _showStylishMessage(
                                          _errorFromBody(
                                            res.body,
                                            fallback: isEdit
                                                ? 'Failed to update offer'
                                                : 'Failed to create offer',
                                          ),
                                          isError: true,
                                        );
                                      },
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.save),
                                label: Text(isEdit ? 'Update Offer' : 'Create Offer'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionBox({
    required String title,
    required Widget child,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _boxedTimelineTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFB3E5FC)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.event, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Colors.orange, Colors.white, Colors.green],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search offers...',
                  isDense: true,
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  _page = 1;
                  _fetchOffers();
                },
              ),
            ),
            DropdownButton<String>(
              value: _statusFilter,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(value: 'ended', child: Text('Ended')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _statusFilter = v;
                  _page = 1;
                });
                _fetchOffers();
              },
            ),
            DropdownButton<String>(
              value: _sortBy,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'createdAt', child: Text('Newest')),
                DropdownMenuItem(value: 'coins', child: Text('Coins')),
                DropdownMenuItem(value: 'endsAt', child: Text('Deadline')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _sortBy = v;
                  _page = 1;
                });
                _fetchOffers();
              },
            ),
            DropdownButton<String>(
              value: _order,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'desc', child: Text('Desc')),
                DropdownMenuItem(value: 'asc', child: Text('Asc')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _order = v;
                  _page = 1;
                });
                _fetchOffers();
              },
            ),
            ElevatedButton.icon(
              onPressed: _fetchOffers,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            ElevatedButton.icon(
              onPressed: () => _openOfferDialog(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B4D8)),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Add Offer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_offers.isEmpty) return const Center(child: Text('No offers found.'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _offers.length,
      itemBuilder: (context, index) {
        final offer = (_offers[index] ?? {}) as Map<String, dynamic>;
        final analytics = (offer['analytics'] ?? {}) as Map<String, dynamic>;
        final status = (offer['status'] ?? '-').toString();
        final statusColor = _statusColor(status);
        final recipientType = (offer['recipientType'] ?? 'all-users').toString();
        final targeted = analytics['targetedCount'];
        final background = index.isEven ? const Color(0xFFFFF8E1) : const Color(0xFFE3F2FD);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Colors.orange, Colors.white, Colors.green],
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (offer['name'] ?? 'Offer').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                    Chip(
                      label: Text(status.toUpperCase()),
                      backgroundColor: statusColor.withValues(alpha: 0.15),
                      labelStyle: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if ((offer['description'] ?? '').toString().trim().isNotEmpty)
                  Text((offer['description'] ?? '').toString()),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text('Coins: +${offer['coins'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('Version: v${offer['version'] ?? 1}'),
                    Text('Starts: ${_fmtDate(offer['startsAt'])}'),
                    Text('Ends: ${_fmtDate(offer['endsAt'])}'),
                    Text('Recipients: ${recipientType == 'all-users' ? 'All Users' : 'Specific'}'
                        '${targeted != null ? ' ($targeted)' : ''}'),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip('Accepted', '${analytics['acceptedCount'] ?? 0}'),
                    _metricChip('Coins Dist.', '${analytics['distributedCoins'] ?? 0}'),
                    _metricChip('Rate', '${analytics['acceptanceRate'] ?? '-'}%'),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _openOfferDialog(existing: offer),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openAnalytics(offer['_id'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00B4D8)),
                      icon: const Icon(Icons.analytics, color: Colors.white),
                      label:
                          const Text('Analytics', style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _openClaimsAudit(offer['_id'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                      icon: const Icon(Icons.fact_check, color: Colors.white),
                      label: const Text('Claims Audit',
                          style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _deleteOffer(offer['_id'].toString()),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      icon: const Icon(Icons.delete, color: Colors.white),
                      label: const Text('Delete', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPagination() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _page <= 1
                ? null
                : () {
                    setState(() => _page -= 1);
                    _fetchOffers();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page $_page / $_totalPages'),
          IconButton(
            onPressed: _page >= _totalPages
                ? null
                : () {
                    setState(() => _page += 1);
                    _fetchOffers();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F6),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: 140,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Manage Offers',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                _buildFilterBar(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildOverviewChip('Loaded', '${_offers.length}'),
                      _buildOverviewChip(
                        'Active',
                        '${_offers.where((offer) => (offer['status'] ?? '') == 'active').length}',
                      ),
                      _buildOverviewChip(
                        'Scheduled',
                        '${_offers.where((offer) => (offer['status'] ?? '') == 'scheduled').length}',
                      ),
                      _buildOverviewChip(
                        'Coins',
                        '${_offers.fold<num>(0, (sum, offer) => sum + ((offer['analytics']?['distributedCoins'] ?? 0) as num))}',
                      ),
                    ],
                  ),
                ),
                Expanded(child: RefreshIndicator(onRefresh: _fetchOffers, child: _buildOfferList())),
                _buildPagination(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


