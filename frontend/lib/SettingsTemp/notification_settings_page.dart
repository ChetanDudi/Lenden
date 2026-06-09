import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import 'custom_warning_widget.dart';
import '../utils/api_client.dart';

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
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _smsNotifications = false;
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
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.get('/api/users/notification-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _transactionNotifications =
              settings['transactionNotifications'] ?? true;
          _paymentReminders = settings['paymentReminders'] ?? true;
          _groupNotifications = settings['groupNotifications'] ?? true;
          _emailNotifications = settings['emailNotifications'] ?? true;
          _pushNotifications = settings['pushNotifications'] ?? true;
          _smsNotifications = settings['smsNotifications'] ?? false;
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
        CustomWarningWidget.showAnimatedError(
            context, 'Error loading settings: ${e.toString()}');
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
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.put(
        '/api/users/notification-settings',
        body: {
          'transactionNotifications': _transactionNotifications,
          'paymentReminders': _paymentReminders,
          'groupNotifications': _groupNotifications,
          'emailNotifications': _emailNotifications,
          'pushNotifications': _pushNotifications,
          'smsNotifications': _smsNotifications,
          'reminderFrequency': _reminderFrequency,
          'quietHoursStart': _quietHoursStart,
          'quietHoursEnd': _quietHoursEnd,
          'quietHoursEnabled': _quietHoursEnabled,
          'displayNotificationCount': _displayNotificationCount,
        },
      );

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        session.updateNotificationSettings(settings);
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, 'Notification settings saved successfully!');
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context, errorData['message'] ?? 'Failed to save settings');
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Notification Settings',
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
                          color: Colors.grey.withOpacity(0.1),
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
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Notification Preferences',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Customize how and when you receive notifications',
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

                  // Notification Types Section
                  _buildSettingsSection(
                    'Notification Types',
                    [
                      _buildSwitchTile(
                        'Transaction Notifications',
                        'Get notified about new transactions and updates',
                        Icons.receipt_long,
                        _transactionNotifications,
                        (value) =>
                            setState(() => _transactionNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Payment Reminders',
                        'Receive reminders for upcoming payments',
                        Icons.schedule,
                        _paymentReminders,
                        (value) => setState(() => _paymentReminders = value),
                      ),
                      _buildSwitchTile(
                        'Group Notifications',
                        'Receive updates about group activities',
                        Icons.group_outlined,
                        _groupNotifications,
                        (value) => setState(() => _groupNotifications = value),
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
                        'Receive notifications via text message',
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

                  // Reminder Frequency Section
                  _buildSettingsSection(
                    'Reminder Settings',
                    [
                      _buildDropdownTile(
                        'Reminder Frequency',
                        'How often to send payment reminders',
                        Icons.repeat,
                        _reminderFrequency,
                        {
                          'daily': 'Daily',
                          'weekly': 'Weekly',
                          'monthly': 'Monthly',
                        },
                        (value) => setState(() => _reminderFrequency = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Quiet Hours Section
                  _buildSettingsSection(
                    'Quiet Hours',
                    [
                      _buildSwitchTile(
                        'Enable Quiet Hours',
                        'Mute notifications during specific hours',
                        Icons.bedtime_outlined,
                        _quietHoursEnabled,
                        (value) => setState(() => _quietHoursEnabled = value),
                      ),
                      if (_quietHoursEnabled) ...[
                        _buildTimeTile(
                          'Start Time',
                          'When quiet hours begin',
                          Icons.access_time,
                          _quietHoursStart,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          'End Time',
                          'When quiet hours end',
                          Icons.access_time,
                          _quietHoursEnd,
                          () => _selectTime(context, false),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Information Section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Notification Tips:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Enable push notifications for instant updates\n• Use quiet hours to avoid disturbances\n• Email notifications provide a backup record\n• SMS notifications work even without internet',
                          style: TextStyle(
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

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
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
    String time,
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
      trailing: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00B4D8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00B4D8),
            ),
          ),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
