import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';

class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});

  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

class _AdminRolesPageState extends State<AdminRolesPage>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();

  late final TabController _tabController;
  bool _loading = true;
  bool _submitting = false;
  bool _loadingAuditLogs = false;
  bool _showAll = false;
  String? _error;
  List<Map<String, dynamic>> _admins = [];
  List<Map<String, dynamic>> _auditLogs = [];
  Map<String, dynamic>? _currentAdmin;

  bool get _isCurrentSuperAdmin =>
      _currentAdmin?['isSuperAdmin'] == true ||
      Provider.of<SessionProvider>(context, listen: false)
              .user?['isSuperAdmin'] ==
          true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAdmins();
    _loadAuditLogs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final query = _searchController.text.trim();
      final path = query.isEmpty
          ? '/api/admin/admins'
          : '/api/admin/admins?search=${Uri.encodeQueryComponent(query)}';
      final response = await ApiClient.get(path);
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception((data['message'] ?? 'Failed to load admins').toString());
      }

      setState(() {
        _admins = List<Map<String, dynamic>>.from(
          (data['admins'] ?? []).map((item) => Map<String, dynamic>.from(item)),
        );
        _currentAdmin = data['currentAdmin'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data['currentAdmin'])
            : data['currentAdmin'] is Map
                ? Map<String, dynamic>.from(data['currentAdmin'])
                : null;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _loadingAuditLogs = true);
    try {
      final response = await ApiClient.get('/api/admin/audit-logs');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
          (data['message'] ?? 'Failed to load audit logs').toString(),
        );
      }
      setState(() {
        _auditLogs = List<Map<String, dynamic>>.from(
          (data['logs'] ?? []).map((item) => Map<String, dynamic>.from(item)),
        );
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingAuditLogs = false);
    }
  }

  Future<void> _createAdmin() async {
    if (_nameController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() => _error = 'Fill all admin creation fields first.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.post(
        '/api/admin/admins',
        body: {
          'name': _nameController.text.trim(),
          'username': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'gender': 'Other',
          'permissions': _defaultPermissions(),
        },
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 201) {
        throw Exception(
          (data['message'] ?? 'Failed to create admin').toString(),
        );
      }

      _nameController.clear();
      _usernameController.clear();
      _emailController.clear();
      _passwordController.clear();
      await _loadAdmins();
      await _loadAuditLogs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Admin created successfully.')),
      );
      _tabController.animateTo(1);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _toggleSuperAdmin(
    Map<String, dynamic> admin,
    bool nextValue,
  ) async {
    final response = await ApiClient.patch(
      '/api/admin/admins/${admin['_id']}/superadmin',
      body: {'isSuperAdmin': nextValue},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text((data['message'] ?? 'Failed to update role').toString()),
        ),
      );
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text((data['message'] ?? 'Role updated').toString())),
    );
  }

  Future<void> _togglePermission(
    Map<String, dynamic> admin,
    String permissionKey,
    bool nextValue,
  ) async {
    final permissions = Map<String, dynamic>.from(
      admin['permissions'] is Map ? admin['permissions'] : {},
    );
    permissions[permissionKey] = nextValue;

    final response = await ApiClient.patch(
      '/api/admin/admins/${admin['_id']}/permissions',
      body: {'permissions': permissions},
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (data['message'] ?? 'Failed to update permissions').toString(),
          ),
        ),
      );
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((data['message'] ?? 'Permissions updated').toString()),
      ),
    );
  }

  Future<void> _removeAdmin(Map<String, dynamic> admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Admin'),
        content: Text(
          'Remove ${(admin['email'] ?? '').toString()} from admin access?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final response = await ApiClient.delete('/api/admin/admins/${admin['_id']}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (data['message'] ?? 'Failed to remove admin').toString(),
          ),
        ),
      );
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text((data['message'] ?? 'Admin removed').toString())),
    );
  }

  List<Map<String, dynamic>> get _visibleAdmins =>
      _showAll ? _admins : _admins.take(5).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: _TopWaveClipper(),
              child: Container(
                height: 165,
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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      const Expanded(
                        child: Text(
                          'Admin Roles',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await _loadAdmins();
                          await _loadAuditLogs();
                        },
                        icon: const Icon(Icons.refresh, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                        colors: [Colors.orange, Colors.white, Colors.green],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF00B4D8),
                        unselectedLabelColor: Colors.black54,
                        indicator: BoxDecoration(
                          color: const Color(0xFFEAF5FF),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        tabs: const [
                          Tab(text: 'Create'),
                          Tab(text: 'Roles'),
                          Tab(text: 'Audit'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [_buildCreateCard()],
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAdmins,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildManageHeader(),
                            const SizedBox(height: 12),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00B4D8),
                                  ),
                                ),
                              )
                            else if (_error != null)
                              _buildMessageCard(_error!, true)
                            else if (_visibleAdmins.isEmpty)
                              _buildMessageCard('No admins found.', false)
                            else
                              ..._visibleAdmins.map(_buildAdminCard),
                          ],
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAuditLogs,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildAuditHeader(),
                            const SizedBox(height: 12),
                            if (_loadingAuditLogs)
                              const Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF00B4D8),
                                  ),
                                ),
                              )
                            else if (_auditLogs.isEmpty)
                              _buildMessageCard('No audit logs found.', false)
                            else
                              ..._auditLogs.take(40).map(_buildAuditCard),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateCard() {
    return Container(
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
            const Text(
              'Create Admin',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _createAdmin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00B4D8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_submitting ? 'Creating...' : 'Create Admin'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Role Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _isCurrentSuperAdmin
                ? 'You can promote, demote, edit permissions, and remove admins from here.'
                : 'You can view admins here. Superadmin role actions are restricted.',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _loadAdmins(),
            decoration: InputDecoration(
              hintText: 'Search admins',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _loadAdmins,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(_showAll ? 'Show Latest 5' : 'View All'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Admin Audit Trail',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 8),
          Text(
            'Recent high-signal admin actions are tracked here for accountability and review.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard(Map<String, dynamic> admin) {
    final canToggle = admin['canToggleSuperAdmin'] == true;
    final canRemove = admin['canRemove'] == true;
    final canEditPermissions = admin['canEditPermissions'] == true;
    final permissions = Map<String, dynamic>.from(
      admin['permissions'] is Map ? admin['permissions'] : {},
    );

    return Container(
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
                    (admin['name'] ?? '').toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: admin['isSuperAdmin'] == true
                        ? const Color(0xFFEAF5FF)
                        : const Color(0xFFF4F8FB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    admin['isSuperAdmin'] == true ? 'Superadmin' : 'Admin',
                    style: const TextStyle(
                      color: Color(0xFF00B4D8),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text((admin['email'] ?? '').toString()),
            const SizedBox(height: 4),
            Text(
              'Username: ${(admin['username'] ?? '').toString()}',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: admin['isSuperAdmin'] == true,
              onChanged: canToggle ? (value) => _toggleSuperAdmin(admin, value) : null,
              title: const Text('Superadmin access'),
              subtitle: Text(
                canToggle
                    ? 'Toggle elevated admin control for this account.'
                    : 'Only eligible superadmins can change this access.',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Permissions',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            ..._permissionItems(permissions).map(
              (entry) => SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: entry.value,
                onChanged: canEditPermissions
                    ? (value) => _togglePermission(admin, entry.key, value)
                    : null,
                title: Text(_permissionLabel(entry.key)),
                subtitle: Text(
                  canEditPermissions
                      ? 'Allow this admin to manage ${_permissionLabel(entry.key).toLowerCase()}.'
                      : 'Only eligible superadmins can change permissions.',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canRemove ? () => _removeAdmin(admin) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Admin'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Iterable<MapEntry<String, bool>> _permissionItems(
    Map<String, dynamic> permissions,
  ) {
    const keys = [
      'canManageUsers',
      'canManageTransactions',
      'canManageSupport',
      'canManageContent',
      'canManageDigitise',
      'canManageSettings',
      'canViewAuditLogs',
    ];
    return keys.map((key) => MapEntry(key, permissions[key] != false));
  }

  String _permissionLabel(String key) {
    switch (key) {
      case 'canManageUsers':
        return 'Users';
      case 'canManageTransactions':
        return 'Transactions';
      case 'canManageSupport':
        return 'Support';
      case 'canManageContent':
        return 'Content';
      case 'canManageDigitise':
        return 'Digitise';
      case 'canManageSettings':
        return 'Settings';
      case 'canViewAuditLogs':
        return 'Audit Logs';
      default:
        return key;
    }
  }

  Widget _buildAuditCard(Map<String, dynamic> log) {
    final severity = (log['severity'] ?? 'info').toString();
    final color = severity == 'critical'
        ? Colors.redAccent
        : severity == 'warning'
            ? Colors.orange
            : const Color(0xFF00B4D8);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (log['summary'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(log['adminEmail'] ?? '').toString()} • ${(log['action'] ?? '').toString()}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(log['createdAt']),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(String message, bool isError) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFFFFEBEE) : Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.redAccent : Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Map<String, dynamic> _defaultPermissions() => {
        'canManageUsers': true,
        'canManageTransactions': true,
        'canManageSupport': true,
        'canManageContent': true,
        'canManageDigitise': true,
        'canManageSettings': true,
        'canViewAuditLogs': true,
      };

  String _formatDateTime(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final suffix = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day}/${dt.month}/${dt.year} $hour:$minute $suffix';
    } catch (_) {
      return value?.toString() ?? '';
    }
  }
}

class _TopWaveClipper extends CustomClipper<Path> {
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
