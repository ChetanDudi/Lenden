import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

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
          showSnack(context, AppLocalizations.of(context).t('system_settings_saved_success'));
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('system_settings_title'), actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveSystemSettings,
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
                          Icons.settings_system_daydream_outlined,
                          size: 48,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          t('system_settings_title'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('configure_system_wide_settings_subtitle'),
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

                  // System Status Section
                  _buildSettingsSection(
                    context,
                    t('system_status_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('maintenance_mode_title'),
                        t('maintenance_mode_desc'),
                        Icons.build_outlined,
                        _maintenanceMode,
                        (value) => setState(() => _maintenanceMode = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('user_registration_title'),
                        t('user_registration_desc'),
                        Icons.person_add_outlined,
                        _userRegistrationEnabled,
                        (value) =>
                            setState(() => _userRegistrationEnabled = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('email_verification_title'),
                        t('email_verification_desc'),
                        Icons.email_outlined,
                        _emailVerificationRequired,
                        (value) =>
                            setState(() => _emailVerificationRequired = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('phone_verification_title'),
                        t('phone_verification_desc'),
                        Icons.phone_outlined,
                        _phoneVerificationRequired,
                        (value) =>
                            setState(() => _phoneVerificationRequired = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('auto_approve_users_title'),
                        t('auto_approve_users_desc'),
                        Icons.check_circle_outline,
                        _autoApproveUsers,
                        (value) => setState(() => _autoApproveUsers = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Transaction Limits Section
                  _buildSettingsSection(
                    context,
                    t('transaction_limits_section'),
                    [
                      _buildInputTile(
                        context,
                        t('maximum_transaction_amount_title'),
                        t('maximum_transaction_amount_desc'),
                        Icons.attach_money,
                        _maxTransactionAmount,
                        (value) =>
                            setState(() => _maxTransactionAmount = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        context,
                        t('minimum_transaction_amount_title'),
                        t('minimum_transaction_amount_desc'),
                        Icons.attach_money,
                        _minTransactionAmount,
                        (value) =>
                            setState(() => _minTransactionAmount = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        context,
                        t('daily_transaction_limit_title'),
                        t('daily_transaction_limit_desc'),
                        Icons.today_outlined,
                        _dailyTransactionLimit,
                        (value) =>
                            setState(() => _dailyTransactionLimit = value),
                        keyboardType: TextInputType.number,
                      ),
                      _buildInputTile(
                        context,
                        t('monthly_transaction_limit_title'),
                        t('monthly_transaction_limit_desc'),
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
                    context,
                    t('system_preferences_section'),
                    [
                      _buildDropdownTile(
                        context,
                        t('default_currency_title'),
                        t('default_currency_desc'),
                        Icons.currency_exchange,
                        _defaultCurrency,
                        {
                          'USD': 'US Dollar (USD)',
                          'EUR': 'Euro (EUR)',
                          'GBP': 'British Pound (GBP)',
                          'INR': 'Indian Rupee (INR)',
                          'CAD': 'Canadian Dollar (CAD)',
                          'AUD': 'Australian Dollar (AUD)',
                          'JPY': 'Japanese Yen (JPY)',
                          'CNY': 'Chinese Yuan (CNY)',
                          'CHF': 'Swiss Franc (CHF)',
                          'SGD': 'Singapore Dollar (SGD)',
                          'HKD': 'Hong Kong Dollar (HKD)',
                          'NOK': 'Norwegian Krone (NOK)',
                          'SEK': 'Swedish Krona (SEK)',
                          'DKK': 'Danish Krone (DKK)',
                          'NZD': 'New Zealand Dollar (NZD)',
                          'MXN': 'Mexican Peso (MXN)',
                          'BRL': 'Brazilian Real (BRL)',
                          'ZAR': 'South African Rand (ZAR)',
                          'KRW': 'South Korean Won (KRW)',
                          'TRY': 'Turkish Lira (TRY)',
                          'IDR': 'Indonesian Rupiah (IDR)',
                          'MYR': 'Malaysian Ringgit (MYR)',
                          'THB': 'Thai Baht (THB)',
                          'PHP': 'Philippine Peso (PHP)',
                          'PLN': 'Polish Zloty (PLN)',
                          'CZK': 'Czech Koruna (CZK)',
                          'HUF': 'Hungarian Forint (HUF)',
                          'RON': 'Romanian Leu (RON)',
                          'BGN': 'Bulgarian Lev (BGN)',
                          'ILS': 'Israeli Shekel (ILS)',
                          'ISK': 'Icelandic Krona (ISK)',
                        },
                        (value) => setState(() => _defaultCurrency = value!),
                      ),
                      _buildDropdownTile(
                        context,
                        t('timezone_title'),
                        t('timezone_desc'),
                        Icons.access_time,
                        _timezone,
                        {
                          'UTC': t('timezone_utc'),
                          'EST': t('timezone_est'),
                          'PST': t('timezone_pst'),
                          'IST': t('timezone_ist'),
                          'GMT': t('timezone_gmt'),
                        },
                        (value) => setState(() => _timezone = value!),
                      ),
                      _buildDropdownTile(
                        context,
                        t('date_format_title'),
                        t('date_format_desc'),
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
                        context,
                        t('time_format_title'),
                        t('time_format_desc'),
                        Icons.schedule,
                        _timeFormat,
                        {
                          '12-hour': t('time_format_12_hour'),
                          '24-hour': t('time_format_24_hour'),
                        },
                        (value) => setState(() => _timeFormat = value!),
                      ),
                      _buildDropdownTile(
                        context,
                        t('language'),
                        t('select_system_language_desc'),
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
                    context,
                    t('features_section'),
                    [
                      _buildSwitchTile(
                        context,
                        t('enable_notifications_title'),
                        t('enable_notifications_desc'),
                        Icons.notifications_outlined,
                        _enableNotifications,
                        (value) => setState(() => _enableNotifications = value),
                      ),
                      _buildSwitchTile(
                        context,
                        t('enable_analytics_title'),
                        t('enable_analytics_desc'),
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
                        color: AppThemeColors.tinted(context,
                            light: Colors.orange.withValues(alpha: 0.1),
                            dark: Colors.orange.withValues(alpha: 0.22)),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                t('maintenance_mode_active_title'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('maintenance_mode_active_desc'),
                            style: const TextStyle(
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
}
