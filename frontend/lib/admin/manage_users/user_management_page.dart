import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'user_details_page.dart';
import 'user_edit_page.dart';
import '../../utils/api_client.dart';
import '../widgets/top_wave_clipper.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/responsive.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class UserManagementPage extends StatefulWidget {
  final String initialStatusFilter;

  const UserManagementPage({
    super.key,
    this.initialStatusFilter = 'All',
  });

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _currentAdmin;
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _sortBy = 'name';
  bool _sortAscending = true;
  final Set<String> _selectedUserIds = {};
  Timer? _searchDebounceTimer;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _statusFilter = widget.initialStatusFilter;
    _loadUsers();
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);

    try {
      final params = <String, String>{
        'sortBy': _sortBy,
        'sortOrder': _sortAscending ? 'asc' : 'desc',
      };
      if (_searchQuery.isNotEmpty) params['search'] = _searchQuery;
      if (_statusFilter != 'All') params['statusFilter'] = _statusFilter.toLowerCase();

      final query = params.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      final response = await ApiClient.get('/api/admin/users?$query');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _users = List<Map<String, dynamic>>.from(data['users']);
            _currentAdmin = data['currentAdmin'] is Map
                ? Map<String, dynamic>.from(data['currentAdmin'])
                : null;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          final t = AppLocalizations.of(context).t;
          setState(() => _isLoading = false);
          showSnack(context, '${t('failed_to_load_users')}: ${response.statusCode}', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        final t = AppLocalizations.of(context).t;
        setState(() => _isLoading = false);
        showSnack(context, '${t('error_loading_users')}: ${e.toString()}', isError: true);
      }
    }
  }

  void _showStyledBanner({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        content: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor.withValues(alpha: 0.14),
                AppThemeColors.cardBg(context),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      message,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppThemeColors.primaryText(context),
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
  }

  bool get _canManageUsers =>
      _currentAdmin?['isSuperAdmin'] == true ||
      ((_currentAdmin?['permissions'] is Map)
          ? Map<String, dynamic>.from(_currentAdmin!['permissions'])['canManageUsers'] !=
              false
          : true);

  Future<void> _bulkForceLogout() async {
    if (_selectedUserIds.isEmpty) return;
    final t = AppLocalizations.of(context).t;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: tricolorBorder(
            radius: 28,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('force_logout_selected_title'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${t('invalidate_sessions_for_label')} ${_selectedUserIds.length} ${_selectedUserIds.length > 1 ? t('selected_users_plural') : t('selected_user_singular')}.',
                              style: TextStyle(
                                color: AppThemeColors.secondaryText(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(t('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.logout_rounded),
                          label: Text(t('force_logout_all_label')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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
    if (confirmed != true) return;
    try {
      final response = await ApiClient.post(
        '/api/admin/users/bulk-force-logout',
        body: {'userIds': _selectedUserIds.toList()},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() => _selectedUserIds.clear());
        if (!mounted) return;
        _showStyledBanner(
          title: t('force_logout_done_title'),
          message: (data['message'] ?? t('selected_users_logged_out')).toString(),
          icon: Icons.logout_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? t('bulk_force_logout_failed')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('force_logout_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _bulkUpdateStatus(bool isActive) async {
    if (_selectedUserIds.isEmpty) return;
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch(
        '/api/admin/users/bulk-status',
        body: {
          'userIds': _selectedUserIds.toList(),
          'isActive': isActive,
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        await _loadUsers();
        setState(() => _selectedUserIds.clear());
        if (!mounted) return;
        _showStyledBanner(
          title: isActive ? t('users_activated_title') : t('users_deactivated_title'),
          message: (data['message'] ?? t('users_updated_label')).toString(),
          icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
          accentColor: isActive ? Colors.green : Colors.deepOrange,
        );
      } else {
        throw Exception((data['message'] ?? t('failed_to_update_users')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('bulk_action_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _exportUsers() async {
    final t = AppLocalizations.of(context).t;
    try {
      final ids = _selectedUserIds.join(',');
      final path = ids.isEmpty
          ? '/api/admin/users/export'
          : '/api/admin/users/export?userIds=${Uri.encodeQueryComponent(ids)}';
      final response = await ApiClient.get(path);
      if (response.statusCode != 200) {
        throw Exception(t('failed_to_export_users'));
      }
      if (!mounted) return;
      _showExportOptions(t('user_export_csv_title'), response.body);
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('export_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.file_download_off_rounded,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _clearPendingUsers() async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch(
        '/api/admin/users/clear-pending',
        body: const {},
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        await _loadUsers();
        if (!mounted) return;
        final modifiedCount = (data['modifiedCount'] ?? 0) as num;
        _showStyledBanner(
          title: modifiedCount > 0 ? t('pending_reviewed_title') : t('all_clear_title'),
          message: (data['message'] ??
                  t('no_pending_users_left_to_review'))
              .toString(),
          icon: modifiedCount > 0
              ? Icons.verified_user_rounded
              : Icons.auto_awesome_rounded,
          accentColor:
              modifiedCount > 0 ? AppColors.cyan : Colors.green,
        );
      } else {
        throw Exception(
          (data['message'] ?? t('failed_to_clear_pending_users')).toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('review_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _reviewPendingUser(Map<String, dynamic> user) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final createdAt = DateTime.tryParse((user['createdAt'] ?? '').toString());
        final joinedText = createdAt != null
            ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt)
            : t('date_unavailable');

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: tricolorBorder(
              radius: 28,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(context),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.pending_actions_rounded,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('review_pending_user_title'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppThemeColors.primaryText(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t('verify_this_user_individually_desc'),
                                style: TextStyle(
                                  color: AppThemeColors.secondaryText(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildInfoPill(context, Icons.person_outline, user['name'] ?? t('unknown')),
                    const SizedBox(height: 10),
                    _buildInfoPill(context, Icons.email_outlined, user['email'] ?? t('no_email')),
                    const SizedBox(height: 10),
                    _buildInfoPill(context, Icons.alternate_email_rounded,
                        '@${user['username'] ?? t('unknown')}'),
                    const SizedBox(height: 10),
                    _buildInfoPill(context, Icons.schedule_rounded, '${t('joined_colon_label')} $joinedText'),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: Text(t('keep_pending_label')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(true),
                            icon: const Icon(Icons.verified_rounded),
                            label: Text(t('mark_verified_label')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      final response = await ApiClient.patch(
        '/api/admin/users/${user['_id']}/review-pending',
        body: const {},
      );
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw Exception(
          (data['message'] ?? t('failed_to_review_pending_user')).toString(),
        );
      }

      setState(() {
        final userIndex = _users.indexWhere((item) => item['_id'] == user['_id']);
        if (userIndex != -1) {
          _users[userIndex] = {
            ..._users[userIndex],
            'isVerified': true,
          };
        }
      });
      _loadUsers();

      if (!mounted) return;
      _showStyledBanner(
        title: t('user_reviewed_title'),
        message: (data['message'] ?? t('pending_user_marked_verified')).toString(),
        icon: Icons.verified_user_rounded,
        accentColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('review_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Widget _buildInfoPill(BuildContext context, IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppThemeColors.tinted(context,
            light: const Color(0xFFF7FAFD), dark: const Color(0xFF1E2A30)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppThemeColors.primaryText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportOptions(String title, String content) {
    final t = AppLocalizations.of(context).t;
    final previewLines = content.split('\n').take(5).join('\n');

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: tricolorBorder(
            radius: 28,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t('export_users_title'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppThemeColors.primaryText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t('export_share_options_desc'),
                    style: TextStyle(
                      color: AppThemeColors.secondaryText(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: const Color(0xFFF6FBFE),
                          dark: const Color(0xFF1A2226)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SelectableText(
                      previewLines,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppThemeColors.primaryText(context),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.visibility_rounded,
                        label: t('preview'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showExportPreview(title, content);
                        },
                      ),
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.copy_rounded,
                        label: t('copy'),
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          _showStyledBanner(
                            title: t('copied_title'),
                            message: t('export_content_copied_to_clipboard'),
                            icon: Icons.copy_rounded,
                            accentColor: AppColors.cyan,
                          );
                        },
                      ),
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.mail_outline_rounded,
                        label: t('email'),
                        onTap: () => _launchExportOption(
                          channel: 'email',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.chat_bubble_outline_rounded,
                        label: t('whatsapp_label'),
                        onTap: () => _launchExportOption(
                          channel: 'whatsapp',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.send_rounded,
                        label: t('telegram_label'),
                        onTap: () => _launchExportOption(
                          channel: 'telegram',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        context: context,
                        icon: Icons.open_in_new_rounded,
                        label: t('others_label'),
                        onTap: () => _launchExportOption(
                          channel: 'others',
                          title: title,
                          content: content,
                        ),
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
  }

  Widget _buildExportActionChip({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppThemeColors.scaffoldBg(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppThemeColors.primaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchExportOption({
    required String channel,
    required String title,
    required String content,
  }) async {
    final t = AppLocalizations.of(context).t;
    try {
      if (channel == 'others') {
        final directory = await getTemporaryDirectory();
        final file = File(
          '${directory.path}/${title.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv',
        );
        await file.writeAsString(content);
        if (!mounted) return;
        Navigator.of(context).pop();
        await OpenFile.open(file.path);
        _showStyledBanner(
          title: t('export_ready_title'),
          message: t('export_file_prepared_opened_desc'),
          icon: Icons.file_open_rounded,
          accentColor: AppColors.cyan,
        );
        return;
      }

      Uri uri;
      if (channel == 'email') {
        uri = Uri(
          scheme: 'mailto',
          queryParameters: {
            'subject': title,
            'body': content,
          },
        );
      } else if (channel == 'whatsapp') {
        uri = Uri.parse(
          'https://wa.me/?text=${Uri.encodeComponent(content)}',
        );
      } else {
        uri = Uri.parse(
          'https://t.me/share/url?text=${Uri.encodeComponent(content)}',
        );
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (!launched) {
        _showStyledBanner(
          title: t('share_app_unavailable_title'),
          message: t('share_app_unavailable_desc'),
          icon: Icons.info_outline,
          accentColor: Colors.orange,
        );
        return;
      }
      _showStyledBanner(
        title: t('export_sent_out_title'),
        message: '${t('export_prepared_for_label')} ${channel[0].toUpperCase()}${channel.substring(1)}.',
        icon: Icons.outbound_rounded,
        accentColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showStyledBanner(
        title: t('export_failed_title'),
        message: e.toString(),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  void _showExportPreview(String title, String content) {
    final t = AppLocalizations.of(context).t;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: tricolorBorder(
          radius: 28,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(context),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_present_rounded,
                        color: AppColors.cyan),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 520,
                  height: 420,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: const Color(0xFFF8FAFD),
                          dark: const Color(0xFF1A2226)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppThemeColors.primaryText(context),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(t('close')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _toggleUserStatus(String userId, bool currentStatus) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch('/api/admin/users/$userId/status',
          body: {'isActive': !currentStatus});
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          final userIndex = _users.indexWhere((user) => user['_id'] == userId);
          if (userIndex != -1) {
            _users[userIndex]['isActive'] = !currentStatus;
          }
        });
        _loadUsers();
        if (!mounted) return;
        _showStyledBanner(
          title: !currentStatus ? t('user_activated_title') : t('user_deactivated_title'),
          message: (data['message'] ?? t('user_status_updated_successfully')).toString(),
          icon: !currentStatus ? Icons.check_circle_rounded : Icons.block_rounded,
          accentColor: !currentStatus ? Colors.green : Colors.deepOrange,
        );
      } else {
        throw Exception((data['message'] ?? t('failed_to_update_user_status')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('status_update_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _forceLogoutUser(String userId, String userName) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: tricolorBorder(
            radius: 28,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('force_logout_user_title'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('force_logout_user_desc'),
                              style: TextStyle(
                                color: AppThemeColors.secondaryText(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildInfoPill(context, Icons.person_outline, userName),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(t('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.logout_rounded),
                          label: Text(t('force_logout_label')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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

    if (confirmed != true) return;

    try {
      final response = await ApiClient.post(
        '/api/admin/users/$userId/force-logout',
        body: const {},
      );
      final data = json.decode(response.body);
      if (!mounted) return;
      if (response.statusCode == 200) {
        _showStyledBanner(
          title: t('user_logged_out_title'),
          message: (data['message'] ?? '${t('all_sessions_invalidated_for_label')} $userName').toString(),
          icon: Icons.logout_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? t('failed_to_force_logout')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('force_logout_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _deleteUser(String userId, String userName) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: tricolorBorder(
            radius: 28,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppThemeColors.cardBg(context),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t('delete_user_title'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppThemeColors.primaryText(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              t('delete_user_permanent_desc'),
                              style: TextStyle(
                                color: AppThemeColors.secondaryText(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildInfoPill(context, Icons.person_outline, userName),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(t('cancel')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: Text(t('delete')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
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

    if (confirmed != true) return;

    try {
      final response = await ApiClient.delete('/api/admin/users/$userId');
      final data = json.decode(response.body);
      if (response.statusCode == 200) {
        setState(() {
          _users.removeWhere((user) => user['_id'] == userId);
        });
        _loadUsers();
        if (!mounted) return;
        _showStyledBanner(
          title: t('user_deleted_title'),
          message: (data['message'] ?? '${t('user_label')} "$userName" ${t('has_been_permanently_deleted')}').toString(),
          icon: Icons.delete_forever_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? t('failed_to_delete_user')).toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: t('delete_failed_title'),
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Color _getNoteColor(BuildContext context, int index) {
    final lightColors = [
      const Color(0xFFFFF4E6),
      const Color(0xFFE8F5E9),
      const Color(0xFFFCE4EC),
      const Color(0xFFE3F2FD),
      const Color(0xFFFFF9C4),
      const Color(0xFFF3E5F5),
    ];
    final darkColors = [
      const Color(0xFF332B1E),
      const Color(0xFF1E2E1F),
      const Color(0xFF332229),
      const Color(0xFF1C2A33),
      const Color(0xFF33311E),
      const Color(0xFF2B2233),
    ];
    return AppThemeColors.tinted(
      context,
      light: lightColors[index % lightColors.length],
      dark: darkColors[index % darkColors.length],
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
                color: AppThemeColors.waveSolid(context),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back, color: AppThemeColors.primaryText(context)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          t('user_management'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppThemeColors.primaryText(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh, color: AppThemeColors.primaryText(context)),
                        onPressed: _loadUsers,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      tricolorBorder(
                        radius: 16,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppThemeColors.cardBg(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(color: AppThemeColors.primaryText(context)),
                            decoration: InputDecoration(
                              hintText: t('search_users_by_name_email_username'),
                              prefixIcon: const Icon(Icons.search,
                                  color: AppColors.cyan),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _searchController.clear();
                                        _searchDebounceTimer?.cancel();
                                        setState(() => _searchQuery = '');
                                        _loadUsers();
                                      },
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 16,
                              ),
                            ),
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                              _searchDebounceTimer?.cancel();
                              _searchDebounceTimer = Timer(
                                const Duration(milliseconds: 300),
                                _loadUsers,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: tricolorBorder(
                              radius: 12,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: AppThemeColors.cardBg(context),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    dropdownColor: AppThemeColors.cardBg(context),
                                    style: TextStyle(color: AppThemeColors.primaryText(context)),
                                    items:
                                        [
                                              {'value': 'All', 'label': t('all_label')},
                                              {'value': 'Active', 'label': t('active')},
                                              {'value': 'Inactive', 'label': t('inactive')},
                                              {'value': 'Pending', 'label': t('pending')},
                                            ]
                                            .map((status) => DropdownMenuItem(
                                                  value: status['value'],
                                                  child: Text(status['label']!),
                                                ))
                                            .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _statusFilter = value!;
                                      });
                                      _loadUsers();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              setState(() {
                                if (_sortBy == value) {
                                  _sortAscending = !_sortAscending;
                                } else {
                                  _sortBy = value;
                                  _sortAscending = true;
                                }
                              });
                              _loadUsers();
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'name',
                                child: Text(t('sort_by_name_label')),
                              ),
                              PopupMenuItem(
                                value: 'email',
                                child: Text(t('sort_by_email_label')),
                              ),
                              PopupMenuItem(
                                value: 'createdAt',
                                child: Text(t('sort_by_date_label')),
                              ),
                            ],
                            child: tricolorBorder(
                              radius: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppThemeColors.cardBg(context),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.sort,
                                        size: 20, color: AppColors.cyan),
                                    const SizedBox(width: 4),
                                    Text(_sortBy == 'name'
                                        ? t('name')
                                        : _sortBy == 'email'
                                            ? t('email')
                                            : t('date_label')),
                                    Icon(
                                      _sortAscending
                                          ? Icons.arrow_upward
                                          : Icons.arrow_downward,
                                      size: 16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildStatCard(t('total_users_label'), _users.length.toString(),
                          Icons.people, 0),
                      const SizedBox(width: 12),
                      _buildStatCard(
                          t('active_users_label'),
                          _users
                              .where((u) => u['isActive'] == true)
                              .length
                              .toString(),
                          Icons.check_circle,
                          1),
                      const SizedBox(width: 12),
                      _buildStatCard(
                          t('pending'),
                          _users
                              .where((u) => u['isVerified'] == false)
                              .length
                              .toString(),
                          Icons.pending,
                          2),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_users.any((u) => u['isVerified'] == false))
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _statusFilter = 'Pending';
                            });
                            _loadUsers();
                          },
                          icon: const Icon(Icons.fact_check_outlined),
                          label: Text(t('review_one_by_one_label')),
                        ),
                      TextButton.icon(
                        onPressed: _canManageUsers ? _clearPendingUsers : null,
                        icon: const Icon(Icons.verified_rounded),
                        label: Text(t('review_all_pending_label')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_selectedUserIds.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selectedUserIds.length} ${t('users_selected_label')}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _canManageUsers
                              ? () => _bulkUpdateStatus(true)
                              : null,
                          child: Text(t('activate')),
                        ),
                        TextButton(
                          onPressed: _canManageUsers
                              ? () => _bulkUpdateStatus(false)
                              : null,
                          child: Text(t('deactivate')),
                        ),
                        TextButton(
                          onPressed: _exportUsers,
                          child: Text(t('export_csv')),
                        ),
                        TextButton(
                          onPressed: _bulkForceLogout,
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: Text(t('force_logout_label')),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _selectedUserIds.clear()),
                          icon: const Icon(Icons.clear),
                        ),
                      ],
                    ),
                  ),
                if (_selectedUserIds.isNotEmpty) const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _users.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _statusFilter == 'Pending'
                                        ? Icons.auto_awesome_rounded
                                        : Icons.people_outline,
                                    size: 64,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _statusFilter == 'Pending'
                                        ? t('no_pending_users_left_to_review')
                                        : t('no_users_found'),
                                    style: const TextStyle(
                                        fontSize: 18, color: Colors.grey),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return _buildUserCard(user, index);
                              },
                            ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, int index) {
    return Expanded(
      child: tricolorBorder(
        radius: 14,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getNoteColor(context, index),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.cyan, size: 24),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppThemeColors.primaryText(context),
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeColors.secondaryText(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, int index) {
    final t = AppLocalizations.of(context).t;
    final isActive = user['isActive'] ?? false;
    final isVerified = user['isVerified'] ?? false;

    return tricolorBorder(
      radius: 14,
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          color: _getNoteColor(context, index),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.cyan,
            child: _buildProfileImage(user),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  user['name'] ?? t('unknown_user'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isActive ? t('active') : t('inactive'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.green : Colors.red,
                  ),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                user['email'] ?? t('no_email'),
                style: TextStyle(fontSize: 14, color: AppThemeColors.secondaryText(context)),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    '@${user['username'] ?? t('unknown')}',
                    style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
                  ),
                  const SizedBox(width: 8),
                  if (!isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t('pending'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              if (!isVerified) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: _canManageUsers ? () => _reviewPendingUser(user) : null,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t('review_this_pending_user_label'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'view':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserDetailsPage(user: user),
                    ),
                  );
                  break;
                case 'edit':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserEditPage(user: user),
                    ),
                  ).then((_) => _loadUsers());
                  break;
                case 'toggle':
                  _toggleUserStatus(user['_id'], isActive);
                  break;
                case 'review_pending':
                  _reviewPendingUser(user);
                  break;
                case 'force_logout':
                  _forceLogoutUser(user['_id'], user['name'] ?? t('user_label'));
                  break;
                case 'delete':
                  _deleteUser(user['_id'], user['name']);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    const Icon(Icons.visibility, size: 16),
                    const SizedBox(width: 8),
                    Text(t('view_details')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    const Icon(Icons.edit, size: 16),
                    const SizedBox(width: 8),
                    Text(t('edit_user')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Row(
                  children: [
                    Icon(isActive ? Icons.block : Icons.check_circle,
                        size: 16,
                        color: isActive ? Colors.deepOrange : Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      isActive ? t('deactivate') : t('activate'),
                      style: TextStyle(
                        color: isActive ? Colors.deepOrange : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isVerified)
                PopupMenuItem(
                  value: 'review_pending',
                  child: Row(
                    children: [
                      const Icon(Icons.verified_user_outlined,
                          size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(t('review_pending')),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'force_logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout_rounded, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(t('force_logout_label'),
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(t('delete_user_label'), style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _selectedUserIds.contains(user['_id']),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedUserIds.add(user['_id']);
                      } else {
                        _selectedUserIds.remove(user['_id']);
                      }
                    });
                  },
                ),
                const Icon(Icons.more_vert),
              ],
            ),
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => UserDetailsPage(user: user),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileImage(Map<String, dynamic> user) {
    final profileImage = user['profileImage'];

    if (profileImage == null) {
      return Text(
        (user['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'U',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }

    // Handle different profileImage formats
    if (profileImage is String) {
      // It's a URL
      return ClipOval(
        child: Image.network(
          profileImage,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              (user['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'U',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          },
        ),
      );
    } else if (profileImage is Map && profileImage['url'] != null) {
      // It's a Map with URL
      return ClipOval(
        child: Image.network(
          profileImage['url'],
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Text(
              (user['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'U',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            );
          },
        ),
      );
    } else {
      // Fallback to initials
      return Text(
        (user['name'] as String?)?.substring(0, 1).toUpperCase() ?? 'U',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }
  }
}
