import 'package:flutter/material.dart';
import 'dart:convert';
import '../utils/api_client.dart';

class AdminAnalyticsSettingsPage extends StatefulWidget {
  const AdminAnalyticsSettingsPage({super.key});

  @override
  State<AdminAnalyticsSettingsPage> createState() =>
      _AdminAnalyticsSettingsPageState();
}

class _AdminAnalyticsSettingsPageState
    extends State<AdminAnalyticsSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Analytics settings
  bool _enableAnalytics = true;
  bool _enableUserTracking = true;
  bool _enableTransactionAnalytics = true;
  bool _enablePerformanceMonitoring = true;
  bool _enableErrorTracking = true;
  bool _enableUsageAnalytics = true;

  // Reporting settings
  String _reportFrequency = 'daily';
  String _reportFormat = 'pdf';
  bool _autoGenerateReports = true;
  bool _emailReports = false;
  String _reportEmail = '';

  // Data retention
  String _dataRetentionPeriod = '1_year';
  bool _anonymizeData = false;
  bool _enableDataExport = true;
  bool _enableDataBackup = true;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsSettings();
  }

  Future<void> _loadAnalyticsSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/admin/analytics-settings');

      if (response.statusCode == 200) {
        final settings = json.decode(response.body);
        setState(() {
          _enableAnalytics = settings['enableAnalytics'] ?? true;
          _enableUserTracking = settings['enableUserTracking'] ?? true;
          _enableTransactionAnalytics =
              settings['enableTransactionAnalytics'] ?? true;
          _enablePerformanceMonitoring =
              settings['enablePerformanceMonitoring'] ?? true;
          _enableErrorTracking = settings['enableErrorTracking'] ?? true;
          _enableUsageAnalytics = settings['enableUsageAnalytics'] ?? true;
          _reportFrequency = settings['reportFrequency'] ?? 'daily';
          _reportFormat = settings['reportFormat'] ?? 'pdf';
          _autoGenerateReports = settings['autoGenerateReports'] ?? true;
          _emailReports = settings['emailReports'] ?? false;
          _reportEmail = settings['reportEmail'] ?? '';
          _dataRetentionPeriod = settings['dataRetentionPeriod'] ?? '1_year';
          _anonymizeData = settings['anonymizeData'] ?? false;
          _enableDataExport = settings['enableDataExport'] ?? true;
          _enableDataBackup = settings['enableDataBackup'] ?? true;
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

  Future<void> _saveAnalyticsSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put(
        '/api/admin/analytics-settings',
        body: {
          'enableAnalytics': _enableAnalytics,
          'enableUserTracking': _enableUserTracking,
          'enableTransactionAnalytics': _enableTransactionAnalytics,
          'enablePerformanceMonitoring': _enablePerformanceMonitoring,
          'enableErrorTracking': _enableErrorTracking,
          'enableUsageAnalytics': _enableUsageAnalytics,
          'reportFrequency': _reportFrequency,
          'reportFormat': _reportFormat,
          'autoGenerateReports': _autoGenerateReports,
          'emailReports': _emailReports,
          'reportEmail': _reportEmail,
          'dataRetentionPeriod': _dataRetentionPeriod,
          'anonymizeData': _anonymizeData,
          'enableDataExport': _enableDataExport,
          'enableDataBackup': _enableDataBackup,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Analytics settings saved successfully!'),
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
          'Analytics Settings',
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
              onPressed: _isSaving ? null : _saveAnalyticsSettings,
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
                          Icons.analytics_outlined,
                          size: 48,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Analytics & Reports',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Configure analytics tracking and reporting preferences',
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

                  // Analytics Tracking Section
                  _buildSettingsSection(
                    'Analytics Tracking',
                    [
                      _buildSwitchTile(
                        'Enable Analytics',
                        'Enable system-wide analytics tracking',
                        Icons.analytics_outlined,
                        _enableAnalytics,
                        (value) => setState(() => _enableAnalytics = value),
                      ),
                      _buildSwitchTile(
                        'User Tracking',
                        'Track user behavior and interactions',
                        Icons.people_outline,
                        _enableUserTracking,
                        (value) => setState(() => _enableUserTracking = value),
                      ),
                      _buildSwitchTile(
                        'Transaction Analytics',
                        'Track transaction patterns and trends',
                        Icons.receipt_outlined,
                        _enableTransactionAnalytics,
                        (value) =>
                            setState(() => _enableTransactionAnalytics = value),
                      ),
                      _buildSwitchTile(
                        'Performance Monitoring',
                        'Monitor system performance metrics',
                        Icons.speed_outlined,
                        _enablePerformanceMonitoring,
                        (value) => setState(
                            () => _enablePerformanceMonitoring = value),
                      ),
                      _buildSwitchTile(
                        'Error Tracking',
                        'Track and monitor system errors',
                        Icons.error_outline,
                        _enableErrorTracking,
                        (value) => setState(() => _enableErrorTracking = value),
                      ),
                      _buildSwitchTile(
                        'Usage Analytics',
                        'Track feature usage and adoption',
                        Icons.trending_up_outlined,
                        _enableUsageAnalytics,
                        (value) =>
                            setState(() => _enableUsageAnalytics = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Reporting Section
                  _buildSettingsSection(
                    'Reporting',
                    [
                      _buildDropdownTile(
                        'Report Frequency',
                        'How often to generate reports',
                        Icons.schedule,
                        _reportFrequency,
                        {
                          'daily': 'Daily',
                          'weekly': 'Weekly',
                          'monthly': 'Monthly',
                          'quarterly': 'Quarterly',
                        },
                        (value) => setState(() => _reportFrequency = value!),
                      ),
                      _buildDropdownTile(
                        'Report Format',
                        'Preferred report format',
                        Icons.description_outlined,
                        _reportFormat,
                        {
                          'pdf': 'PDF',
                          'excel': 'Excel',
                          'csv': 'CSV',
                          'json': 'JSON',
                        },
                        (value) => setState(() => _reportFormat = value!),
                      ),
                      _buildSwitchTile(
                        'Auto-generate Reports',
                        'Automatically generate reports',
                        Icons.auto_awesome,
                        _autoGenerateReports,
                        (value) => setState(() => _autoGenerateReports = value),
                      ),
                      _buildSwitchTile(
                        'Email Reports',
                        'Send reports via email',
                        Icons.email_outlined,
                        _emailReports,
                        (value) => setState(() => _emailReports = value),
                      ),
                      if (_emailReports)
                        _buildInputTile(
                          'Report Email',
                          'Email address for reports',
                          Icons.email,
                          _reportEmail,
                          (value) => setState(() => _reportEmail = value),
                          keyboardType: TextInputType.emailAddress,
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Data Management Section
                  _buildSettingsSection(
                    'Data Management',
                    [
                      _buildDropdownTile(
                        'Data Retention Period',
                        'How long to keep analytics data',
                        Icons.storage_outlined,
                        _dataRetentionPeriod,
                        {
                          '30_days': '30 Days',
                          '3_months': '3 Months',
                          '6_months': '6 Months',
                          '1_year': '1 Year',
                          '2_years': '2 Years',
                          'indefinite': 'Indefinite',
                        },
                        (value) =>
                            setState(() => _dataRetentionPeriod = value!),
                      ),
                      _buildSwitchTile(
                        'Anonymize Data',
                        'Remove personal information from analytics',
                        Icons.privacy_tip_outlined,
                        _anonymizeData,
                        (value) => setState(() => _anonymizeData = value),
                      ),
                      _buildSwitchTile(
                        'Enable Data Export',
                        'Allow exporting analytics data',
                        Icons.file_download_outlined,
                        _enableDataExport,
                        (value) => setState(() => _enableDataExport = value),
                      ),
                      _buildSwitchTile(
                        'Enable Data Backup',
                        'Automatically backup analytics data',
                        Icons.backup_outlined,
                        _enableDataBackup,
                        (value) => setState(() => _enableDataBackup = value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Warning Section
                  if (!_enableAnalytics)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.3)),
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
                                'Analytics Disabled',
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
                            'Analytics tracking is currently disabled. You will not be able to generate reports or track system performance.',
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
        width: 200,
        child: TextField(
          controller: TextEditingController(text: value),
          onChanged: onChanged,
          keyboardType: keyboardType,
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
}
