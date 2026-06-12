import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';

class AdminSystemSettingsPage extends StatefulWidget {
  const AdminSystemSettingsPage({super.key});

  @override
  State<AdminSystemSettingsPage> createState() =>
      _AdminSystemSettingsPageState();
}

class _AdminSystemSettingsPageState extends State<AdminSystemSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // System settings
  bool _maintenanceMode = false;
  bool _userRegistrationEnabled = true;
  bool _emailVerificationRequired = true;
  bool _phoneVerificationRequired = false;
  bool _autoApproveUsers = false;
  bool _enableNotifications = true;
  bool _enableAnalytics = true;

  // Transaction settings
  String _maxTransactionAmount = '10000';
  String _minTransactionAmount = '1';
  String _dailyTransactionLimit = '50000';
  String _monthlyTransactionLimit = '500000';

  // System preferences
  String _defaultCurrency = 'USD';
  String _timezone = 'UTC';
  String _dateFormat = 'MM/DD/YYYY';
  String _timeFormat = '12-hour';
  String _language = 'English';

  @override
  void initState() {
    super.initState();
    _loadSystemSettings();
  }

  Future<void> _loadSystemSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/admin/system-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _maintenanceMode = settings['maintenanceMode'] ?? false;
          _userRegistrationEnabled =
              settings['userRegistrationEnabled'] ?? true;
          _emailVerificationRequired =
              settings['emailVerificationRequired'] ?? true;
          _phoneVerificationRequired =
              settings['phoneVerificationRequired'] ?? false;
          _autoApproveUsers = settings['autoApproveUsers'] ?? false;
          _enableNotifications = settings['enableNotifications'] ?? true;
          _enableAnalytics = settings['enableAnalytics'] ?? true;
          _maxTransactionAmount =
              settings['maxTransactionAmount']?.toString() ?? '10000';
          _minTransactionAmount =
              settings['minTransactionAmount']?.toString() ?? '1';
          _dailyTransactionLimit =
              settings['dailyTransactionLimit']?.toString() ?? '50000';
          _monthlyTransactionLimit =
              settings['monthlyTransactionLimit']?.toString() ?? '500000';
          _defaultCurrency = settings['defaultCurrency'] ?? 'USD';
          _timezone = settings['timezone'] ?? 'UTC';
          _dateFormat = settings['dateFormat'] ?? 'MM/DD/YYYY';
          _timeFormat = settings['timeFormat'] ?? '12-hour';
          _language = settings['language'] ?? 'English';
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

  Future<void> _saveSystemSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put('/api/admin/system-settings', body: {
        'maintenanceMode': _maintenanceMode,
        'userRegistrationEnabled': _userRegistrationEnabled,
        'emailVerificationRequired': _emailVerificationRequired,
        'phoneVerificationRequired': _phoneVerificationRequired,
        'autoApproveUsers': _autoApproveUsers,
        'enableNotifications': _enableNotifications,
        'enableAnalytics': _enableAnalytics,
        'maxTransactionAmount': double.parse(_maxTransactionAmount),
        'minTransactionAmount': double.parse(_minTransactionAmount),
        'dailyTransactionLimit': double.parse(_dailyTransactionLimit),
        'monthlyTransactionLimit': double.parse(_monthlyTransactionLimit),
        'defaultCurrency': _defaultCurrency,
        'timezone': _timezone,
        'dateFormat': _dateFormat,
        'timeFormat': _timeFormat,
        'language': _language,
      });

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('System settings saved successfully!'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'System Settings',
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
              onPressed: _isSaving ? null : _saveSystemSettings,
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
                          Icons.settings_system_daydream_outlined,
                          size: 48,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'System Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Configure system-wide settings and preferences',
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

                  // System Status Section
                  _buildSettingsSection(
                    'System Status',
                    [
                      _buildSwitchTile(
                        'Maintenance Mode',
                        'Temporarily disable the system for maintenance',
                        Icons.build_outlined,
                        _maintenanceMode,
                        (value) => setState(() => _maintenanceMode = value),
                      ),
                      _buildSwitchTile(
                        'User Registration',
                        'Allow new users to register',
                        Icons.person_add_outlined,
                        _userRegistrationEnabled,
                        (value) =>
                            setState(() => _userRegistrationEnabled = value),
                      ),
                      _buildSwitchTile(
                        'Email Verification',
                        'Require email verification for new users',
                        Icons.email_outlined,
                        _emailVerificationRequired,
                        (value) =>
                            setState(() => _emailVerificationRequired = value),
                      ),
                      _buildSwitchTile(
                        'Phone Verification',
                        'Require phone verification for new users',
                        Icons.phone_outlined,
                        _phoneVerificationRequired,
                        (value) =>
                            setState(() => _phoneVerificationRequired = value),
                      ),
                      _buildSwitchTile(
                        'Auto-approve Users',
                        'Automatically approve new user registrations',
                        Icons.check_circle_outline,
                        _autoApproveUsers,
                        (value) => setState(() => _autoApproveUsers = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Transaction Limits Section
                  _buildSettingsSection(
                    'Transaction Limits',
                    [
                      _buildInputTile(
                        'Maximum Transaction Amount',
                        'Maximum amount per transaction',
                        Icons.attach_money,
                        _maxTransactionAmount,
                        (value) =>
                            setState(() => _maxTransactionAmount = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        'Minimum Transaction Amount',
                        'Minimum amount per transaction',
                        Icons.attach_money,
                        _minTransactionAmount,
                        (value) =>
                            setState(() => _minTransactionAmount = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        'Daily Transaction Limit',
                        'Maximum daily transaction limit per user',
                        Icons.today_outlined,
                        _dailyTransactionLimit,
                        (value) =>
                            setState(() => _dailyTransactionLimit = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        'Monthly Transaction Limit',
                        'Maximum monthly transaction limit per user',
                        Icons.calendar_month_outlined,
                        _monthlyTransactionLimit,
                        (value) =>
                            setState(() => _monthlyTransactionLimit = value),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // System Preferences Section
                  _buildSettingsSection(
                    'System Preferences',
                    [
                      _buildDropdownTile(
                        'Default Currency',
                        'Select default currency for transactions',
                        Icons.currency_exchange,
                        _defaultCurrency,
                        {
                          'USD': 'US Dollar (USD)',
                          'EUR': 'Euro (EUR)',
                          'GBP': 'British Pound (GBP)',
                          'INR': 'Indian Rupee (INR)',
                          'CAD': 'Canadian Dollar (CAD)',
                          'AUD': 'Australian Dollar (AUD)',
                        },
                        (value) => setState(() => _defaultCurrency = value!),
                      ),
                      _buildDropdownTile(
                        'Timezone',
                        'Select system timezone',
                        Icons.access_time,
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
                      _buildDropdownTile(
                        'Date Format',
                        'Select date display format',
                        Icons.date_range,
                        _dateFormat,
                        {
                          'MM/DD/YYYY': 'MM/DD/YYYY',
                          'DD/MM/YYYY': 'DD/MM/YYYY',
                          'YYYY-MM-DD': 'YYYY-MM-DD',
                          'DD-MM-YYYY': 'DD-MM-YYYY',
                        },
                        (value) => setState(() => _dateFormat = value!),
                      ),
                      _buildDropdownTile(
                        'Time Format',
                        'Select time display format',
                        Icons.schedule,
                        _timeFormat,
                        {
                          '12-hour': '12-hour (AM/PM)',
                          '24-hour': '24-hour',
                        },
                        (value) => setState(() => _timeFormat = value!),
                      ),
                      _buildDropdownTile(
                        'Language',
                        'Select system language',
                        Icons.language,
                        _language,
                        {
                          'English': 'English',
                          'Spanish': 'Español',
                          'French': 'Français',
                          'German': 'Deutsch',
                          'Hindi': 'हिंदी',
                        },
                        (value) => setState(() => _language = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Features Section
                  _buildSettingsSection(
                    'Features',
                    [
                      _buildSwitchTile(
                        'Enable Notifications',
                        'Enable system-wide notifications',
                        Icons.notifications_outlined,
                        _enableNotifications,
                        (value) => setState(() => _enableNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Enable Analytics',
                        'Enable system analytics and tracking',
                        Icons.analytics_outlined,
                        _enableAnalytics,
                        (value) => setState(() => _enableAnalytics = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Warning Section
                  if (_maintenanceMode)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.orange,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Maintenance Mode Active',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'The system is currently in maintenance mode. Users will not be able to access the application until maintenance mode is disabled.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange,
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

  Widget _buildInputTile(
    String title,
    String subtitle,
    IconData icon,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType? keyboardType,
  }) {
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
      trailing: SizedBox(
        width: 100,
        child: TextField(
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          keyboardType: keyboardType,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
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
}
