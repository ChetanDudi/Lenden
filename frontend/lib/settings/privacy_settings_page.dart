import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import 'custom_warning_widget.dart';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

String _friendlyDeviceName(String? ua) {
  if (ua == null || ua.isEmpty) return 'Unknown Device';
  String os = 'Unknown OS';
  String browser = '';
  if (ua.contains('Android')) {
    final m = RegExp(r'Android ([0-9.]+)').firstMatch(ua);
    os = 'Android${m != null ? ' ${m.group(1)}' : ''}';
  } else if (ua.contains('iPhone')) {
    os = 'iPhone';
  } else if (ua.contains('iPad')) {
    os = 'iPad';
  } else if (ua.contains('Windows')) {
    os = 'Windows';
  } else if (ua.contains('Macintosh') || ua.contains('Mac OS')) {
    os = 'Mac';
  } else if (ua.contains('CrOS')) {
    os = 'Chromebook';
  } else if (ua.contains('Linux')) {
    os = 'Linux';
  }
  if (ua.contains('OPR') || ua.contains('OPX')) {
    browser = 'Opera';
  } else if (ua.contains('Edg/') || ua.contains('EdgA/')) {
    browser = 'Edge';
  } else if (ua.contains('Chrome')) {
    browser = 'Chrome';
  } else if (ua.contains('Firefox')) {
    browser = 'Firefox';
  } else if (ua.contains('Safari')) {
    browser = 'Safari';
  }
  return browser.isNotEmpty ? '$os · $browser' : os;
}

IconData _deviceIcon(String? ua) {
  if (ua == null) return Icons.devices;
  if (ua.contains('iPhone') || ua.contains('iPad')) return Icons.phone_iphone;
  if (ua.contains('Android')) return Icons.phone_android;
  if (ua.contains('Windows') || ua.contains('Macintosh') || ua.contains('Linux') || ua.contains('CrOS')) return Icons.computer;
  return Icons.devices;
}

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isExporting = false;

  // Privacy settings
  bool _profileVisibility = true;
  bool _contactSharing = false;
  bool _analyticsSharing = true;

  // Security settings
  bool _loginNotifications = true;
  bool _deviceManagement = true;
  String _sessionTimeout = '30'; // minutes

  List<Map<String, dynamic>> _devices = [];
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
    _loadDevices();
    _loadCurrentDeviceId();
  }

  Future<void> _loadPrivacySettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/users/privacy-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _profileVisibility = settings['profileVisibility'] ?? true;
          _contactSharing = settings['contactSharing'] ?? false;
          _analyticsSharing = settings['analyticsSharing'] ?? true;
          _loginNotifications = settings['loginNotifications'] ?? true;
          _deviceManagement = settings['deviceManagement'] ?? true;
          _sessionTimeout = settings['sessionTimeout']?.toString() ?? '30';
        });
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context,
            '${AppLocalizations.of(context).t('error_loading_settings')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _savePrivacySettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put(
        '/api/users/privacy-settings',
        body: {
          'profileVisibility': _profileVisibility,
          'contactSharing': _contactSharing,
          'analyticsSharing': _analyticsSharing,
          'loginNotifications': _loginNotifications,
          'deviceManagement': _deviceManagement,
          'sessionTimeout': int.parse(_sessionTimeout),
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, AppLocalizations.of(context).t('notification_settings_saved'));
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(context,
              errorData['message'] ?? AppLocalizations.of(context).t('failed_save_settings'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: AppThemeColors.cardBg(ctx),
          title: Text(
            t('deactivate_account_title'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: Text(
            t('deactivate_account_confirm_message'),
            style: TextStyle(color: AppThemeColors.primaryText(ctx)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                t('cancel'),
                style: TextStyle(color: AppThemeColors.secondaryText(ctx)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _performAccountDeletion();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                t('deactivate_account_title'),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performAccountDeletion() async {
    final t = AppLocalizations.of(context).t;
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        content: Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                t('deactivating_account_progress'),
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppThemeColors.primaryText(ctx)),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.delete('/api/users/delete-account');

      Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog

      if (response.statusCode == 200) {
        if (mounted) {
          await session.logout();
          Navigator.of(context).pushReplacementNamed('/');
          CustomWarningWidget.showAnimatedSuccess(
              context, t('account_deactivated_success'));
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context, errorData['message'] ?? t('failed_deactivate_account'));
        }
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, t('network_error_deactivate_account'));
      }
    }
  }

  Future<void> _loadDevices() async {
    try {
      final response = await ApiClient.get('/api/users/devices');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _devices = List<Map<String, dynamic>>.from(data['devices'] ?? []);
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _logoutDevice(String deviceId) async {
    final t = AppLocalizations.of(context).t;
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.post(
        '/api/users/logout-device',
        body: {'deviceId': deviceId},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          // If logging out current device, also log out locally
          if (deviceId == _currentDeviceId) {
            await session.logout();
            if (Navigator.canPop(context)) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
            Navigator.of(context).pushReplacementNamed('/');
            CustomWarningWidget.showAnimatedSuccess(
                context, t('logged_out_from_this_device'));
            return;
          }
          CustomWarningWidget.showAnimatedSuccess(context, t('device_logged_out'));
          _loadDevices();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context, errorData['error'] ?? t('failed_logout_device'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _logoutAllDevices() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(t('logout_all_devices_title'),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppThemeColors.primaryText(ctx))),
        content: Text(t('logout_all_devices_confirm_message'),
            style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t('cancel'),
                  style: TextStyle(color: AppThemeColors.secondaryText(ctx)))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(t('logout_all_button'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await ApiClient.post(
        '/api/users/logout-all-devices',
        body: {'currentDeviceId': _currentDeviceId ?? ''},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        CustomWarningWidget.showAnimatedSuccess(
            context, t('logged_out_from_all_other_devices'));
        _loadDevices();
      } else {
        final err = json.decode(response.body);
        CustomWarningWidget.showAnimatedError(
            context, err['error'] ?? t('failed_logout_all_devices'));
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _requestDataExport() async {
    final t = AppLocalizations.of(context).t;
    setState(() => _isExporting = true);
    try {
      final response = await ApiClient.get(
        '/api/users/export-data',
        timeout: const Duration(seconds: 30),
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'] as Map<String, dynamic>? ?? {};
        _showExportSummaryDialog(summary, data['note'] as String? ?? '');
      } else if (response.statusCode == 408) {
        CustomWarningWidget.showAnimatedError(
            context, t('server_waking_up_retry'));
      } else if (response.statusCode == 440) {
        CustomWarningWidget.showAnimatedError(
            context, t('session_expired_login_again'));
      } else {
        final err = json.decode(response.body);
        CustomWarningWidget.showAnimatedError(
            context, err['message'] ?? err['error'] ?? t('failed_export_data'));
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _showExportSummaryDialog(
      Map<String, dynamic> summary, String note) {
    final t = AppLocalizations.of(context).t;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.download_rounded,
                  color: AppColors.cyan, size: 20),
            ),
            const SizedBox(width: 10),
            Text(t('your_data_summary_title'),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppThemeColors.primaryText(ctx))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow(ctx, t('name'), summary['name']?.toString() ?? '—'),
            _summaryRow(ctx, t('email'), summary['email']?.toString() ?? '—'),
            _summaryRow(ctx, t('wallet_balance_label'),
                '₹${(summary['walletBalance'] ?? 0).toStringAsFixed(2)}'),
            _summaryRow(ctx, t('transactions_label'),
                '${summary['transactionCount'] ?? 0}'),
            _summaryRow(ctx, t('wallet_entries_label'),
                '${summary['walletTransactionCount'] ?? 0}'),
            _summaryRow(ctx, t('subscriptions_label'),
                '${summary['subscriptionCount'] ?? 0}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppThemeColors.tinted(ctx,
                    light: const Color(0xFFFFF8E1),
                    dark: const Color(0xFF5D4E2A)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCC02)),
              ),
              child: Text(note,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF5D4037))),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(t('ok'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: AppThemeColors.secondaryText(context))),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppThemeColors.primaryText(context))),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCurrentDeviceId() async {
    // Try to get deviceId from local storage
    final session = Provider.of<SessionProvider>(context, listen: false);
    final deviceId = await session.getDeviceId();
    setState(() {
      _currentDeviceId = deviceId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('privacy_settings'), actions: [
        if (!_isLoading)
          TextButton(
            onPressed: _isSaving ? null : _savePrivacySettings,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    t('save'),
                    style: const TextStyle(
                      color: AppColors.cyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
      ]),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppThemeColors.cardBg(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withValues(alpha: 0.1),
                          spreadRadius: 1,
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.privacy_tip_outlined,
                          size: 48,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('privacy_security_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('control_privacy_subtitle'),
                          style: TextStyle(
                            fontSize: 14,
                            color: AppThemeColors.secondaryText(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Privacy Settings Section
                  _buildSettingsSection(
                    context,
                    t('privacy_settings'),
                    [
                      _buildSwitchTile(
                        context,
                        t('profile_visibility_title'),
                        t('profile_visibility_desc'),
                        Icons.visibility_outlined,
                        _profileVisibility,
                        (value) => setState(() => _profileVisibility = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('contact_sharing_title'),
                        t('contact_sharing_desc'),
                        Icons.contacts_outlined,
                        _contactSharing,
                        (value) => setState(() => _contactSharing = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('analytics_sharing_title'),
                        t('analytics_sharing_desc'),
                        Icons.analytics_outlined,
                        _analyticsSharing,
                        (value) => setState(() => _analyticsSharing = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Security Settings Section
                  _buildSettingsSection(
                    context,
                    t('security_settings_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('login_notifications_title'),
                        t('login_notifications_desc'),
                        Icons.notifications_active_outlined,
                        _loginNotifications,
                        (value) => setState(() => _loginNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('device_management_title'),
                        t('device_management_desc'),
                        Icons.devices,
                        _deviceManagement,
                        (value) => setState(() => _deviceManagement = value),
                      ),
                      _buildDropdownTile(
                        context,
                        t('session_timeout_title'),
                        t('session_timeout_desc'),
                        Icons.timer_outlined,
                        _sessionTimeout,
                        {
                          '15': t('minutes_15'),
                          '30': t('minutes_30'),
                          '60': t('hour_1'),
                          '120': t('hours_2'),
                          '0': t('never'),
                        },
                        (value) => setState(() => _sessionTimeout = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Device Management Section
                  _buildSettingsSection(
                    context,
                    t('active_devices'),
                    [
                      if (_devices.isEmpty)
                        ListTile(
                          title: Text(t('no_active_devices_found'),
                              style: TextStyle(
                                  color: AppThemeColors.primaryText(context))),
                        ),
                      ..._devices.map((device) {
                        final isCurrent =
                            device['deviceId'] == _currentDeviceId;
                        return ListTile(
                          leading: Icon(
                            _deviceIcon(device['userAgent']?.toString()),
                            color: isCurrent
                                ? Colors.green
                                : AppThemeColors.secondaryText(context),
                          ),
                          title: Text(
                            _friendlyDeviceName(device['userAgent']?.toString()),
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent
                                  ? Colors.green
                                  : AppThemeColors.primaryText(context),
                            ),
                          ),
                          subtitle: Text(
                            '${t('ip_label')}: ${device['ipAddress'] ?? 'N/A'}\n'
                            '${t('last_active_label')}: ${device['lastActive'] != null ? device['lastActive'].toString().substring(0, 19).replaceFirst('T', ' ') : 'N/A'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppThemeColors.secondaryText(context)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.logout, color: Colors.red),
                            tooltip: isCurrent
                                ? t('logout_from_this_device')
                                : t('logout_from_this_device_remotely'),
                            onPressed: () => _logoutDevice(device['deviceId']),
                          ),
                        );
                      }).toList(),
                      if (_devices.length > 1)
                        _buildActionTile(
                          context,
                          t('logout_all_other_devices_title'),
                          t('logout_all_other_devices_desc'),
                          Icons.devices_other,
                          _logoutAllDevices,
                          isDestructive: true,
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Data Management Section
                  _buildSettingsSection(
                    context,
                    t('account_management_section'),
                    [
                      _buildActionTile(
                        context,
                        t('export_my_data_title'),
                        t('export_my_data_desc'),
                        Icons.download_outlined,
                        _isExporting ? () {} : _requestDataExport,
                      ),
                      _buildActionTile(
                        context,
                        t('deactivate_account_title'),
                        t('deactivate_account_desc'),
                        Icons.delete_forever_outlined,
                        () => _deleteAccount(),
                        isDestructive: true,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Information Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppThemeColors.tinted(context,
                          light: Colors.blue.withValues(alpha: 0.1),
                          dark: Colors.blue.withValues(alpha: 0.22)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('privacy_security_tips_title'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('privacy_security_tips_body'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingsSection(
      BuildContext context, String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppThemeColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.cyan,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.cyan),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppThemeColors.primaryText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: AppThemeColors.secondaryText(context),
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.cyan,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDropdownTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String value,
    Map<String, String> options,
    ValueChanged<String?> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.cyan),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppThemeColors.primaryText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: AppThemeColors.secondaryText(context),
        ),
      ),
      trailing: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        underline: Container(),
        items: options.entries.map((entry) {
          return DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value),
          );
        }).toList(),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : AppColors.cyan,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDestructive ? Colors.red : AppThemeColors.primaryText(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: AppThemeColors.secondaryText(context),
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: isDestructive ? Colors.red : AppThemeColors.secondaryText(context),
        size: 16,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
