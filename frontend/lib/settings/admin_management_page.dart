import 'package:flutter/material.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_widgets.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:math';
import '../utils/api_client.dart';
import '../session.dart';
import '../admin/widgets/top_wave_clipper.dart';
import '../utils/responsive.dart';
import '../utils/theme_helper.dart';
import '../l10n/app_localizations.dart';

class AdminManagementPage extends StatefulWidget {
  const AdminManagementPage({Key? key}) : super(key: key);

  @override
  _AdminManagementPageState createState() => _AdminManagementPageState();
}

class _AdminManagementPageState extends State<AdminManagementPage> {
  List<dynamic> admins = [];
  bool isLoading = true;
  String? adminBeingRemoved;
  bool showAllAdmins = false; // Add this line

  final TextEditingController _searchController = TextEditingController();
  List<dynamic> filteredAdmins = [];
  bool isSearchMode = false;

  @override
  void initState() {
    super.initState();
    fetchAdmins();
    _searchController.addListener(_filterAdmins);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> fetchAdmins() async {
    setState(() {
      isLoading = true;
    });
    try {
      final response = await ApiClient.get('/api/admin/admins');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          admins = data['admins'];
          filteredAdmins = data['admins'];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showStylishSnackBar(
        message: AppLocalizations.of(context).t('failed_to_fetch_admins'),
        isSuccess: false,
        icon: Icons.sync_problem,
      );
    }
  }

  bool isPasswordValid(String password) {
    final lengthValid = password.length >= 8 && password.length <= 30;
    final hasUpper = RegExp(r'[A-Z]').hasMatch(password);
    final hasLower = RegExp(r'[a-z]').hasMatch(password);
    final hasSpecial = RegExp(r'[^A-Za-z0-9]').hasMatch(password);
    return lengthValid && hasUpper && hasLower && hasSpecial;
  }

  Future<void> addAdmin() async {
    final t = AppLocalizations.of(context).t;
    final formKey = GlobalKey<FormState>();
    String name = '';
    String email = '';
    String username = '';
    String password = '';
    String gender = 'Other';
    String? emailError;
    String? usernameError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing while submitting
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(ctx).size.width * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppThemeColors.cardBg(ctx),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  spreadRadius: 5,
                  blurRadius: 15,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with wave design
                    Stack(
                      children: [
                        ClipPath(
                          clipper: TopWaveClipper(),
                          child: Container(
                            height: 100,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.cyan, Color(0xFF48CAE4)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 20,
                          left: 0,
                          right: 0,
                          child: Column(
                            children: [
                              const Icon(Icons.admin_panel_settings,
                                  color: Colors.white, size: 40),
                              Text(
                                t('add_new_admin'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Input Fields with enhanced styling
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(ctx),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 1,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: TextFormField(
                        style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                        decoration: InputDecoration(
                          labelText: t('name'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(color: AppColors.cyan),
                          ),
                          prefixIcon:
                              const Icon(Icons.person, color: AppColors.cyan),
                          filled: true,
                          fillColor: AppThemeColors.cardBg(ctx),
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? t('required') : null,
                        onSaved: (value) => name = value ?? '',
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Email field with error message
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppThemeColors.cardBg(ctx),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                spreadRadius: 1,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: TextFormField(
                            style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                            decoration: InputDecoration(
                              labelText: t('email'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: emailError != null
                                      ? Colors.red
                                      : AppColors.cyan,
                                ),
                              ),
                              prefixIcon: Icon(Icons.email,
                                  color: emailError != null
                                      ? Colors.red
                                      : AppColors.cyan),
                              filled: true,
                              fillColor: AppThemeColors.cardBg(ctx),
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? t('required') : null,
                            onSaved: (value) => email = value ?? '',
                          ),
                        ),
                        if (emailError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 16),
                            child: Text(
                              emailError ?? '',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // Username field with error message
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppThemeColors.cardBg(ctx),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                spreadRadius: 1,
                                blurRadius: 5,
                              ),
                            ],
                          ),
                          child: TextFormField(
                            style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                            decoration: InputDecoration(
                              labelText: t('username'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: usernameError != null
                                      ? Colors.red
                                      : AppColors.cyan,
                                ),
                              ),
                              prefixIcon: Icon(Icons.account_circle,
                                  color: usernameError != null
                                      ? Colors.red
                                      : AppColors.cyan),
                              filled: true,
                              fillColor: AppThemeColors.cardBg(ctx),
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? t('required') : null,
                            onSaved: (value) => username = value ?? '',
                          ),
                        ),
                        if (usernameError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 16),
                            child: Text(
                              usernameError ?? '',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(ctx),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 1,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: TextFormField(
                        obscureText: true,
                        style: TextStyle(color: AppThemeColors.primaryText(ctx)),
                        decoration: InputDecoration(
                          labelText: t('password'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(color: AppColors.cyan),
                          ),
                          prefixIcon:
                              const Icon(Icons.lock, color: AppColors.cyan),
                          filled: true,
                          fillColor: AppThemeColors.cardBg(ctx),
                          helperText: t('password_requirements_short'),
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) return t('required');
                          if (!isPasswordValid(value!)) {
                            return t('password_requirements_short');
                          }
                          return null;
                        },
                        onSaved: (value) => password = value ?? '',
                      ),
                    ),
                    const SizedBox(height: 15),

                    // Gender Selection
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeColors.cardBg(ctx),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            spreadRadius: 1,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: DropdownButtonFormField<String>(
                        value: gender,
                        decoration: InputDecoration(
                          labelText: t('gender'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(color: AppColors.cyan),
                          ),
                          prefixIcon:
                              const Icon(Icons.people, color: AppColors.cyan),
                          filled: true,
                          fillColor: AppThemeColors.cardBg(ctx),
                        ),
                        items: ['Male', 'Female', 'Other'].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            gender = newValue;
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 25),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: isSubmitting
                              ? null
                              : () => Navigator.pop(dialogContext),
                          child: Text(t('cancel'),
                              style: TextStyle(color: AppThemeColors.secondaryText(ctx))),
                        ),
                        ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (formKey.currentState?.validate() ??
                                      false) {
                                    setState(() {
                                      isSubmitting = true;
                                      emailError = null;
                                      usernameError = null;
                                    });

                                    formKey.currentState?.save();
                                    try {
                                      final response = await ApiClient.post(
                                        '/api/admin/admins',
                                        body: {
                                          'name': name,
                                          'email': email,
                                          'username': username,
                                          'password': password,
                                          'gender': gender,
                                        },
                                      );

                                      final responseData =
                                          json.decode(response.body);

                                      if (response.statusCode == 201) {
                                        Navigator.pop(dialogContext);
                                        fetchAdmins();
                                        _showStylishSnackBar(
                                          message: responseData['message'] ??
                                              t('admin_added_successfully'),
                                          icon: Icons.person_add,
                                        );
                                      } else {
                                        setState(() {
                                          isSubmitting = false;
                                          if (responseData['message']
                                              .contains('email')) {
                                            emailError =
                                                responseData['message'];
                                          } else if (responseData['message']
                                              .contains('username')) {
                                            usernameError =
                                                responseData['message'];
                                          } else {
                                            // Show general error
                                            ScaffoldMessenger.of(dialogContext)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    responseData['message'] ??
                                                        t('failed_to_add_admin')),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        });
                                      }
                                    } catch (e) {
                                      setState(() {
                                        isSubmitting = false;
                                      });
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('${t('error')}: ${e.toString()}'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.cyan,
                            disabledBackgroundColor:
                                AppColors.cyan.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: isSubmitting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(t('adding_admin_ellipsis'),
                                        style: const TextStyle(color: Colors.white)),
                                  ],
                                )
                              : Text(t('add_admin')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _currentIsSuperAdmin {
    final user =
        Provider.of<SessionProvider>(context, listen: false).user;
    return user?['isSuperAdmin'] == true;
  }

  List<Map<String, dynamic>> _permissionDefs(String Function(String) t) => [
    {
      'key': 'canManageUsers',
      'label': t('manage_users'),
      'icon': Icons.people_alt_rounded,
      'color': const Color(0xFF304E96),
    },
    {
      'key': 'canManageTransactions',
      'label': t('manage_transactions'),
      'icon': Icons.receipt_long_rounded,
      'color': const Color(0xFF1E6B3B),
    },
    {
      'key': 'canManageSupport',
      'label': t('manage_support'),
      'icon': Icons.support_agent_rounded,
      'color': const Color(0xFF11806A),
    },
    {
      'key': 'canManageContent',
      'label': t('manage_content'),
      'icon': Icons.campaign_rounded,
      'color': const Color(0xFF3157B7),
    },
    {
      'key': 'canManageDigitise',
      'label': t('manage_digitise'),
      'icon': Icons.card_giftcard_rounded,
      'color': const Color(0xFF9B5B21),
    },
    {
      'key': 'canManageSettings',
      'label': t('manage_settings'),
      'icon': Icons.settings_rounded,
      'color': const Color(0xFF296D4E),
    },
    {
      'key': 'canViewAuditLogs',
      'label': t('view_audit_logs'),
      'icon': Icons.history_rounded,
      'color': const Color(0xFF5B2D8E),
    },
  ];

  Future<void> _toggleSuperAdmin(
      String adminId, bool currentValue) async {
    final t = AppLocalizations.of(context).t;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: AppThemeColors.cardBg(ctx),
        title: Text(
          currentValue ? t('revoke_super_admin_question') : t('grant_super_admin_question'),
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: currentValue ? Colors.red : Colors.green),
        ),
        content: Text(
          currentValue
              ? t('admin_lose_super_privileges')
              : t('admin_gain_super_access'),
          style: TextStyle(color: AppThemeColors.primaryText(ctx)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentValue ? Colors.red : Colors.green,
            ),
            child: Text(
              currentValue ? t('revoke') : t('grant'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final response = await ApiClient.patch(
        '/api/admin/admins/$adminId/superadmin',
        body: {'isSuperAdmin': !currentValue},
      );
      if (response.statusCode == 200) {
        fetchAdmins();
        _showStylishSnackBar(
          message: !currentValue
              ? t('super_admin_privileges_granted')
              : t('super_admin_privileges_revoked'),
          icon: Icons.admin_panel_settings,
        );
      } else {
        final data = json.decode(response.body);
        _showStylishSnackBar(
          message: (data['message'] ?? t('failed_to_update')).toString(),
          isSuccess: false,
          icon: Icons.error_outline,
        );
      }
    } catch (_) {
      _showStylishSnackBar(
        message: t('failed_to_update_super_admin_status'),
        isSuccess: false,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _savePermissions(
      String adminId, Map<String, bool> permissions) async {
    final t = AppLocalizations.of(context).t;
    try {
      final response = await ApiClient.patch(
        '/api/admin/admins/$adminId/permissions',
        body: permissions,
      );
      if (response.statusCode == 200) {
        fetchAdmins();
        _showStylishSnackBar(
          message: t('permissions_updated_successfully'),
          icon: Icons.check_circle,
        );
      } else {
        final data = json.decode(response.body);
        _showStylishSnackBar(
          message: (data['message'] ?? t('failed_to_update_permissions'))
              .toString(),
          isSuccess: false,
          icon: Icons.error_outline,
        );
      }
    } catch (_) {
      _showStylishSnackBar(
        message: t('failed_to_update_permissions'),
        isSuccess: false,
        icon: Icons.error_outline,
      );
    }
  }

  void _showPermissionsEditor(Map<String, dynamic> admin) {
    final t = AppLocalizations.of(context).t;
    final permissionDefs = _permissionDefs(t);
    final isSuperAdmin = admin['isSuperAdmin'] == true;
    final existingPerms =
        (admin['permissions'] is Map)
            ? Map<String, dynamic>.from(admin['permissions'] as Map)
            : <String, dynamic>{};

    final perms = <String, bool>{};
    for (final def in permissionDefs) {
      final key = def['key'] as String;
      perms[key] = existingPerms[key] != false;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height: MediaQuery.of(sheetContext).size.height * 0.82,
          decoration: BoxDecoration(
            color: AppThemeColors.cardBg(ctx),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Admin header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.cyan,
                      child: Text(
                        (admin['name'] as String? ?? 'A')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            admin['name'] ?? '',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppThemeColors.primaryText(ctx)),
                          ),
                          Text(
                            admin['email'] ?? '',
                            style: TextStyle(
                                fontSize: 12, color: AppThemeColors.secondaryText(ctx)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),

              // Super admin toggle
              if (_currentIsSuperAdmin) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.star_rounded,
                            color: Colors.amber, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t('super_admin'),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppThemeColors.primaryText(ctx))),
                            Text(t('full_access_all_features'),
                                style: TextStyle(
                                    fontSize: 12, color: AppThemeColors.secondaryText(ctx))),
                          ],
                        ),
                      ),
                      Switch(
                        value: isSuperAdmin,
                        activeColor: Colors.amber,
                        onChanged: (v) {
                          Navigator.pop(ctx);
                          _toggleSuperAdmin(
                              admin['_id'] as String, isSuperAdmin);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],

              // Permission toggles
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  children: [
                    if (isSuperAdmin)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                color: Colors.amber, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t('super_admins_have_all_permissions'),
                                style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...(permissionDefs.map((def) {
                      final key = def['key'] as String;
                      final color = def['color'] as Color;
                      final icon = def['icon'] as IconData;
                      final label = def['label'] as String;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: color, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                label,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppThemeColors.primaryText(ctx)),
                              ),
                            ),
                            Switch(
                              value: isSuperAdmin || (perms[key] ?? true),
                              activeColor: AppColors.cyan,
                              onChanged: isSuperAdmin
                                  ? null
                                  : (v) =>
                                      setSheet(() => perms[key] = v),
                            ),
                          ],
                        ),
                      );
                    })),
                  ],
                ),
              ),

              // Save button (only for non-superadmin)
              if (!isSuperAdmin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _savePermissions(admin['_id'] as String, perms);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.cyan,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        t('save_permissions'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
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

  Widget _buildPermissionIcons(Map<String, dynamic> admin, String Function(String) t) {
    final permissionDefs = _permissionDefs(t);
    final perms = (admin['permissions'] is Map)
        ? Map<String, dynamic>.from(admin['permissions'] as Map)
        : <String, dynamic>{};

    final granted = permissionDefs
        .where((d) => perms[d['key']] != false)
        .toList();
    final denied = permissionDefs.length - granted.length;

    return Row(
      children: [
        ...granted.take(4).map((d) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: d['label'] as String,
                child: Icon(d['icon'] as IconData,
                    size: 14, color: d['color'] as Color),
              ),
            )),
        if (granted.length > 4)
          Text('+${granted.length - 4}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        if (denied > 0) ...[
          const SizedBox(width: 4),
          Text('($denied ${t('restricted_suffix')})',
              style: TextStyle(fontSize: 10, color: Colors.red[300])),
        ],
      ],
    );
  }

  Future<void> removeAdmin(String adminId) async {
    final t = AppLocalizations.of(context).t;
    setState(() => adminBeingRemoved = adminId);
    try {
      final response = await ApiClient.delete('/api/admin/admins/$adminId');

      if (response.statusCode == 200) {
        fetchAdmins();
        _showStylishSnackBar(
          message: t('admin_removed_successfully'),
          icon: Icons.person_remove,
        );
      }
    } catch (e) {
      _showStylishSnackBar(
        message: t('failed_to_remove_admin'),
        isSuccess: false,
        icon: Icons.error_outline,
      );
    } finally {
      setState(() => adminBeingRemoved = null);
    }
  }

  void _showStylishSnackBar({
    required String message,
    bool isSuccess = true,
    IconData? icon,
  }) => showSnack(context, message, isError: !isSuccess);

  void _filterAdmins() {
    if (_searchController.text.isEmpty) {
      setState(() {
        filteredAdmins = admins;
        isSearchMode = false;
      });
      return;
    }

    final query = _searchController.text.toLowerCase();
    setState(() {
      isSearchMode = true;
      filteredAdmins = admins.where((admin) {
        final email = admin['email'].toString().toLowerCase();
        final username = admin['username'].toString().toLowerCase();
        final name = admin['name'].toString().toLowerCase();
        return email.contains(query) ||
            username.contains(query) ||
            name.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context).t;
    return Scaffold(
      backgroundColor: AppThemeColors.scaffoldBg(context),
      body: Stack(
        children: [
          // Top wave background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: TopWaveClipper(),
              child: Container(
                height: context.sh(78),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.cyan, Color(0xFF48CAE4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),

          // Main content
          Column(
            children: [
              // Header with extra padding
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 24),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        t('manage_admins'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Add search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: AppThemeColors.primaryText(context)),
                  decoration: InputDecoration(
                    hintText: t('search_admins'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    filled: true,
                    fillColor: AppThemeColors.cardBg(context),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Admin list container with margin from wave
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: AppThemeColors.cardBg(context),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(30)),
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : admins.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      t('no_admins_found'),
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: AppThemeColors.secondaryText(context),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Column(
                                children: [
                                  Expanded(
                                    child: ListView.builder(
                                      padding:
                                          const EdgeInsets.fromLTRB(16, 24, 16, 16),
                                      itemCount: isSearchMode
                                          ? filteredAdmins.length
                                          : (showAllAdmins
                                              ? admins.length
                                              : min(3, admins.length)),
                                      itemBuilder: (context, index) {
                                        final admin = isSearchMode
                                            ? filteredAdmins[index]
                                            : admins[index];
                                        final isProtected = admin['email'] ==
                                            'chetandudi791@gmail.com';

                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 16),
                                          decoration: BoxDecoration(
                                            color: AppThemeColors.cardBg(context),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: AppColors.cyan
                                                  .withValues(alpha: 0.2),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.03),
                                                blurRadius: 10,
                                                spreadRadius: 0,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Stack(
                                            children: [
                                              if (isProtected)
                                                Positioned(
                                                  top: 8,
                                                  right: 8,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                            vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade200,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                            Icons.verified_user,
                                                            size: 16,
                                                            color: Colors
                                                                .grey.shade700),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          t('protected_label'),
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey.shade700,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              Padding(
                                                padding: const EdgeInsets.all(16),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 30,
                                                      backgroundColor:
                                                          AppColors.cyan,
                                                      child: Text(
                                                        admin['name'][0]
                                                            .toUpperCase(),
                                                        style: const TextStyle(
                                                          fontSize: 24,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  admin['name'],
                                                                  style: TextStyle(
                                                                    fontSize: 17,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    color: AppThemeColors.primaryText(context),
                                                                  ),
                                                                ),
                                                              ),
                                                              if (admin['isSuperAdmin'] ==
                                                                  true)
                                                                Container(
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          8,
                                                                      vertical:
                                                                          3),
                                                                  decoration:
                                                                      BoxDecoration(
                                                                    color: Colors
                                                                        .amber
                                                                        .withValues(alpha: 0.15),
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(10),
                                                                    border: Border.all(
                                                                        color: Colors
                                                                            .amber
                                                                            .withValues(alpha: 0.4)),
                                                                  ),
                                                                  child: Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      const Icon(
                                                                          Icons
                                                                              .star_rounded,
                                                                          color:
                                                                              Colors.amber,
                                                                          size:
                                                                              12),
                                                                      const SizedBox(
                                                                          width:
                                                                              3),
                                                                      Text(
                                                                        t('super_badge'),
                                                                        style: const TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                            fontWeight: FontWeight
                                                                                .bold,
                                                                            color:
                                                                                Colors.amber),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                          const SizedBox(height: 3),
                                                          Text(
                                                            admin['email'],
                                                            style: TextStyle(
                                                              color: AppThemeColors.secondaryText(context),
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                          Text(
                                                            '@${admin['username']}',
                                                            style: TextStyle(
                                                              color: AppThemeColors.mutedText(context),
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          if (admin['isSuperAdmin'] !=
                                                              true) ...[
                                                            const SizedBox(
                                                                height: 6),
                                                            _buildPermissionIcons(
                                                                admin, t),
                                                          ],
                                                        ],
                                                      ),
                                                    ),
                                                    Column(
                                                      children: [
                                                        IconButton(
                                                          icon: const Icon(
                                                              Icons
                                                                  .manage_accounts_rounded,
                                                              color: Color(
                                                                  0xFF00B4D8)),
                                                          tooltip:
                                                              t('edit_permissions_tooltip'),
                                                          onPressed: () =>
                                                              _showPermissionsEditor(
                                                                  admin),
                                                        ),
                                                        if (!isProtected)
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons
                                                                    .delete_outline,
                                                                color:
                                                                    Colors.red),
                                                            onPressed: () =>
                                                                _showDeleteConfirmation(
                                                                    admin),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Add loading overlay when this admin is being removed
                                              if (adminBeingRemoved ==
                                                  admin['_id'])
                                                Positioned.fill(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: AppThemeColors.cardBg(context)
                                                          .withValues(alpha: 0.7),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                    ),
                                                    child: Center(
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const SizedBox(
                                                            width: 24,
                                                            height: 24,
                                                            child:
                                                                CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              valueColor:
                                                                  AlwaysStoppedAnimation<
                                                                          Color>(
                                                                      Color(
                                                                          0xFF00B4D8)),
                                                            ),
                                                          ),
                                                          const SizedBox(height: 8),
                                                          Text(
                                                            t('removing_admin_ellipsis'),
                                                            style: const TextStyle(
                                                              color: Color(
                                                                  0xFF00B4D8),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (!isSearchMode &&
                                      admins.length > 3 &&
                                      !showAllAdmins)
                                    Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: ElevatedButton(
                                        onPressed: () {
                                          setState(() {
                                            showAllAdmins = true;
                                          });
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.cyan,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 30, vertical: 15),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(30),
                                          ),
                                        ),
                                        child: Text(
                                          t('view_all_admins'),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'viewAll',
            onPressed: () {
              _searchController.clear();
              FocusScope.of(context).unfocus();
              fetchAdmins();
            },
            backgroundColor: const Color(0xFF48CAE4),
            child: const Icon(Icons.people_outline),
            mini: true,
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'addAdmin',
            onPressed: addAdmin,
            icon: const Icon(Icons.person_add),
            label: Text(t('add_admin')),
            backgroundColor: AppColors.cyan,
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(dynamic admin) {
    final t = AppLocalizations.of(context).t;
    showGeneralDialog(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) => Container(),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeInOut,
        );

        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: AlertDialog(
              backgroundColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              content: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppThemeColors.cardBg(dialogContext),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const Icon(
                          Icons.warning_rounded,
                          color: Colors.red,
                          size: 40,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t('remove_admin_access_title'),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      t('are_you_sure_remove'),
                      style: TextStyle(
                        color: AppThemeColors.secondaryText(dialogContext),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      admin['name'],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppThemeColors.primaryText(dialogContext),
                      ),
                    ),
                    Text(
                      t('as_admin_question'),
                      style: TextStyle(
                        color: AppThemeColors.secondaryText(dialogContext),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(
                            t('cancel'),
                            style: TextStyle(
                              color: AppThemeColors.secondaryText(dialogContext),
                              fontSize: 16,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            removeAdmin(admin['_id']);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            t('remove_access'),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}
