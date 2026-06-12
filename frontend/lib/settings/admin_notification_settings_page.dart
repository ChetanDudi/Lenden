import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import '../utils/api_client.dart';

class AdminNotificationSettingsPage extends StatefulWidget {
  const AdminNotificationSettingsPage({super.key});

  @override
  State<AdminNotificationSettingsPage> createState() =>
      _AdminNotificationSettingsPageState();
}

class _AdminNotificationSettingsPageState
    extends State<AdminNotificationSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // System alerts
  bool _systemAlerts = true;
  bool _maintenanceAlerts = true;
  bool _errorAlerts = true;
  bool _performanceAlerts = true;
  bool _securityAlerts = true;
  bool _backupAlerts = true;

  // User management alerts
  bool _newUserAlerts = true;
  bool _suspiciousActivityAlerts = true;
  bool _accountLockoutAlerts = true;
  bool _failedLoginAlerts = true;
  bool _userDeletionAlerts = true;
  bool _bulkActionAlerts = true;

  // Transaction alerts
  bool _largeTransactionAlerts = true;
  bool _failedTransactionAlerts = true;
  bool _suspiciousTransactionAlerts = true;
  bool _dailyTransactionSummary = true;
  bool _weeklyTransactionSummary = true;
  bool _monthlyTransactionSummary = false;

  // Notification channels
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;
  bool _inAppNotifications = true;

  // Notification preferences
  String _notificationFrequency = 'immediate';
  bool _quietHoursEnabled = false;
  String _quietHoursStart = '22:00';
  String _quietHoursEnd = '08:00';
  String _timezone = 'UTC';
  bool _displayNotificationCount = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/admin/notification-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _systemAlerts = settings['systemAlerts'] ?? true;
          _maintenanceAlerts = settings['maintenanceAlerts'] ?? true;
          _errorAlerts = settings['errorAlerts'] ?? true;
          _performanceAlerts = settings['performanceAlerts'] ?? true;
          _securityAlerts = settings['securityAlerts'] ?? true;
          _backupAlerts = settings['backupAlerts'] ?? true;
          _newUserAlerts = settings['newUserAlerts'] ?? true;
          _suspiciousActivityAlerts =
              settings['suspiciousActivityAlerts'] ?? true;
          _accountLockoutAlerts = settings['accountLockoutAlerts'] ?? true;
          _failedLoginAlerts = settings['failedLoginAlerts'] ?? true;
          _userDeletionAlerts = settings['userDeletionAlerts'] ?? true;
          _bulkActionAlerts = settings['bulkActionAlerts'] ?? true;
          _largeTransactionAlerts = settings['largeTransactionAlerts'] ?? true;
          _failedTransactionAlerts =
              settings['failedTransactionAlerts'] ?? true;
          _suspiciousTransactionAlerts =
              settings['suspiciousTransactionAlerts'] ?? true;
          _dailyTransactionSummary =
              settings['dailyTransactionSummary'] ?? true;
          _weeklyTransactionSummary =
              settings['weeklyTransactionSummary'] ?? true;
          _monthlyTransactionSummary =
              settings['monthlyTransactionSummary'] ?? false;
          _emailNotifications = settings['emailNotifications'] ?? true;
          _pushNotifications = settings['pushNotifications'] ?? true;
          _smsNotifications = settings['smsNotifications'] ?? false;
          _inAppNotifications = settings['inAppNotifications'] ?? true;
          _notificationFrequency =
              settings['notificationFrequency'] ?? 'immediate';
          _quietHoursEnabled = settings['quietHoursEnabled'] ?? false;
          _quietHoursStart = settings['quietHoursStart'] ?? '22:00';
          _quietHoursEnd = settings['quietHoursEnd'] ?? '08:00';
          _timezone = settings['timezone'] ?? 'UTC';
          _displayNotificationCount =
              settings['displayNotificationCount'] ?? true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading settings: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveNotificationSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response =
          await ApiClient.put('/api/admin/notification-settings', body: {
        'systemAlerts': _systemAlerts,
        'maintenanceAlerts': _maintenanceAlerts,
        'errorAlerts': _errorAlerts,
        'performanceAlerts': _performanceAlerts,
        'securityAlerts': _securityAlerts,
        'backupAlerts': _backupAlerts,
        'newUserAlerts': _newUserAlerts,
        'suspiciousActivityAlerts': _suspiciousActivityAlerts,
        'accountLockoutAlerts': _accountLockoutAlerts,
        'failedLoginAlerts': _failedLoginAlerts,
        'userDeletionAlerts': _userDeletionAlerts,
        'bulkActionAlerts': _bulkActionAlerts,
        'largeTransactionAlerts': _largeTransactionAlerts,
        'failedTransactionAlerts': _failedTransactionAlerts,
        'suspiciousTransactionAlerts': _suspiciousTransactionAlerts,
        'dailyTransactionSummary': _dailyTransactionSummary,
        'weeklyTransactionSummary': _weeklyTransactionSummary,
        'monthlyTransactionSummary': _monthlyTransactionSummary,
        'emailNotifications': _emailNotifications,
        'pushNotifications': _pushNotifications,
        'smsNotifications': _smsNotifications,
        'inAppNotifications': _inAppNotifications,
        'notificationFrequency': _notificationFrequency,
        'quietHoursEnabled': _quietHoursEnabled,
        'quietHoursStart': _quietHoursStart,
        'quietHoursEnd': _quietHoursEnd,
        'timezone': _timezone,
        'displayNotificationCount': _displayNotificationCount,
      });

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        final session = Provider.of<SessionProvider>(context, listen: false);
        session.updateNotificationSettings(settings);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notification settings saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['message'] ?? 'Failed to save settings'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _quietHoursStart =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        } else {
          _quietHoursEnd =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Admin Notifications',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveNotificationSettings,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Color(0xFF00B4D8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
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
                      color: Colors.white,
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
                          Icons.admin_panel_settings_outlined,
                          size: 48,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Admin Notifications',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Configure admin-specific notifications and alerts',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // System Alerts Section
                  _buildSettingsSection(
                    'System Alerts',
                    [
                      _buildSwitchTile(
                        'System Alerts',
                        'General system notifications',
                        Icons.system_update_outlined,
                        _systemAlerts,
                        (value) => setState(() => _systemAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Maintenance Alerts',
                        'System maintenance notifications',
                        Icons.build_outlined,
                        _maintenanceAlerts,
                        (value) => setState(() => _maintenanceAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Error Alerts',
                        'System error notifications',
                        Icons.error_outline,
                        _errorAlerts,
                        (value) => setState(() => _errorAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Performance Alerts',
                        'Performance issue notifications',
                        Icons.speed_outlined,
                        _performanceAlerts,
                        (value) => setState(() => _performanceAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Security Alerts',
                        'Security-related notifications',
                        Icons.security_outlined,
                        _securityAlerts,
                        (value) => setState(() => _securityAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Backup Alerts',
                        'Backup status notifications',
                        Icons.backup_outlined,
                        _backupAlerts,
                        (value) => setState(() => _backupAlerts = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // User Management Alerts Section
                  _buildSettingsSection(
                    'User Management Alerts',
                    [
                      _buildSwitchTile(
                        'New User Alerts',
                        'Notifications for new user registrations',
                        Icons.person_add_outlined,
                        _newUserAlerts,
                        (value) => setState(() => _newUserAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Suspicious Activity',
                        'Suspicious user activity alerts',
                        Icons.warning_outlined,
                        _suspiciousActivityAlerts,
                        (value) =>
                            setState(() => _suspiciousActivityAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Account Lockout Alerts',
                        'User account lockout notifications',
                        Icons.lock_outlined,
                        _accountLockoutAlerts,
                        (value) =>
                            setState(() => _accountLockoutAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Failed Login Alerts',
                        'Failed login attempt notifications',
                        Icons.login_outlined,
                        _failedLoginAlerts,
                        (value) => setState(() => _failedLoginAlerts = value),
                      ),
                      _buildSwitchTile(
                        'User Deletion Alerts',
                        'User account deletion notifications',
                        Icons.delete_outline,
                        _userDeletionAlerts,
                        (value) => setState(() => _userDeletionAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Bulk Action Alerts',
                        'Bulk user management notifications',
                        Icons.group_outlined,
                        _bulkActionAlerts,
                        (value) => setState(() => _bulkActionAlerts = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Transaction Alerts Section
                  _buildSettingsSection(
                    'Transaction Alerts',
                    [
                      _buildSwitchTile(
                        'Large Transaction Alerts',
                        'High-value transaction notifications',
                        Icons.attach_money_outlined,
                        _largeTransactionAlerts,
                        (value) =>
                            setState(() => _largeTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Failed Transaction Alerts',
                        'Failed transaction notifications',
                        Icons.cancel_outlined,
                        _failedTransactionAlerts,
                        (value) =>
                            setState(() => _failedTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Suspicious Transaction Alerts',
                        'Suspicious transaction pattern alerts',
                        Icons.report_problem_outlined,
                        _suspiciousTransactionAlerts,
                        (value) => setState(
                            () => _suspiciousTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        'Daily Transaction Summary',
                        'Daily transaction summary reports',
                        Icons.summarize_outlined,
                        _dailyTransactionSummary,
                        (value) =>
                            setState(() => _dailyTransactionSummary = value),
                      ),
                      _buildSwitchTile(
                        'Weekly Transaction Summary',
                        'Weekly transaction summary reports',
                        Icons.calendar_view_week_outlined,
                        _weeklyTransactionSummary,
                        (value) =>
                            setState(() => _weeklyTransactionSummary = value),
                      ),
                      _buildSwitchTile(
                        'Monthly Transaction Summary',
                        'Monthly transaction summary reports',
                        Icons.calendar_view_month_outlined,
                        _monthlyTransactionSummary,
                        (value) =>
                            setState(() => _monthlyTransactionSummary = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Notification Channels Section
                  _buildSettingsSection(
                    'Notification Channels',
                    [
                      _buildSwitchTile(
                        'Email Notifications',
                        'Receive notifications via email',
                        Icons.email_outlined,
                        _emailNotifications,
                        (value) => setState(() => _emailNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Push App Notifications',
                        'Receive notifications in the app',
                        Icons.notifications_active_outlined,
                        _pushNotifications,
                        (value) => setState(() => _pushNotifications = value),
                      ),
                      _buildSwitchTile(
                        'SMS Notifications',
                        'Receive SMS notifications',
                        Icons.sms_outlined,
                        _smsNotifications,
                        (value) => setState(() => _smsNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Display Notification Count',
                        'Show the number of unread notifications',
                        Icons.looks_one,
                        _displayNotificationCount,
                        (value) =>
                            setState(() => _displayNotificationCount = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Notification Preferences Section
                  _buildSettingsSection(
                    'Notification Preferences',
                    [
                      _buildDropdownTile(
                        'Notification Frequency',
                        'How often to receive notifications',
                        Icons.schedule_outlined,
                        _notificationFrequency,
                        {
                          'immediate': 'Immediate',
                          'hourly': 'Hourly',
                          'daily': 'Daily',
                          'weekly': 'Weekly',
                        },
                        (value) =>
                            setState(() => _notificationFrequency = value!),
                      ),
                      _buildDropdownTile(
                        'Timezone',
                        'Your timezone for notifications',
                        Icons.access_time_outlined,
                        _timezone,
                        {
                          'UTC': 'UTC (Coordinated Universal Time)',
                          'EST': 'Eastern Standard Time',
                          'PST': 'Pacific Standard Time',
                          'IST': 'Indian Standard Time',
                          'GMT': 'Greenwich Mean Time',
                        },
                        (value) => setState(() => _timezone = value!),
                      ),
                      _buildSwitchTile(
                        'Quiet Hours',
                        'Enable quiet hours for notifications',
                        Icons.bedtime_outlined,
                        _quietHoursEnabled,
                        (value) => setState(() => _quietHoursEnabled = value),
                      ),
                      if (_quietHoursEnabled) ...[
                        _buildTimeTile(
                          'Quiet Hours Start',
                          'Start time for quiet hours',
                          Icons.nightlight_outlined,
                          _quietHoursStart,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          'Quiet Hours End',
                          'End time for quiet hours',
                          Icons.wb_sunny_outlined,
                          _quietHoursEnd,
                          () => _selectTime(context, false),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Notification Status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.notifications_active,
                              color: Colors.blue,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Notification Status',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getNotificationStatusText(),
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

  String _getNotificationStatusText() {
    if (!_emailNotifications &&
        !_pushNotifications &&
        !_smsNotifications &&
        !_inAppNotifications) {
      return 'All notifications are currently disabled.';
    }

    List<String> activeChannels = [];
    if (_emailNotifications) activeChannels.add('Email');
    if (_pushNotifications) activeChannels.add('Push');
    if (_smsNotifications) activeChannels.add('SMS');
    if (_inAppNotifications) activeChannels.add('In-App');

    return 'Notifications are active via: ${activeChannels.join(', ')}';
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
                color: Color(0xFF00B4D8),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00B4D8)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF00B4D8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDropdownTile(
    String title,
    String subtitle,
    IconData icon,
    String value,
    Map<String, String> options,
    ValueChanged<String?> onChanged,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00B4D8)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
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

  Widget _buildTimeTile(
    String title,
    String subtitle,
    IconData icon,
    String value,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF00B4D8)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
      trailing: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF00B4D8).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF00B4D8),
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
