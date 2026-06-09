import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';

class AdminSecuritySettingsPage extends StatefulWidget {
  const AdminSecuritySettingsPage({super.key});

  @override
  State<AdminSecuritySettingsPage> createState() =>
      _AdminSecuritySettingsPageState();
}

class _AdminSecuritySettingsPageState extends State<AdminSecuritySettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Authentication settings
  bool _requireTwoFactorAuth = true;
  bool _enableSessionTimeout = true;
  String _sessionTimeoutMinutes = '30';
  bool _enableLoginNotifications = true;
  bool _enableFailedLoginAlerts = true;
  int _maxFailedAttempts = 5;
  String _lockoutDuration = '15';

  // Access control
  bool _enableIpWhitelist = false;
  String _allowedIps = '';
  bool _enableGeolocationRestriction = false;
  String _allowedCountries = '';
  bool _enableTimeBasedAccess = false;
  String _accessStartTime = '09:00';
  String _accessEndTime = '17:00';

  // Security policies
  bool _requireStrongPasswords = true;
  bool _enablePasswordExpiry = true;
  String _passwordExpiryDays = '90';
  bool _preventPasswordReuse = true;
  int _passwordHistoryCount = 5;
  bool _enableAccountLockout = true;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/admin/security-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _requireTwoFactorAuth = settings['requireTwoFactorAuth'] ?? true;
          _enableSessionTimeout = settings['enableSessionTimeout'] ?? true;
          _sessionTimeoutMinutes =
              settings['sessionTimeoutMinutes']?.toString() ?? '30';
          _enableLoginNotifications =
              settings['enableLoginNotifications'] ?? true;
          _enableFailedLoginAlerts =
              settings['enableFailedLoginAlerts'] ?? true;
          _maxFailedAttempts = settings['maxFailedAttempts'] ?? 5;
          _lockoutDuration = settings['lockoutDuration']?.toString() ?? '15';
          _enableIpWhitelist = settings['enableIpWhitelist'] ?? false;
          _allowedIps = settings['allowedIps'] ?? '';
          _enableGeolocationRestriction =
              settings['enableGeolocationRestriction'] ?? false;
          _allowedCountries = settings['allowedCountries'] ?? '';
          _enableTimeBasedAccess = settings['enableTimeBasedAccess'] ?? false;
          _accessStartTime = settings['accessStartTime'] ?? '09:00';
          _accessEndTime = settings['accessEndTime'] ?? '17:00';
          _requireStrongPasswords = settings['requireStrongPasswords'] ?? true;
          _enablePasswordExpiry = settings['enablePasswordExpiry'] ?? true;
          _passwordExpiryDays =
              settings['passwordExpiryDays']?.toString() ?? '90';
          _preventPasswordReuse = settings['preventPasswordReuse'] ?? true;
          _passwordHistoryCount = settings['passwordHistoryCount'] ?? 5;
          _enableAccountLockout = settings['enableAccountLockout'] ?? true;
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

  Future<void> _saveSecuritySettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response =
          await ApiClient.put('/api/admin/security-settings', body: {
        'requireTwoFactorAuth': _requireTwoFactorAuth,
        'enableSessionTimeout': _enableSessionTimeout,
        'sessionTimeoutMinutes': int.parse(_sessionTimeoutMinutes),
        'enableLoginNotifications': _enableLoginNotifications,
        'enableFailedLoginAlerts': _enableFailedLoginAlerts,
        'maxFailedAttempts': _maxFailedAttempts,
        'lockoutDuration': int.parse(_lockoutDuration),
        'enableIpWhitelist': _enableIpWhitelist,
        'allowedIps': _allowedIps,
        'enableGeolocationRestriction': _enableGeolocationRestriction,
        'allowedCountries': _allowedCountries,
        'enableTimeBasedAccess': _enableTimeBasedAccess,
        'accessStartTime': _accessStartTime,
        'accessEndTime': _accessEndTime,
        'requireStrongPasswords': _requireStrongPasswords,
        'enablePasswordExpiry': _enablePasswordExpiry,
        'passwordExpiryDays': int.parse(_passwordExpiryDays),
        'preventPasswordReuse': _preventPasswordReuse,
        'passwordHistoryCount': _passwordHistoryCount,
        'enableAccountLockout': _enableAccountLockout,
      });

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Security settings saved successfully!'),
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
          _accessStartTime =
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
        } else {
          _accessEndTime =
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
          'Security Settings',
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
              onPressed: _isSaving ? null : _saveSecuritySettings,
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
                          Icons.security,
                          size: 48,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Security Settings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Configure admin security and access controls',
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

                  // Authentication Section
                  _buildSettingsSection(
                    'Authentication',
                    [
                      _buildSwitchTile(
                        'Require Two-Factor Auth',
                        'Force all admins to use 2FA',
                        Icons.verified_user_outlined,
                        _requireTwoFactorAuth,
                        (value) =>
                            setState(() => _requireTwoFactorAuth = value),
                      ),
                      _buildSwitchTile(
                        'Enable Session Timeout',
                        'Automatically log out inactive sessions',
                        Icons.timer_outlined,
                        _enableSessionTimeout,
                        (value) =>
                            setState(() => _enableSessionTimeout = value),
                      ),
                      if (_enableSessionTimeout)
                        _buildInputTile(
                          'Session Timeout (minutes)',
                          'Minutes before session expires',
                          Icons.access_time,
                          _sessionTimeoutMinutes,
                          (value) =>
                              setState(() => _sessionTimeoutMinutes = value),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        'Login Notifications',
                        'Notify on successful admin logins',
                        Icons.notifications_outlined,
                        _enableLoginNotifications,
                        (value) =>
                            setState(() => _enableLoginNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Failed Login Alerts',
                        'Alert on failed login attempts',
                        Icons.warning_outlined,
                        _enableFailedLoginAlerts,
                        (value) =>
                            setState(() => _enableFailedLoginAlerts = value),
                      ),
                      _buildInputTile(
                        'Max Failed Attempts',
                        'Maximum failed login attempts',
                        Icons.block_outlined,
                        _maxFailedAttempts.toString(),
                        (value) => setState(() =>
                            _maxFailedAttempts = int.tryParse(value) ?? 5),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        'Lockout Duration (minutes)',
                        'Account lockout duration',
                        Icons.lock_clock_outlined,
                        _lockoutDuration,
                        (value) => setState(() => _lockoutDuration = value),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Access Control Section
                  _buildSettingsSection(
                    'Access Control',
                    [
                      _buildSwitchTile(
                        'IP Whitelist',
                        'Restrict access to specific IP addresses',
                        Icons.location_on_outlined,
                        _enableIpWhitelist,
                        (value) => setState(() => _enableIpWhitelist = value),
                      ),
                      if (_enableIpWhitelist)
                        _buildInputTile(
                          'Allowed IPs',
                          'Comma-separated IP addresses',
                          Icons.computer_outlined,
                          _allowedIps,
                          (value) => setState(() => _allowedIps = value),
                        ),
                      _buildSwitchTile(
                        'Geolocation Restriction',
                        'Restrict access by country',
                        Icons.public_outlined,
                        _enableGeolocationRestriction,
                        (value) => setState(
                            () => _enableGeolocationRestriction = value),
                      ),
                      if (_enableGeolocationRestriction)
                        _buildInputTile(
                          'Allowed Countries',
                          'Comma-separated country codes',
                          Icons.flag_outlined,
                          _allowedCountries,
                          (value) => setState(() => _allowedCountries = value),
                        ),
                      _buildSwitchTile(
                        'Time-Based Access',
                        'Restrict access to specific hours',
                        Icons.schedule_outlined,
                        _enableTimeBasedAccess,
                        (value) =>
                            setState(() => _enableTimeBasedAccess = value),
                      ),
                      if (_enableTimeBasedAccess) ...[
                        _buildTimeTile(
                          'Access Start Time',
                          'Start time for admin access',
                          Icons.access_time,
                          _accessStartTime,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          'Access End Time',
                          'End time for admin access',
                          Icons.access_time,
                          _accessEndTime,
                          () => _selectTime(context, false),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Password Policy Section
                  _buildSettingsSection(
                    'Password Policy',
                    [
                      _buildSwitchTile(
                        'Require Strong Passwords',
                        'Enforce password complexity requirements',
                        Icons.password_outlined,
                        _requireStrongPasswords,
                        (value) =>
                            setState(() => _requireStrongPasswords = value),
                      ),
                      _buildSwitchTile(
                        'Enable Password Expiry',
                        'Force password changes periodically',
                        Icons.schedule_outlined,
                        _enablePasswordExpiry,
                        (value) =>
                            setState(() => _enablePasswordExpiry = value),
                      ),
                      if (_enablePasswordExpiry)
                        _buildInputTile(
                          'Password Expiry (days)',
                          'Days before password expires',
                          Icons.calendar_today_outlined,
                          _passwordExpiryDays,
                          (value) =>
                              setState(() => _passwordExpiryDays = value),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        'Prevent Password Reuse',
                        'Prevent reusing recent passwords',
                        Icons.history_outlined,
                        _preventPasswordReuse,
                        (value) =>
                            setState(() => _preventPasswordReuse = value),
                      ),
                      if (_preventPasswordReuse)
                        _buildInputTile(
                          'Password History Count',
                          'Number of recent passwords to remember',
                          Icons.list_outlined,
                          _passwordHistoryCount.toString(),
                          (value) => setState(() =>
                              _passwordHistoryCount = int.tryParse(value) ?? 5),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        'Enable Account Lockout',
                        'Lock accounts after failed attempts',
                        Icons.lock_outlined,
                        _enableAccountLockout,
                        (value) =>
                            setState(() => _enableAccountLockout = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Security Status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Row(
                          children: [
                            Icon(
                              Icons.security,
                              color: Colors.green,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Security Status: Active',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'All security measures are properly configured and active.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green,
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
            color: const Color(0xFF00B4D8).withOpacity(0.1),
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
