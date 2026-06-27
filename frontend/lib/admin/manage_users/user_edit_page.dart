import 'package:flutter/material.dart';
import 'dart:convert';
import '../../utils/api_client.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_widgets.dart';
import '../../utils/theme_helper.dart';
import '../../l10n/app_localizations.dart';

class UserEditPage extends StatefulWidget {
  final Map<String, dynamic> user;

  const UserEditPage({super.key, required this.user});

  @override
  State<UserEditPage> createState() => _UserEditPageState();
}

class _UserEditPageState extends State<UserEditPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isSaving = false;

  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _altEmailController = TextEditingController();

  // Form values
  String _selectedGender = 'Other';
  String _selectedRole = 'user';
  DateTime? _selectedDateOfBirth;
  bool _isActive = false;
  bool _isVerified = false;
  bool _phoneVerified = false;
  bool _twoFactorEnabled = false;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _altEmailController.dispose();
    super.dispose();
  }

  void _initializeForm() {
    final user = widget.user;

    _nameController.text = user['name'] ?? '';
    _emailController.text = user['email'] ?? '';
    _phoneController.text = user['phone'] ?? '';
    _addressController.text = user['address'] ?? '';
    _altEmailController.text = user['altEmail'] ?? '';

    _selectedGender = user['gender'] ?? 'Other';
    _selectedRole = user['role'] ?? 'user';
    _isActive = user['isActive'] ?? false;
    _isVerified = user['isVerified'] ?? false;
    _phoneVerified = user['phoneVerified'] ?? false;
    _twoFactorEnabled = user['twoFactorEnabled'] ?? false;

    if (user['dateOfBirth'] != null) {
      try {
        _selectedDateOfBirth = DateTime.parse(user['dateOfBirth']);
      } catch (e) {
        _selectedDateOfBirth = null;
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDateOfBirth) {
      setState(() {
        _selectedDateOfBirth = picked;
      });
    }
  }

  Future<void> _saveUser() async {
    final t = AppLocalizations.of(context).t;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiClient.put(
        '/api/admin/users/${widget.user['_id']}',
        body: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'altEmail': _altEmailController.text.trim(),
          'gender': _selectedGender,
          'role': _selectedRole,
          'dateOfBirth': _selectedDateOfBirth?.toIso8601String(),
          'isActive': _isActive,
          'isVerified': _isVerified,
          'phoneVerified': _phoneVerified,
          'twoFactorEnabled': _twoFactorEnabled,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          showSnack(context, t('user_updated_successfully'));
          Navigator.pop(context, true);
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          showSnack(context, errorData['message'] ?? t('failed_to_update_user'), isError: true);
        }
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, '${t('error')}: ${e.toString()}', isError: true);
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
      appBar: transparentAppBar(
        context,
        title: '${t('edit')} ${widget.user['name'] ?? t('user_label')}',
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _isSaving ? null : _saveUser,
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
              child: Form(
                key: _formKey,
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
                            Icons.edit,
                            size: 48,
                            color: AppColors.cyan,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t('edit_user_information_title'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppThemeColors.primaryText(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t('update_user_details_settings'),
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

                    // Personal Information Section
                    _buildSection(
                      context,
                      t('personal_information'),
                      [
                        _buildTextField(
                          context: context,
                          controller: _nameController,
                          label: t('full_name'),
                          icon: Icons.person,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return t('please_enter_full_name');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          context: context,
                          controller: _emailController,
                          label: t('email_address_label'),
                          icon: Icons.email,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return t('please_enter_email_address');
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                .hasMatch(value)) {
                              return t('please_enter_valid_email_address');
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          context: context,
                          controller: _phoneController,
                          label: t('phone_number'),
                          icon: Icons.phone,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          context: context,
                          controller: _addressController,
                          label: t('address'),
                          icon: Icons.location_on,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          context: context,
                          controller: _altEmailController,
                          label: t('alternative_email'),
                          icon: Icons.alternate_email,
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),
                        _buildDropdownField(
                          context: context,
                          label: t('gender'),
                          icon: Icons.person_outline,
                          value: _selectedGender,
                          items: [
                            DropdownMenuItem(
                                value: 'Male', child: Text(t('male'))),
                            DropdownMenuItem(
                                value: 'Female', child: Text(t('female'))),
                            DropdownMenuItem(
                                value: 'Other', child: Text(t('other'))),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedGender = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildDateField(context),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Account Settings Section
                    _buildSection(
                      context,
                      t('account_settings'),
                      [
                        _buildDropdownField(
                          context: context,
                          label: t('account_role_label'),
                          icon: Icons.admin_panel_settings,
                          value: _selectedRole,
                          items: [
                            DropdownMenuItem(
                                value: 'user', child: Text(t('user_label'))),
                            DropdownMenuItem(
                                value: 'admin', child: Text(t('administrator'))),
                            DropdownMenuItem(
                                value: 'moderator', child: Text(t('moderator'))),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedRole = value!;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildSwitchTile(
                          context,
                          t('account_active_label'),
                          t('enable_disable_user_account_desc'),
                          Icons.check_circle_outline,
                          _isActive,
                          (value) => setState(() => _isActive = value),
                        ),
                        _buildSwitchTile(
                          context,
                          t('email_verified_title'),
                          t('mark_email_verified_desc'),
                          Icons.verified_outlined,
                          _isVerified,
                          (value) => setState(() => _isVerified = value),
                        ),
                        _buildSwitchTile(
                          context,
                          t('phone_verified_title'),
                          t('mark_phone_verified_desc'),
                          Icons.phone_android_outlined,
                          _phoneVerified,
                          (value) => setState(() => _phoneVerified = value),
                        ),
                        _buildSwitchTile(
                          context,
                          t('two_factor_authentication_label'),
                          t('enable_two_factor_auth_desc'),
                          Icons.security,
                          _twoFactorEnabled,
                          (value) => setState(() => _twoFactorEnabled = value),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.cyan,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                t('save_changes'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSection(
      BuildContext context, String title, List<Widget> children) {
    return Container(
      width: double.infinity,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(children: children),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.cyan),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cyan, width: 2),
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required BuildContext context,
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.cyan),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cyan, width: 2),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateField(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: t('date_of_birth_label'),
        prefixIcon:
            const Icon(Icons.calendar_today, color: AppColors.cyan),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cyan, width: 2),
        ),
      ),
      child: InkWell(
        onTap: _selectDate,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _selectedDateOfBirth != null
                    ? '${_selectedDateOfBirth!.day}/${_selectedDateOfBirth!.month}/${_selectedDateOfBirth!.year}'
                    : t('select_date'),
                style: TextStyle(
                  color: _selectedDateOfBirth != null
                      ? AppThemeColors.primaryText(context)
                      : AppThemeColors.secondaryText(context),
                ),
              ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
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
      contentPadding: EdgeInsets.zero,
    );
  }
}
