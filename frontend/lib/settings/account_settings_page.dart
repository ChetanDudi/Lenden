import 'package:flutter/material.dart';
import '../utils/pickers.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import 'custom_warning_widget.dart';
import '../utils/api_client.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Account information
  String _name = '';
  String _username = '';
  String _email = '';
  String _phone = '';
  String _address = '';
  String _gender = '';
  DateTime? _birthday;
  String? _profileImageUrl;
  DateTime? _memberSince;
  double _rating = 0.0;

  // Form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccountInformation();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadAccountInformation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiClient.get('/api/users/me');

      if (response.statusCode == 200) {
        final userData = json.decode(response.body);
        setState(() {
          _name = userData['name'] ?? '';
          _username = userData['username'] ?? '';
          _email = userData['email'] ?? '';
          _phone = userData['phone'] ?? '';
          _address = userData['address'] ?? '';
          _gender = (userData['gender'] ?? '').toString();
          _birthday = userData['birthday'] != null
              ? DateTime.parse(userData['birthday'])
              : null;
          _profileImageUrl = userData['profileImage'];
          _memberSince = userData['memberSince'] != null
              ? DateTime.parse(userData['memberSince'])
              : null;
          _rating =
              (userData['avgRating'] ?? userData['rating'] ?? 0.0).toDouble();
          // Set controller values
          _nameController.text = _name;
          _phoneController.text = _phone;
          _addressController.text = _address;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(context,
            '${AppLocalizations.of(context).t('error_loading_account_info')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validatePhone(String phone) {
    if (phone.isEmpty) return null; // optional field
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) {
      return AppLocalizations.of(context).t('valid_phone_error');
    }
    return null;
  }

  Future<void> _updateAccountInformation() async {
    final phoneError = _validatePhone(_phoneController.text.trim());
    if (phoneError != null) {
      CustomWarningWidget.showAnimatedError(context, phoneError);
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put(
        '/api/users/account-information',
        body: {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'gender': _gender,
          'birthday': _birthday?.toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(context,
              AppLocalizations.of(context).t('account_info_updated_successfully'));
          await Provider.of<SessionProvider>(context, listen: false)
              .refreshUserProfile();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(
              context,
              errorData['message'] ??
                  AppLocalizations.of(context).t('failed_update_account_info'));
        }
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, '${AppLocalizations.of(context).t('error_prefix')} ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showAppDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _birthday) {
      setState(() {
        _birthday = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      appBar: transparentAppBar(context, title: t('account_information'), actions: [
        if (!_isLoading)
          TextButton(
            onPressed: _isSaving ? null : _updateAccountInformation,
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
                        _profileImageUrl != null
                            ? CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.transparent,
                                backgroundImage:
                                    NetworkImage(_profileImageUrl!),
                              )
                            : const Icon(
                                Icons.person_outline,
                                size: 64,
                                color: AppColors.cyan,
                              ),
                        const SizedBox(height: 16),
                        Text(
                          t('account_information'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppThemeColors.primaryText(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('manage_personal_account_details'),
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

                  // Account Information Section
                  _buildSettingsSection(
                    t('personal_information'),
                    [
                      _buildReadOnlyTileWithAvatar(
                        t('username'),
                        _username,
                        Icons.person_outline,
                      ),
                      _buildReadOnlyTileWithAvatar(
                        t('email'),
                        _email,
                        Icons.email_outlined,
                      ),
                      _buildEditableTile(
                        t('full_name'),
                        t('enter_full_name'),
                        Icons.badge_outlined,
                        _nameController,
                        TextInputType.name,
                      ),
                      _buildEditableTile(
                        t('phone_number'),
                        t('enter_phone_number'),
                        Icons.phone_outlined,
                        _phoneController,
                        TextInputType.phone,
                      ),
                      _buildEditableTile(
                        t('address'),
                        t('enter_address'),
                        Icons.location_on_outlined,
                        _addressController,
                        TextInputType.streetAddress,
                        maxLines: 3,
                      ),
                      _buildDropdownTile(
                        t('gender'),
                        t('select_gender'),
                        Icons.person_outline,
                        _gender,
                        {
                          'Male': t('male'),
                          'Female': t('female'),
                          'Other': t('other'),
                        },
                        (value) => setState(() => _gender = value!),
                      ),
                      _buildDateTile(
                        t('birthday'),
                        t('select_birthday'),
                        Icons.cake_outlined,
                        _birthday,
                        () => _selectDate(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Account Status Section
                  _buildSettingsSection(
                    t('account_status'),
                    [
                      _buildStatusTile(
                        t('account_status'),
                        t('active'),
                        Icons.check_circle_outline,
                        Colors.green,
                      ),
                      _buildStatusTile(
                        t('email_verification'),
                        t('verified'),
                        Icons.verified_outlined,
                        Colors.green,
                      ),
                      _buildStatusTile(
                        t('member_since'),
                        _memberSince != null
                            ? _formatDate(_memberSince!)
                            : t('not_available'),
                        Icons.calendar_today_outlined,
                        Colors.blue,
                      ),
                      _buildRatingTile(
                        t('user_rating'),
                        _rating,
                        Icons.star_outline,
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
                          dark: const Color(0xFF1A2733)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('account_info_tips'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('account_info_tips_body'),
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

  Widget _buildSettingsSection(String title, List<Widget> children) {
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

  Widget _buildReadOnlyTileWithAvatar(
    String title,
    String value,
    IconData icon,
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
        value,
        style: TextStyle(
          fontSize: 14,
          color: AppThemeColors.secondaryText(context),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_profileImageUrl != null)
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.transparent,
              backgroundImage: NetworkImage(_profileImageUrl!),
            ),
          const SizedBox(width: 8),
          Icon(
            Icons.lock_outline,
            color: AppThemeColors.secondaryText(context),
            size: 16,
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildEditableTile(
    String title,
    String hint,
    IconData icon,
    TextEditingController controller,
    TextInputType keyboardType, {
    int maxLines = 1,
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
      subtitle: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 14,
          color: AppThemeColors.primaryText(context),
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
        value: value.isNotEmpty ? value : null,
        onChanged: onChanged,
        underline: Container(),
        hint: Text(AppLocalizations.of(context).t('select')),
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

  Widget _buildDateTile(
    String title,
    String subtitle,
    IconData icon,
    DateTime? date,
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
            date != null ? _formatDate(date) : AppLocalizations.of(context).t('select_date'),
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

  Widget _buildStatusTile(
    String title,
    String status,
    IconData icon,
    Color statusColor,
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
        status,
        style: TextStyle(
          fontSize: 14,
          color: statusColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildRatingTile(
    String title,
    double rating,
    IconData icon,
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
      subtitle: Row(
        children: [
          ...List.generate(5, (index) {
            return Icon(
              index < rating.floor()
                  ? Icons.star
                  : (index < rating ? Icons.star_half : Icons.star_border),
              color: Colors.amber,
              size: 20,
            );
          }),
          const SizedBox(width: 8),
          Text(
            '${rating.toStringAsFixed(1)}/5',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.amber,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
