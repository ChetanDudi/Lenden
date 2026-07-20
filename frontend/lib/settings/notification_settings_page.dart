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

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Notification settings
  bool _transactionNotifications = true;
  bool _paymentReminders = true;
  bool _groupNotifications = true;
  bool _chatNotifications = true;
  bool _friendNotifications = true;
  bool _subscriptionNotifications = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;
  bool _notificationSound = true;
  bool _vibrationEnabled = true;
  bool _displayNotificationCount = true;

  // Notification frequency
  String _reminderFrequency = 'daily'; // daily, weekly, monthly
  String _quietHoursStart = '22:00';
  String _quietHoursEnd = '08:00';
  bool _quietHoursEnabled = false;

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
      final response = await ApiClient.get('/api/users/notification-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _transactionNotifications =
              settings['transactionNotifications'] ?? true;
          _paymentReminders = settings['paymentReminders'] ?? true;
          _groupNotifications = settings['groupNotifications'] ?? true;
          _chatNotifications = settings['chatNotifications'] ?? true;
          _friendNotifications = settings['friendNotifications'] ?? true;
          _subscriptionNotifications = settings['subscriptionNotifications'] ?? true;
          _emailNotifications = settings['emailNotifications'] ?? true;
          _pushNotifications = settings['pushNotifications'] ?? true;
          _smsNotifications = settings['smsNotifications'] ?? false;
          _notificationSound = settings['notificationSound'] ?? true;
          _vibrationEnabled = settings['vibrationEnabled'] ?? true;
          _reminderFrequency = settings['reminderFrequency'] ?? 'daily';
          _quietHoursStart = settings['quietHoursStart'] ?? '22:00';
          _quietHoursEnd = settings['quietHoursEnd'] ?? '08:00';
          _quietHoursEnabled = settings['quietHoursEnabled'] ?? false;
          _displayNotificationCount =
              settings['displayNotificationCount'] ?? true;
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

  Future<void> _saveNotificationSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put(
        '/api/users/notification-settings',
        body: {
          'transactionNotifications': _transactionNotifications,
          'paymentReminders': _paymentReminders,
          'groupNotifications': _groupNotifications,
          'chatNotifications': _chatNotifications,
          'friendNotifications': _friendNotifications,
          'subscriptionNotifications': _subscriptionNotifications,
          'emailNotifications': _emailNotifications,
          'pushNotifications': _pushNotifications,
          'smsNotifications': _smsNotifications,
          'notificationSound': _notificationSound,
          'vibrationEnabled': _vibrationEnabled,
          'reminderFrequency': _reminderFrequency,
          'quietHoursStart': _quietHoursStart,
          'quietHoursEnd': _quietHoursEnd,
          'quietHoursEnabled': _quietHoursEnabled,
          'displayNotificationCount': _displayNotificationCount,
        },
      );

      if (response.statusCode == 200) {
        Provider.of<SessionProvider>(context, listen: false)
            .updateNotificationSettings({
          'transactionNotifications': _transactionNotifications,
          'paymentReminders': _paymentReminders,
          'groupNotifications': _groupNotifications,
          'chatNotifications': _chatNotifications,
          'friendNotifications': _friendNotifications,
          'subscriptionNotifications': _subscriptionNotifications,
          'emailNotifications': _emailNotifications,
          'pushNotifications': _pushNotifications,
          'smsNotifications': _smsNotifications,
          'notificationSound': _notificationSound,
          'vibrationEnabled': _vibrationEnabled,
          'reminderFrequency': _reminderFrequency,
          'quietHoursStart': _quietHoursStart,
          'quietHoursEnd': _quietHoursEnd,
          'quietHoursEnabled': _quietHoursEnabled,
          'displayNotificationCount': _displayNotificationCount,
        });
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
      appBar: transparentAppBar(context, title: t('notification_settings'), actions: [
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
                          Icons.notifications_outlined,
                          size: 48,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('notification_preferences_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('customize_notifications_subtitle'),
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

                  // Notification Types Section
                  _buildSettingsSection(
                    context,
                    t('notification_types'),
                    [
                      _buildSwitchTile(
                        context,
                        t('transaction_notifications_title'),
                        t('transaction_notifications_desc'),
                        Icons.receipt_long,
                        _transactionNotifications,
                        (value) =>
                            setState(() => _transactionNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('payment_reminders_title'),
                        t('payment_reminders_desc'),
                        Icons.schedule,
                        _paymentReminders,
                        (value) => setState(() => _paymentReminders = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('group_notifications_title'),
                        t('group_notifications_desc'),
                        Icons.group_outlined,
                        _groupNotifications,
                        (value) => setState(() => _groupNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('chat_notifications_title'),
                        t('chat_notifications_desc'),
                        Icons.chat_bubble_outline,
                        _chatNotifications,
                        (value) => setState(() => _chatNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('subscription_notifications_title'),
                        t('subscription_notifications_desc'),
                        Icons.workspace_premium_outlined,
                        _subscriptionNotifications,
                        (value) => setState(() => _subscriptionNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('friend_notifications_title'),
                        t('friend_notifications_desc'),
                        Icons.people_outline,
                        _friendNotifications,
                        (value) => setState(() => _friendNotifications = value),
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
                        t('email_notifications_title'),
                        t('email_notifications_desc'),
                        Icons.email_outlined,
                        _emailNotifications,
                        (value) => setState(() => _emailNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('push_app_notifications_title'),
                        t('push_app_notifications_desc'),
                        Icons.notifications_active_outlined,
                        _pushNotifications,
                        (value) => setState(() => _pushNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('notification_sound_title'),
                        t('notification_sound_desc'),
                        Icons.volume_up_outlined,
                        _notificationSound,
                        (value) => setState(() => _notificationSound = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('vibration_title'),
                        t('vibration_desc'),
                        Icons.vibration,
                        _vibrationEnabled,
                        (value) => setState(() => _vibrationEnabled = value),
                      ),
                      _buildComingSoonTile(
                        context,
                        t('sms_notifications_title'),
                        t('sms_notifications_desc'),
                        Icons.sms_outlined,
                      ),
                      _buildSwitchTile(
                        context,
                        t('display_notification_count_title'),
                        t('display_notification_count_desc'),
                        Icons.looks_one,
                        _displayNotificationCount,
                        (value) =>
                            setState(() => _displayNotificationCount = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Reminder Frequency Section
                  _buildSettingsSection(
                    context,
                    t('reminder_settings'),
                    [
                      _buildDropdownTile(
                        context,
                        t('reminder_frequency_title'),
                        t('reminder_frequency_desc'),
                        Icons.repeat,
                        _reminderFrequency,
                        {
                          'daily': t('daily'),
                          'weekly': t('weekly'),
                          'monthly': t('monthly'),
                        },
                        (value) => setState(() => _reminderFrequency = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Quiet Hours Section
                  _buildSettingsSection(
                    context,
                    t('quiet_hours'),
                    [
                      _buildSwitchTile(
                        context,
                        t('enable_quiet_hours_title'),
                        t('enable_quiet_hours_desc'),
                        Icons.bedtime_outlined,
                        _quietHoursEnabled,
                        (value) => setState(() => _quietHoursEnabled = value),
                      ),
                      if (_quietHoursEnabled) ...[
                        _buildTimeTile(
                          context,
                          t('start_time'),
                          t('start_time_desc'),
                          Icons.access_time,
                          _quietHoursStart,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          context,
                          t('end_time'),
                          t('end_time_desc'),
                          Icons.access_time,
                          _quietHoursEnd,
                          () => _selectTime(context, false),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Quick Actions Section
                  _buildSettingsSection(
                    context,
                    t('notification_actions_title'),
                    [
                      _buildActionTile(
                        context,
                        t('mark_all_read_title'),
                        t('mark_all_read_desc'),
                        Icons.done_all,
                        _markAllAsRead,
                      ),
                      _buildActionTile(
                        context,
                        t('clear_read_notifications_title'),
                        t('clear_read_notifications_desc'),
                        Icons.delete_sweep_outlined,
                        _clearReadNotifications,
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
                          t('notification_tips_title'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('notification_tips_body'),
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

  Future<void> _markAllAsRead() async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.post('/api/notifications/mark-as-read', body: {});
      if (!mounted) return;
      if (response.statusCode == 200) {
        CustomWarningWidget.showAnimatedSuccess(context, t('mark_all_read_success'));
      } else {
        CustomWarningWidget.showAnimatedError(context, t('action_failed'));
      }
    } catch (e) {
      if (mounted) CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
    }
  }

  Future<void> _clearReadNotifications() async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(t('clear_read_notifications_title'),
            style: TextStyle(fontWeight: FontWeight.bold, color: AppThemeColors.primaryText(ctx))),
        content: Text(t('clear_read_confirm_message'),
            style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t('cancel'), style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(t('clear'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await ApiClient.delete('/api/notifications/clear-read');
      if (!mounted) return;
      if (response.statusCode == 200) {
        CustomWarningWidget.showAnimatedSuccess(context, t('clear_read_success'));
      } else {
        CustomWarningWidget.showAnimatedError(context, t('action_failed'));
      }
    } catch (e) {
      if (mounted) CustomWarningWidget.showAnimatedError(context, 'Error: ${e.toString()}');
    }
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
      leading: Icon(icon, color: isDestructive ? Colors.red : AppColors.cyan),
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
        style: TextStyle(fontSize: 12, color: AppThemeColors.secondaryText(context)),
      ),
      trailing: Icon(Icons.arrow_forward_ios,
          color: isDestructive ? Colors.red : AppThemeColors.secondaryText(context), size: 16),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildComingSoonTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppThemeColors.mutedText(context)),
      title: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppThemeColors.mutedText(context),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cyan.withValues(alpha: 0.4)),
            ),
            child: Text(
              AppLocalizations.of(context).t('coming_soon_label'),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.cyan),
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: AppThemeColors.mutedText(context)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
    String time,
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
      trailing: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.cyan,
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
