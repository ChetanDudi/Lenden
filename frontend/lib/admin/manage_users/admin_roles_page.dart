import 'dart:convert';
import 'package:flutter/material.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import '../../session.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

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
        throw Exception((data['message'] ?? AppLocalizations.of(context).t('failed_load_admins')).toString());
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
          (data['message'] ?? AppLocalizations.of(context).t('failed_load_audit_logs')).toString(),
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
      setState(() => _error = AppLocalizations.of(context).t('fill_all_admin_creation_fields'));
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
          (data['message'] ?? AppLocalizations.of(context).t('failed_create_admin')).toString(),
        );
      }

      _nameController.clear();
      _usernameController.clear();
      _emailController.clear();
      _passwordController.clear();
      await _loadAdmins();
      await _loadAuditLogs();
      if (!mounted) return;
      showSnack(context, AppLocalizations.of(context).t('admin_created_success'));
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
      showSnack(context, (data['message'] ?? AppLocalizations.of(context).t('failed_update_role')).toString(), isError: true);
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    showSnack(context, (data['message'] ?? AppLocalizations.of(context).t('role_updated')).toString());
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
      showSnack(context, (data['message'] ?? AppLocalizations.of(context).t('failed_to_update_permissions')).toString(), isError: true);
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    showSnack(context, (data['message'] ?? AppLocalizations.of(context).t('permissions_updated_successfully')).toString());
  }

  Future<void> _removeAdmin(Map<String, dynamic> admin) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppThemeColors.cardBg(dialogContext),
        title: Text(t('remove_admin_title'),
            style: TextStyle(color: AppThemeColors.primaryText(dialogContext))),
        content: Text(
          '${t('remove_admin_confirm_prefix')} ${(admin['email'] ?? '').toString()} ${t('remove_admin_confirm_suffix')}',
          style: TextStyle(color: AppThemeColors.primaryText(dialogContext)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(dialogContext))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(t('remove')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final response = await ApiClient.delete('/api/admin/admins/${admin['_id']}');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      if (!mounted) return;
      showSnack(context, (data['message'] ?? t('failed_remove_admin')).toString(), isError: true);
      return;
    }

    await _loadAdmins();
    await _loadAuditLogs();
    if (!mounted) return;
    showSnack(context, (data['message'] ?? t('admin_removed_successfully')).toString());
  }

  List<Map<String, dynamic>> get _visibleAdmins =>
      _showAll ? _admins : _admins.take(5).toList();

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
                  gradient: LinearGradient(
                    colors: AppThemeColors.waveGradient(context),
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
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                      ),
                      Expanded(
                        child: Text(
                          t('admin_roles_title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await _loadAdmins();
                          await _loadAuditLogs();
                        },
                        icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
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
                        color: AppThemeColors.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: AppColors.cyan,
                        unselectedLabelColor: AppThemeColors.secondaryText(context),
                        indicator: BoxDecoration(
                          color: AppThemeColors.tinted(context,
                              light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A57)),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        tabs: [
                          Tab(text: t('create')),
                          Tab(text: t('roles_tab')),
                          Tab(text: t('audit_tab')),
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
                        children: [_buildCreateCard(context)],
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAdmins,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildManageHeader(context),
                            const SizedBox(height: 12),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.cyan,
                                  ),
                                ),
                              )
                            else if (_error != null)
                              _buildMessageCard(context, _error!, true)
                            else if (_visibleAdmins.isEmpty)
                              _buildMessageCard(context, t('no_admins_found'), false)
                            else
                              ..._visibleAdmins.map((a) => _buildAdminCard(context, a)),
                          ],
                        ),
                      ),
                      RefreshIndicator(
                        onRefresh: _loadAuditLogs,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _buildAuditHeader(context),
                            const SizedBox(height: 12),
                            if (_loadingAuditLogs)
                              const Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.cyan,
                                  ),
                                ),
                              )
                            else if (_auditLogs.isEmpty)
                              _buildMessageCard(context, t('no_audit_logs_found'), false)
                            else ...[
                              ...(_showAll ? _auditLogs : _auditLogs.take(40))
                                  .map((l) => _buildAuditCard(context, l)),
                              if (_auditLogs.length > 40)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      icon: Icon(
                                        _showAll
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                        size: 18,
                                      ),
                                      label: Text(
                                        _showAll
                                            ? t('show_less')
                                            : '${t('show_all_count')} (${_auditLogs.length})',
                                      ),
                                      onPressed: () =>
                                          setState(() => _showAll = !_showAll),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            AppColors.cyan,
                                        side: const BorderSide(
                                            color: AppColors.cyan),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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

  Widget _buildCreateCard(BuildContext context) {
    final t = AppLocalizations.of(context).t;
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
          color: AppThemeColors.cardBg(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('create_admin_title'),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppThemeColors.primaryText(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: t('name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: t('username'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: t('email'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: TextStyle(color: AppThemeColors.primaryText(context)),
              decoration: InputDecoration(
                labelText: t('password'),
                border: const OutlineInputBorder(),
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
                  backgroundColor: AppColors.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_submitting ? t('creating_ellipsis') : t('create_admin')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageHeader(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('role_management_title'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppThemeColors.primaryText(context)),
          ),
          const SizedBox(height: 8),
          Text(
            _isCurrentSuperAdmin
                ? t('role_management_subtitle_super')
                : t('role_management_subtitle_restricted'),
            style: TextStyle(
              color: AppThemeColors.secondaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onSubmitted: (_) => _loadAdmins(),
            style: TextStyle(color: AppThemeColors.primaryText(context)),
            decoration: InputDecoration(
              hintText: t('search_admins'),
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
              child: Text(_showAll ? t('show_latest_5') : t('view_all')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditHeader(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('admin_audit_trail_title'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppThemeColors.primaryText(context)),
          ),
          const SizedBox(height: 8),
          Text(
            t('admin_audit_trail_subtitle'),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppThemeColors.primaryText(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard(BuildContext context, Map<String, dynamic> admin) {
    final t = AppLocalizations.of(context).t;
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
          color: AppThemeColors.cardBg(context),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: admin['isSuperAdmin'] == true
                        ? AppThemeColors.tinted(context,
                            light: const Color(0xFFEAF5FF), dark: const Color(0xFF1B3A57))
                        : AppThemeColors.tinted(context,
                            light: const Color(0xFFF4F8FB), dark: const Color(0xFF2A2D33)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    admin['isSuperAdmin'] == true ? t('superadmin_label') : t('admin_label'),
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text((admin['email'] ?? '').toString(),
                style: TextStyle(color: AppThemeColors.primaryText(context))),
            const SizedBox(height: 4),
            Text(
              '${t('username')}: ${(admin['username'] ?? '').toString()}',
              style: TextStyle(color: AppThemeColors.secondaryText(context)),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: admin['isSuperAdmin'] == true,
              onChanged: canToggle ? (value) => _toggleSuperAdmin(admin, value) : null,
              title: Text(t('superadmin_access_title'),
                  style: TextStyle(color: AppThemeColors.primaryText(context))),
              subtitle: Text(
                canToggle
                    ? t('toggle_elevated_admin_desc')
                    : t('only_eligible_superadmins_access_desc'),
                style: TextStyle(color: AppThemeColors.secondaryText(context)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t('permissions_label'),
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AppThemeColors.primaryText(context)),
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
                title: Text(_permissionLabel(entry.key, t),
                    style: TextStyle(color: AppThemeColors.primaryText(context))),
                subtitle: Text(
                  canEditPermissions
                      ? '${t('allow_admin_manage_prefix')} ${_permissionLabel(entry.key, t).toLowerCase()}.'
                      : t('only_eligible_superadmins_permissions_desc'),
                  style: TextStyle(color: AppThemeColors.secondaryText(context)),
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
                label: Text(t('remove_admin_button')),
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

  String _permissionLabel(String key, String Function(String) t) {
    switch (key) {
      case 'canManageUsers':
        return t('users_perm_label');
      case 'canManageTransactions':
        return t('transactions');
      case 'canManageSupport':
        return t('support_perm_label');
      case 'canManageContent':
        return t('content_perm_label');
      case 'canManageDigitise':
        return t('digitise_perm_label');
      case 'canManageSettings':
        return t('settings');
      case 'canViewAuditLogs':
        return t('audit_logs');
      default:
        return key;
    }
  }

  Widget _buildAuditCard(BuildContext context, Map<String, dynamic> log) {
    final severity = (log['severity'] ?? 'info').toString();
    final color = severity == 'critical'
        ? Colors.redAccent
        : severity == 'warning'
            ? Colors.orange
            : AppColors.cyan;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
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
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(log['adminEmail'] ?? '').toString()} • ${(log['action'] ?? '').toString()}',
                  style: TextStyle(color: AppThemeColors.secondaryText(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(log['createdAt']),
                  style: TextStyle(color: AppThemeColors.mutedText(context), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(BuildContext context, String message, bool isError) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isError
            ? AppThemeColors.tinted(context,
                light: const Color(0xFFFFEBEE), dark: const Color(0xFF4A2326))
            : AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.redAccent : AppThemeColors.primaryText(context),
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
