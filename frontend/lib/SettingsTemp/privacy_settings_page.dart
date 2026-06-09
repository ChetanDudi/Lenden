import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import 'custom_warning_widget.dart';
import '../utils/api_client.dart';

class PrivacySettingsPage extends StatefulWidget {
  const PrivacySettingsPage({super.key});

  @override
  State<PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<PrivacySettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

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
      final session = Provider.of<SessionProvider>(context, listen: false);
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

  Future<void> _savePrivacySettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
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
              context, 'Privacy settings saved successfully!');
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

  Future<void> _deleteAccount() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Deactivate Account',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          content: const Text(
            'Are you sure you want to deactivate your account? This action is reversible. All your data will be preserved, but you will not be able to use your account until you recover it.',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _performAccountDeletion();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Deactivate Account',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _performAccountDeletion() async {
    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: const [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 18),
            Expanded(
              child: Text(
                'Deactivating account...',
                style: TextStyle(fontWeight: FontWeight.w500),
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
              context, 'Account deactivated successfully');
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context, errorData['message'] ?? 'Failed to delete account');
        }
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop(); // Close progress dialog
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context,
            'Network error: Unable to delete account. Please try again.');
      }
    }
  }

  Future<void> _loadDevices() async {
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
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
                context, 'Logged out from this device');
            return;
          }
          CustomWarningWidget.showAnimatedSuccess(context, 'Device logged out');
          _loadDevices();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context, errorData['error'] ?? 'Failed to logout device');
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, 'Error: ${e.toString()}');
      }
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Privacy Settings',
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
              onPressed: _isSaving ? null : _savePrivacySettings,
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
                          Icons.privacy_tip_outlined,
                          size: 48,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Privacy & Security',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Control your privacy and security preferences',
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

                  // Privacy Settings Section
                  _buildSettingsSection(
                    'Privacy Settings',
                    [
                      _buildSwitchTile(
                        'Profile Visibility',
                        'Allow others to see your profile information',
                        Icons.visibility_outlined,
                        _profileVisibility,
                        (value) => setState(() => _profileVisibility = value),
                      ),
                      _buildSwitchTile(
                        'Contact Sharing',
                        'Allow others to see your contact number',
                        Icons.contacts_outlined,
                        _contactSharing,
                        (value) => setState(() => _contactSharing = value),
                      ),
                      _buildSwitchTile(
                        'Analytics Sharing',
                        'Hide Analytics data on Analytics Page',
                        Icons.analytics_outlined,
                        _analyticsSharing,
                        (value) => setState(() => _analyticsSharing = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Security Settings Section
                  _buildSettingsSection(
                    'Security Settings',
                    [
                      _buildSwitchTile(
                        'Login Notifications',
                        'Get notified by email when someone logs into your account',
                        Icons.notifications_active_outlined,
                        _loginNotifications,
                        (value) => setState(() => _loginNotifications = value),
                      ),
                      _buildSwitchTile(
                        'Device Management',
                        'Allow multiple devices to access your account',
                        Icons.devices,
                        _deviceManagement,
                        (value) => setState(() => _deviceManagement = value),
                      ),
                      _buildDropdownTile(
                        'Session Timeout',
                        'Auto-logout after inactivity',
                        Icons.timer_outlined,
                        _sessionTimeout,
                        {
                          '15': '15 minutes',
                          '30': '30 minutes',
                          '60': '1 hour',
                          '120': '2 hours',
                          '0': 'Never',
                        },
                        (value) => setState(() => _sessionTimeout = value!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Device Management Section
                  _buildSettingsSection(
                    'Active Devices',
                    [
                      if (_devices.isEmpty)
                        const ListTile(
                          title: Text('No active devices found'),
                        ),
                      ..._devices.map((device) {
                        final isCurrent =
                            device['deviceId'] == _currentDeviceId;
                        return ListTile(
                          leading: Icon(
                            Icons.devices,
                            color: isCurrent ? Colors.green : Colors.grey,
                          ),
                          title: Text(
                            device['userAgent'] ?? 'Unknown Device',
                            style: TextStyle(
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isCurrent ? Colors.green : Colors.black87,
                            ),
                          ),
                          subtitle: Text(
                            'IP: ${device['ipAddress'] ?? 'N/A'}\n'
                            'Last Active: ${device['lastActive'] != null ? device['lastActive'].toString().substring(0, 19).replaceFirst('T', ' ') : 'N/A'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.logout, color: Colors.red),
                            tooltip: isCurrent
                                ? 'Logout from this device'
                                : 'Logout from this device remotely',
                            onPressed: () => _logoutDevice(device['deviceId']),
                          ),
                        );
                      }).toList(),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Data Management Section
                  _buildSettingsSection(
                    'Account Management',
                    [
                      _buildActionTile(
                        'Deactivate Account',
                        'Temporarily deactivate your account. You can recover it later.',
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Privacy & Security Tips:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Enable two-factor authentication for enhanced security\n• Regularly review your privacy settings\n• Be cautious about sharing personal information\n• Keep your app updated for the latest security features',
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

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : const Color(0xFF00B4D8),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDestructive ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.grey,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: isDestructive ? Colors.red : Colors.grey,
        size: 16,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
