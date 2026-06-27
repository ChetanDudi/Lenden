import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

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
        final t = AppLocalizations.of(context).t;
        showSnack(context, '${t('error_loading_settings')} ${e.toString()}', isError: true);
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
          showSnack(context, AppLocalizations.of(context).t('security_settings_saved_success'));
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          showSnack(context, errorData['message'] ?? AppLocalizations.of(context).t('failed_save_settings'), isError: true);
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
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('security_settings_title'), actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveSecuritySettings,
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
                          Icons.security,
                          size: 48,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('security_settings_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('configure_admin_security_subtitle'),
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

                  // Authentication Section
                  _buildSettingsSection(
                    context,
                    t('authentication_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('require_two_factor_auth_title'),
                        t('require_two_factor_auth_desc'),
                        Icons.verified_user_outlined,
                        _requireTwoFactorAuth,
                        (value) =>
                            setState(() => _requireTwoFactorAuth = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('enable_session_timeout_title'),
                        t('enable_session_timeout_desc'),
                        Icons.timer_outlined,
                        _enableSessionTimeout,
                        (value) =>
                            setState(() => _enableSessionTimeout = value),
                      ),
                      if (_enableSessionTimeout)
                        _buildInputTile(
                          context,
                          t('session_timeout_minutes_title'),
                          t('minutes_before_session_expires_desc'),
                          Icons.access_time,
                          _sessionTimeoutMinutes,
                          (value) =>
                              setState(() => _sessionTimeoutMinutes = value),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        context,
                        t('login_notifications_title'),
                        t('notify_successful_admin_logins_desc'),
                        Icons.notifications_outlined,
                        _enableLoginNotifications,
                        (value) =>
                            setState(() => _enableLoginNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('failed_login_alerts_title'),
                        t('alert_failed_login_attempts_desc'),
                        Icons.warning_outlined,
                        _enableFailedLoginAlerts,
                        (value) =>
                            setState(() => _enableFailedLoginAlerts = value),
                      ),
                      _buildInputTile(
                        context,
                        t('max_failed_attempts_title'),
                        t('max_failed_attempts_desc'),
                        Icons.block_outlined,
                        _maxFailedAttempts.toString(),
                        (value) => setState(() =>
                            _maxFailedAttempts = int.tryParse(value) ?? 5),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        context,
                        t('lockout_duration_minutes_title'),
                        t('account_lockout_duration_desc'),
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
                    context,
                    t('access_control_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('ip_whitelist_title'),
                        t('ip_whitelist_desc'),
                        Icons.location_on_outlined,
                        _enableIpWhitelist,
                        (value) => setState(() => _enableIpWhitelist = value),
                      ),
                      if (_enableIpWhitelist)
                        _buildInputTile(
                          context,
                          t('allowed_ips_title'),
                          t('allowed_ips_desc'),
                          Icons.computer_outlined,
                          _allowedIps,
                          (value) => setState(() => _allowedIps = value),
                        ),
                      _buildSwitchTile(
                        context,
                        t('geolocation_restriction_title'),
                        t('geolocation_restriction_desc'),
                        Icons.public_outlined,
                        _enableGeolocationRestriction,
                        (value) => setState(
                            () => _enableGeolocationRestriction = value),
                      ),
                      if (_enableGeolocationRestriction)
                        _buildInputTile(
                          context,
                          t('allowed_countries_title'),
                          t('allowed_countries_desc'),
                          Icons.flag_outlined,
                          _allowedCountries,
                          (value) => setState(() => _allowedCountries = value),
                        ),
                      _buildSwitchTile(
                        context,
                        t('time_based_access_title'),
                        t('time_based_access_desc'),
                        Icons.schedule_outlined,
                        _enableTimeBasedAccess,
                        (value) =>
                            setState(() => _enableTimeBasedAccess = value),
                      ),
                      if (_enableTimeBasedAccess) ...[
                        _buildTimeTile(
                          context,
                          t('access_start_time_title'),
                          t('access_start_time_desc'),
                          Icons.access_time,
                          _accessStartTime,
                          () => _selectTime(context, true),
                        ),
                        _buildTimeTile(
                          context,
                          t('access_end_time_title'),
                          t('access_end_time_desc'),
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
                    context,
                    t('password_policy_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('require_strong_passwords_title'),
                        t('require_strong_passwords_desc'),
                        Icons.password_outlined,
                        _requireStrongPasswords,
                        (value) =>
                            setState(() => _requireStrongPasswords = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('enable_password_expiry_title'),
                        t('enable_password_expiry_desc'),
                        Icons.schedule_outlined,
                        _enablePasswordExpiry,
                        (value) =>
                            setState(() => _enablePasswordExpiry = value),
                      ),
                      if (_enablePasswordExpiry)
                        _buildInputTile(
                          context,
                          t('password_expiry_days_title'),
                          t('password_expiry_days_desc'),
                          Icons.calendar_today_outlined,
                          _passwordExpiryDays,
                          (value) =>
                              setState(() => _passwordExpiryDays = value),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        context,
                        t('prevent_password_reuse_title'),
                        t('prevent_password_reuse_desc'),
                        Icons.history_outlined,
                        _preventPasswordReuse,
                        (value) =>
                            setState(() => _preventPasswordReuse = value),
                      ),
                      if (_preventPasswordReuse)
                        _buildInputTile(
                          context,
                          t('password_history_count_title'),
                          t('password_history_count_desc'),
                          Icons.list_outlined,
                          _passwordHistoryCount.toString(),
                          (value) => setState(() =>
                              _passwordHistoryCount = int.tryParse(value) ?? 5),
                          keyboardType: TextInputType.number,
                        ),
                      _buildSwitchTile(
                        context,
                        t('enable_account_lockout_title'),
                        t('enable_account_lockout_desc'),
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
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.security,
                              color: Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t('security_status_active_title'),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('security_measures_configured_desc'),
                          style: const TextStyle(
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

  Widget _buildInputTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String value,
    ValueChanged<String> onChanged, {
    TextInputType? keyboardType,
  }) {
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppThemeColors.primaryText(context),
          ),
        ),
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
