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
          setState(() => _isLoading = false);
          showSnack(context, 'Failed to load users: ${response.statusCode}', isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showSnack(context, 'Error loading users: ${e.toString()}', isError: true);
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
                Colors.white,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
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
                color: Colors.white,
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
                            const Text(
                              'Force Logout Selected',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Invalidate all sessions for ${_selectedUserIds.length} selected user${_selectedUserIds.length > 1 ? 's' : ''}.',
                              style: const TextStyle(
                                color: Colors.black54,
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
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Force Logout All'),
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
          title: 'Force Logout Done',
          message: (data['message'] ?? 'Selected users have been logged out').toString(),
          icon: Icons.logout_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? 'Bulk force logout failed').toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Force Logout Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _bulkUpdateStatus(bool isActive) async {
    if (_selectedUserIds.isEmpty) return;
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
          title: isActive ? 'Users Activated' : 'Users Deactivated',
          message: (data['message'] ?? 'Users updated').toString(),
          icon: isActive ? Icons.check_circle_rounded : Icons.block_rounded,
          accentColor: isActive ? Colors.green : Colors.deepOrange,
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to update users').toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Bulk Action Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _exportUsers() async {
    try {
      final ids = _selectedUserIds.join(',');
      final path = ids.isEmpty
          ? '/api/admin/users/export'
          : '/api/admin/users/export?userIds=${Uri.encodeQueryComponent(ids)}';
      final response = await ApiClient.get(path);
      if (response.statusCode != 200) {
        throw Exception('Failed to export users');
      }
      if (!mounted) return;
      _showExportOptions('User Export CSV', response.body);
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Export Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.file_download_off_rounded,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _clearPendingUsers() async {
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
          title: modifiedCount > 0 ? 'Pending Reviewed' : 'All Clear',
          message: (data['message'] ??
                  'No pending users were left to review')
              .toString(),
          icon: modifiedCount > 0
              ? Icons.verified_user_rounded
              : Icons.auto_awesome_rounded,
          accentColor:
              modifiedCount > 0 ? AppColors.cyan : Colors.green,
        );
      } else {
        throw Exception(
          (data['message'] ?? 'Failed to clear pending users').toString(),
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Review Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _reviewPendingUser(Map<String, dynamic> user) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final createdAt = DateTime.tryParse((user['createdAt'] ?? '').toString());
        final joinedText = createdAt != null
            ? DateFormat('dd MMM yyyy, hh:mm a').format(createdAt)
            : 'Date unavailable';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: tricolorBorder(
              radius: 28,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Review Pending User',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Verify this user individually instead of clearing everyone together.',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildInfoPill(Icons.person_outline, user['name'] ?? 'Unknown'),
                    const SizedBox(height: 10),
                    _buildInfoPill(Icons.email_outlined, user['email'] ?? 'No email'),
                    const SizedBox(height: 10),
                    _buildInfoPill(Icons.alternate_email_rounded,
                        '@${user['username'] ?? 'unknown'}'),
                    const SizedBox(height: 10),
                    _buildInfoPill(Icons.schedule_rounded, 'Joined: $joinedText'),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Keep Pending'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pop(true),
                            icon: const Icon(Icons.verified_rounded),
                            label: const Text('Mark Verified'),
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
          (data['message'] ?? 'Failed to review pending user').toString(),
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
        title: 'User Reviewed',
        message: (data['message'] ?? 'Pending user marked as verified').toString(),
        icon: Icons.verified_user_rounded,
        accentColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Review Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Widget _buildInfoPill(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showExportOptions(String title, String content) {
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Export Users',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose how you want to send or review this export. Share options now carry the full export payload to the selected destination, just like the referral flow.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6FBFE),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SelectableText(
                      previewLines,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildExportActionChip(
                        icon: Icons.visibility_rounded,
                        label: 'Preview',
                        onTap: () {
                          Navigator.of(context).pop();
                          _showExportPreview(title, content);
                        },
                      ),
                      _buildExportActionChip(
                        icon: Icons.copy_rounded,
                        label: 'Copy',
                        onTap: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (!mounted) return;
                          Navigator.of(context).pop();
                          _showStyledBanner(
                            title: 'Copied',
                            message: 'Export content was copied to clipboard.',
                            icon: Icons.copy_rounded,
                            accentColor: AppColors.cyan,
                          );
                        },
                      ),
                      _buildExportActionChip(
                        icon: Icons.mail_outline_rounded,
                        label: 'Email',
                        onTap: () => _launchExportOption(
                          channel: 'email',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'WhatsApp',
                        onTap: () => _launchExportOption(
                          channel: 'whatsapp',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        icon: Icons.send_rounded,
                        label: 'Telegram',
                        onTap: () => _launchExportOption(
                          channel: 'telegram',
                          title: title,
                          content: content,
                        ),
                      ),
                      _buildExportActionChip(
                        icon: Icons.open_in_new_rounded,
                        label: 'Others',
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
          color: AppColors.scaffoldBgAlt,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
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
          title: 'Export Ready',
          message: 'The full export file was prepared and opened for external sharing.',
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
          title: 'Share App Unavailable',
          message: 'That app could not be opened on this device right now. You can still use Preview or Others.',
          icon: Icons.info_outline,
          accentColor: Colors.orange,
        );
        return;
      }
      _showStyledBanner(
        title: 'Export Sent Out',
        message: 'Your export was prepared for ${channel[0].toUpperCase()}${channel.substring(1)}.',
        icon: Icons.outbound_rounded,
        accentColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showStyledBanner(
        title: 'Export Failed',
        message: e.toString(),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  void _showExportPreview(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: tricolorBorder(
          radius: 28,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
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
                      color: const Color(0xFFF8FAFD),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        content,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
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
                    label: const Text('Close'),
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
          title: !currentStatus ? 'User Activated' : 'User Deactivated',
          message: (data['message'] ?? 'User status updated successfully').toString(),
          icon: !currentStatus ? Icons.check_circle_rounded : Icons.block_rounded,
          accentColor: !currentStatus ? Colors.green : Colors.deepOrange,
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to update user status').toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Status Update Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _forceLogoutUser(String userId, String userName) async {
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
                color: Colors.white,
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Force Logout User',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'This will immediately invalidate all active sessions for this user.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildInfoPill(Icons.person_outline, userName),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Force Logout'),
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
          title: 'User Logged Out',
          message: (data['message'] ?? 'All sessions invalidated for $userName').toString(),
          icon: Icons.logout_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to force logout').toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Force Logout Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Future<void> _deleteUser(String userId, String userName) async {
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
                color: Colors.white,
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete User',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'This action is permanent and cannot be undone.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildInfoPill(Icons.person_outline, userName),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(true),
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Delete'),
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
          title: 'User Deleted',
          message: (data['message'] ?? 'User "$userName" has been permanently deleted').toString(),
          icon: Icons.delete_forever_rounded,
          accentColor: Colors.red,
        );
      } else {
        throw Exception((data['message'] ?? 'Failed to delete user').toString());
      }
    } catch (e) {
      if (!mounted) return;
      _showStyledBanner(
        title: 'Delete Failed',
        message: e.toString().replaceFirst('Exception: ', ''),
        icon: Icons.error_outline,
        accentColor: Colors.red,
      );
    }
  }

  Color _getNoteColor(int index) {
    final colors = [
      const Color(0xFFFFF4E6),
      const Color(0xFFE8F5E9),
      const Color(0xFFFCE4EC),
      const Color(0xFFE3F2FD),
      const Color(0xFFFFF9C4),
      const Color(0xFFF3E5F5),
    ];
    return colors[index % colors.length];
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBgAlt,
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
                color: AppColors.cyan,
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
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text(
                          'User Management',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.black),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText:
                                  'Search users by name, email, or username...',
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _statusFilter,
                                    isExpanded: true,
                                    items:
                                        ['All', 'Active', 'Inactive', 'Pending']
                                            .map((status) => DropdownMenuItem(
                                                  value: status,
                                                  child: Text(status),
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
                              const PopupMenuItem(
                                value: 'name',
                                child: Text('Sort by Name'),
                              ),
                              const PopupMenuItem(
                                value: 'email',
                                child: Text('Sort by Email'),
                              ),
                              const PopupMenuItem(
                                value: 'createdAt',
                                child: Text('Sort by Date'),
                              ),
                            ],
                            child: tricolorBorder(
                              radius: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.sort,
                                        size: 20, color: AppColors.cyan),
                                    const SizedBox(width: 4),
                                    Text(_sortBy == 'name'
                                        ? 'Name'
                                        : _sortBy == 'email'
                                            ? 'Email'
                                            : 'Date'),
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
                      _buildStatCard('Total Users', _users.length.toString(),
                          Icons.people, 0),
                      const SizedBox(width: 12),
                      _buildStatCard(
                          'Active Users',
                          _users
                              .where((u) => u['isActive'] == true)
                              .length
                              .toString(),
                          Icons.check_circle,
                          1),
                      const SizedBox(width: 12),
                      _buildStatCard(
                          'Pending',
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
                          label: const Text('Review One by One'),
                        ),
                      TextButton.icon(
                        onPressed: _canManageUsers ? _clearPendingUsers : null,
                        icon: const Icon(Icons.verified_rounded),
                        label: const Text('Review All Pending'),
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_selectedUserIds.length} users selected',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: _canManageUsers
                              ? () => _bulkUpdateStatus(true)
                              : null,
                          child: const Text('Activate'),
                        ),
                        TextButton(
                          onPressed: _canManageUsers
                              ? () => _bulkUpdateStatus(false)
                              : null,
                          child: const Text('Deactivate'),
                        ),
                        TextButton(
                          onPressed: _exportUsers,
                          child: const Text('Export CSV'),
                        ),
                        TextButton(
                          onPressed: _bulkForceLogout,
                          style: TextButton.styleFrom(foregroundColor: Colors.red),
                          child: const Text('Force Logout'),
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
                                        ? 'No pending users were left to review'
                                        : 'No users found',
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
            color: _getNoteColor(index),
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, int index) {
    final isActive = user['isActive'] ?? false;
    final isVerified = user['isVerified'] ?? false;

    return tricolorBorder(
      radius: 14,
      padding: const EdgeInsets.all(1),
      child: Container(
        decoration: BoxDecoration(
          color: _getNoteColor(index),
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
                  user['name'] ?? 'Unknown User',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
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
                  isActive ? 'Active' : 'Inactive',
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
                user['email'] ?? 'No email',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    '@${user['username'] ?? 'unknown'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                      child: const Text(
                        'Pending',
                        style: TextStyle(
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
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 16,
                          color: Colors.orange,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Review this pending user',
                          style: TextStyle(
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
                  _forceLogoutUser(user['_id'], user['name'] ?? 'User');
                  break;
                case 'delete':
                  _deleteUser(user['_id'], user['name']);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'view',
                child: Row(
                  children: [
                    Icon(Icons.visibility, size: 16),
                    SizedBox(width: 8),
                    Text('View Details'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 8),
                    Text('Edit User'),
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
                      isActive ? 'Deactivate' : 'Activate',
                      style: TextStyle(
                        color: isActive ? Colors.deepOrange : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isVerified)
                const PopupMenuItem(
                  value: 'review_pending',
                  child: Row(
                    children: [
                      Icon(Icons.verified_user_outlined,
                          size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Review Pending'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'force_logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Force Logout',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, size: 16, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete User', style: TextStyle(color: Colors.red)),
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
