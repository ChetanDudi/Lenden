import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

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
        showSnack(context,
            '${AppLocalizations.of(context).t('error_loading_settings')} ${e.toString()}',
            isError: true);
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
          showSnack(context,
              AppLocalizations.of(context).t('notification_settings_saved'));
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          showSnack(context,
              errorData['message'] ??
                  AppLocalizations.of(context).t('failed_save_settings'),
              isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Error: ${e.toString()}', isError: true);
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
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('admin_notifications'), actions: [
        if (!_isLoading)
          TextButton(
            onPressed: _isSaving ? null : _saveNotificationSettings,
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
                          Icons.admin_panel_settings_outlined,
                          size: 48,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('admin_notifications'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('admin_notifications_alerts_subtitle'),
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

                  // System Alerts Section
                  _buildSettingsSection(
                    context,
                    t('system_alerts'),
                    [
                      _buildSwitchTile(
                        context,
                        t('system_alerts'),
                        t('general_system_notifications'),
                        Icons.system_update_outlined,
                        _systemAlerts,
                        (value) => setState(() => _systemAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('maintenance_alerts'),
                        t('system_maintenance_notifications'),
                        Icons.build_outlined,
                        _maintenanceAlerts,
                        (value) => setState(() => _maintenanceAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('error_alerts'),
                        t('system_error_notifications'),
                        Icons.error_outline,
                        _errorAlerts,
                        (value) => setState(() => _errorAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('performance_alerts'),
                        t('performance_issue_notifications'),
                        Icons.speed_outlined,
                        _performanceAlerts,
                        (value) => setState(() => _performanceAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('security_alerts'),
                        t('security_related_notifications'),
                        Icons.security_outlined,
                        _securityAlerts,
                        (value) => setState(() => _securityAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('backup_alerts'),
                        t('backup_status_notifications'),
                        Icons.backup_outlined,
                        _backupAlerts,
                        (value) => setState(() => _backupAlerts = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // User Management Alerts Section
                  _buildSettingsSection(
                    context,
                    t('user_management_alerts'),
                    [
                      _buildSwitchTile(
                        context,
                        t('new_user_alerts'),
                        t('new_user_registrations_notifications'),
                        Icons.person_add_outlined,
                        _newUserAlerts,
                        (value) => setState(() => _newUserAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('suspicious_activity'),
                        t('suspicious_user_activity_alerts'),
                        Icons.warning_outlined,
                        _suspiciousActivityAlerts,
                        (value) =>
                            setState(() => _suspiciousActivityAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('account_lockout_alerts'),
                        t('user_account_lockout_notifications'),
                        Icons.lock_outlined,
                        _accountLockoutAlerts,
                        (value) =>
                            setState(() => _accountLockoutAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('failed_login_alerts'),
                        t('failed_login_attempt_notifications'),
                        Icons.login_outlined,
                        _failedLoginAlerts,
                        (value) => setState(() => _failedLoginAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('user_deletion_alerts'),
                        t('user_account_deletion_notifications'),
                        Icons.delete_outline,
                        _userDeletionAlerts,
                        (value) => setState(() => _userDeletionAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('bulk_action_alerts'),
                        t('bulk_user_management_notifications'),
                        Icons.group_outlined,
                        _bulkActionAlerts,
                        (value) => setState(() => _bulkActionAlerts = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Transaction Alerts Section
                  _buildSettingsSection(
                    context,
                    t('transaction_alerts'),
                    [
                      _buildSwitchTile(
                        context,
                        t('large_transaction_alerts'),
                        t('high_value_transaction_notifications'),
                        Icons.attach_money_outlined,
                        _largeTransactionAlerts,
                        (value) =>
                            setState(() => _largeTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('failed_transaction_alerts'),
                        t('failed_transaction_notifications'),
                        Icons.cancel_outlined,
                        _failedTransactionAlerts,
                        (value) =>
                            setState(() => _failedTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('suspicious_transaction_alerts'),
                        t('suspicious_transaction_pattern_alerts'),
                        Icons.report_problem_outlined,
                        _suspiciousTransactionAlerts,
                        (value) => setState(
                            () => _suspiciousTransactionAlerts = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('daily_transaction_summary'),
                        t('daily_transaction_summary_reports'),
                        Icons.summarize_outlined,
                        _dailyTransactionSummary,
                        (value) =>
                            setState(() => _dailyTransactionSummary = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('weekly_transaction_summary'),
                        t('weekly_transaction_summary_reports'),
                        Icons.calendar_view_week_outlined,
                        _weeklyTransactionSummary,
                        (value) =>
                            setState(() => _weeklyTransactionSummary = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('monthly_transaction_summary'),
                        t('monthly_transaction_summary_reports'),
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
                    context,
                    t('notification_channels'),
                    [
                      _buildSwitchTile(
                        context,
                        t('email_notifications'),
                        t('receive_notifications_via_email'),
                        Icons.email_outlined,
                        _emailNotifications,
                        (value) => setState(() => _emailNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('push_app_notifications'),
                        t('receive_notifications_in_app'),
                        Icons.notifications_active_outlined,
                        _pushNotifications,
                        (value) => setState(() => _pushNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('sms_notifications'),
                        t('receive_sms_notifications'),
                        Icons.sms_outlined,
                        _smsNotifications,
                        (value) => setState(() => _smsNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('display_notification_count'),
                        t('show_unread_notifications_count'),
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
                    context,
                    t('notification_preferences'),
                    [
                      _buildDropdownTile(
                        context,
                        t('notification_frequency'),
                        t('how_often_receive_notifications'),
                        Icons.schedule_outlined,
                        _notificationFrequency,
                        {
                          'immediate': t('immediate'),
                          'hourly': t('hourly'),
                          'daily': t('daily'),
                          'weekly': t('weekly'),
                        },
                        (value) =>
                            setState(() => _notificationFrequency = value!),
                      ),
                      _buildDropdownTile(
                        context,
                        t('timezone_label'),
                        t('your_timezone_for_notifications'),
                        Icons.access_time_outlined,
                        _timezone,
                        {
                          'UTC': t('utc_coordinated_universal_time'),
                          'EST': t('eastern_standard_time'),
                          'PST': t('pacific_standard_time'),
                          'IST': t('indian_standard_time'),
                          'GMT': t('greenwich_mean_time'),
                        },
                        (value) => setState(() => _timezone = value!),
                      ),
                      _buildSwitchTile(
                        context,
                        t('quiet_hours'),
                        t('enable_quiet_hours_notifications'),
                        Icons.bedtime_outlined,
                        _quietHoursEnabled,
                        (value) => setState(() => _quietHoursEnabled = value),
                      ),
                      if (_quietHoursEnabled) ...[
                        _buildTimeTile(
                          context,
                          t('quiet_hours_start'),
                          t('start_time_for_quiet_hours'),
                          Icons.nightlight_outlined,
                          _quietHoursStart,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          context,
                          t('quiet_hours_end'),
                          t('end_time_for_quiet_hours'),
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
                      color: AppThemeColors.tinted(context,
                          light: Colors.blue.withValues(alpha: 0.1),
                          dark: Colors.blue.withValues(alpha: 0.22)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.notifications_active,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t('notification_status'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _getNotificationStatusText(context),
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

  String _getNotificationStatusText(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    if (!_emailNotifications &&
        !_pushNotifications &&
        !_smsNotifications &&
        !_inAppNotifications) {
      return t('all_notifications_disabled');
    }

    List<String> activeChannels = [];
    if (_emailNotifications) activeChannels.add(t('email'));
    if (_pushNotifications) activeChannels.add(t('push'));
    if (_smsNotifications) activeChannels.add(t('sms'));
    if (_inAppNotifications) activeChannels.add(t('in_app'));

    return '${t('notifications_active_via')} ${activeChannels.join(', ')}';
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

  Widget _buildTimeTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String value,
    VoidCallback onTap,
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
      trailing: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.cyan,
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
