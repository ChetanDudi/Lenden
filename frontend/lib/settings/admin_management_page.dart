import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:math';
import '../utils/api_client.dart';
import '../session.dart';
import '../admin/widgets/top_wave_clipper.dart';

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
        message: 'Failed to fetch admins',
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
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
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
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
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
                              Icon(Icons.admin_panel_settings,
                                  color: Colors.white, size: 40),
                              Text(
                                'Add New Admin',
                                style: TextStyle(
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
                        color: Colors.white,
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
                        decoration: InputDecoration(
                          labelText: 'Name',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Color(0xFF00B4D8)),
                          ),
                          prefixIcon:
                              Icon(Icons.person, color: Color(0xFF00B4D8)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        validator: (value) =>
                            value?.isEmpty ?? true ? 'Required' : null,
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
                            color: Colors.white,
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
                            decoration: InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: emailError != null
                                      ? Colors.red
                                      : Color(0xFF00B4D8),
                                ),
                              ),
                              prefixIcon: Icon(Icons.email,
                                  color: emailError != null
                                      ? Colors.red
                                      : Color(0xFF00B4D8)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? 'Required' : null,
                            onSaved: (value) => email = value ?? '',
                          ),
                        ),
                        if (emailError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 16),
                            child: Text(
                              emailError ?? '',
                              style: TextStyle(
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
                            color: Colors.white,
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
                            decoration: InputDecoration(
                              labelText: 'Username',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide(
                                  color: usernameError != null
                                      ? Colors.red
                                      : Color(0xFF00B4D8),
                                ),
                              ),
                              prefixIcon: Icon(Icons.account_circle,
                                  color: usernameError != null
                                      ? Colors.red
                                      : Color(0xFF00B4D8)),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            validator: (value) =>
                                value?.isEmpty ?? true ? 'Required' : null,
                            onSaved: (value) => username = value ?? '',
                          ),
                        ),
                        if (usernameError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 16),
                            child: Text(
                              usernameError ?? '',
                              style: TextStyle(
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
                        color: Colors.white,
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
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Color(0xFF00B4D8)),
                          ),
                          prefixIcon:
                              Icon(Icons.lock, color: Color(0xFF00B4D8)),
                          filled: true,
                          fillColor: Colors.white,
                          helperText:
                              'Must be 8-30 characters with uppercase, lowercase, and special character',
                          helperMaxLines: 2,
                        ),
                        validator: (value) {
                          if (value?.isEmpty ?? true) return 'Required';
                          if (!isPasswordValid(value!)) {
                            return 'Password must meet requirements';
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
                        color: Colors.white,
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
                          labelText: 'Gender',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: Color(0xFF00B4D8)),
                          ),
                          prefixIcon:
                              Icon(Icons.people, color: Color(0xFF00B4D8)),
                          filled: true,
                          fillColor: Colors.white,
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
                              : () => Navigator.pop(context),
                          child: Text('Cancel',
                              style: TextStyle(color: Colors.grey[600])),
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
                                        Navigator.pop(context);
                                        fetchAdmins();
                                        _showStylishSnackBar(
                                          message: responseData['message'] ??
                                              'Admin added successfully',
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    responseData['message'] ??
                                                        'Failed to add admin'),
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
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Error: ${e.toString()}'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF00B4D8),
                            disabledBackgroundColor:
                                Color(0xFF00B4D8).withValues(alpha: 0.5),
                            padding: EdgeInsets.symmetric(
                                horizontal: 30, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: isSubmitting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Adding admin...',
                                        style: TextStyle(color: Colors.white)),
                                  ],
                                )
                              : Text('Add Admin'),
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

  static const List<Map<String, dynamic>> _permissionDefs = [
    {
      'key': 'canManageUsers',
      'label': 'Manage Users',
      'icon': Icons.people_alt_rounded,
      'color': Color(0xFF304E96),
    },
    {
      'key': 'canManageTransactions',
      'label': 'Manage Transactions',
      'icon': Icons.receipt_long_rounded,
      'color': Color(0xFF1E6B3B),
    },
    {
      'key': 'canManageSupport',
      'label': 'Manage Support',
      'icon': Icons.support_agent_rounded,
      'color': Color(0xFF11806A),
    },
    {
      'key': 'canManageContent',
      'label': 'Manage Content',
      'icon': Icons.campaign_rounded,
      'color': Color(0xFF3157B7),
    },
    {
      'key': 'canManageDigitise',
      'label': 'Manage Digitise',
      'icon': Icons.card_giftcard_rounded,
      'color': Color(0xFF9B5B21),
    },
    {
      'key': 'canManageSettings',
      'label': 'Manage Settings',
      'icon': Icons.settings_rounded,
      'color': Color(0xFF296D4E),
    },
    {
      'key': 'canViewAuditLogs',
      'label': 'View Audit Logs',
      'icon': Icons.history_rounded,
      'color': Color(0xFF5B2D8E),
    },
  ];

  Future<void> _toggleSuperAdmin(
      String adminId, bool currentValue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          currentValue ? 'Revoke Super Admin?' : 'Grant Super Admin?',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              color: currentValue ? Colors.red : Colors.green),
        ),
        content: Text(
          currentValue
              ? 'This admin will lose all super admin privileges.'
              : 'This admin will gain full super admin access to all features.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: currentValue ? Colors.red : Colors.green,
            ),
            child: Text(
              currentValue ? 'Revoke' : 'Grant',
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
              ? 'Super admin privileges granted'
              : 'Super admin privileges revoked',
          icon: Icons.admin_panel_settings,
        );
      } else {
        final data = json.decode(response.body);
        _showStylishSnackBar(
          message: (data['message'] ?? 'Failed to update').toString(),
          isSuccess: false,
          icon: Icons.error_outline,
        );
      }
    } catch (_) {
      _showStylishSnackBar(
        message: 'Failed to update super admin status',
        isSuccess: false,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _savePermissions(
      String adminId, Map<String, bool> permissions) async {
    try {
      final response = await ApiClient.patch(
        '/api/admin/admins/$adminId/permissions',
        body: permissions,
      );
      if (response.statusCode == 200) {
        fetchAdmins();
        _showStylishSnackBar(
          message: 'Permissions updated successfully',
          icon: Icons.check_circle,
        );
      } else {
        final data = json.decode(response.body);
        _showStylishSnackBar(
          message: (data['message'] ?? 'Failed to update permissions')
              .toString(),
          isSuccess: false,
          icon: Icons.error_outline,
        );
      }
    } catch (_) {
      _showStylishSnackBar(
        message: 'Failed to update permissions',
        isSuccess: false,
        icon: Icons.error_outline,
      );
    }
  }

  void _showPermissionsEditor(Map<String, dynamic> admin) {
    final isSuperAdmin = admin['isSuperAdmin'] == true;
    final existingPerms =
        (admin['permissions'] is Map)
            ? Map<String, dynamic>.from(admin['permissions'] as Map)
            : <String, dynamic>{};

    final perms = <String, bool>{};
    for (final def in _permissionDefs) {
      final key = def['key'] as String;
      perms[key] = existingPerms[key] != false;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(24)),
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
                      backgroundColor: const Color(0xFF00B4D8),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          Text(
                            admin['email'] ?? '',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
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
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Super Admin',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            Text('Full access to all features',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
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
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                color: Colors.amber, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Super admins have all permissions automatically.',
                                style: TextStyle(
                                    color: Colors.amber,
                                    fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ...(_permissionDefs.map((def) {
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
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            Switch(
                              value: isSuperAdmin || (perms[key] ?? true),
                              activeColor: const Color(0xFF00B4D8),
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
                        backgroundColor: const Color(0xFF00B4D8),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save Permissions',
                        style: TextStyle(
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

  Widget _buildPermissionIcons(Map<String, dynamic> admin) {
    final perms = (admin['permissions'] is Map)
        ? Map<String, dynamic>.from(admin['permissions'] as Map)
        : <String, dynamic>{};

    final granted = _permissionDefs
        .where((d) => perms[d['key']] != false)
        .toList();
    final denied = _permissionDefs.length - granted.length;

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
          Text('($denied restricted)',
              style: TextStyle(fontSize: 10, color: Colors.red[300])),
        ],
      ],
    );
  }

  Future<void> removeAdmin(String adminId) async {
    setState(() => adminBeingRemoved = adminId);
    try {
      final response = await ApiClient.delete('/api/admin/admins/$adminId');

      if (response.statusCode == 200) {
        fetchAdmins();
        _showStylishSnackBar(
          message: 'Admin removed successfully',
          icon: Icons.person_remove,
        );
      }
    } catch (e) {
      _showStylishSnackBar(
        message: 'Failed to remove admin',
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
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(10),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSuccess ? Color(0xFF00B4D8) : Colors.red,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: (isSuccess ? Color(0xFF00B4D8) : Colors.red)
                    .withValues(alpha: 0.3),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                icon ?? (isSuccess ? Icons.check_circle : Icons.error),
                color: Colors.white,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
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
                height: 220, // Increased height for wave
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF48CAE4)],
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
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Manage Admins',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
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
                  decoration: InputDecoration(
                    hintText: 'Search admins...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 10),

              // Admin list container with margin from wave
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(top: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(30)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(30)),
                    child: isLoading
                        ? Center(child: CircularProgressIndicator())
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
                                    SizedBox(height: 16),
                                    Text(
                                      'No admins found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey[600],
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
                                          EdgeInsets.fromLTRB(16, 24, 16, 16),
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
                                          margin: EdgeInsets.only(bottom: 16),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Color(0xFF00B4D8)
                                                  .withValues(alpha: 0.2),
                                              width: 1,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.03),
                                                blurRadius: 10,
                                                spreadRadius: 0,
                                                offset: Offset(0, 2),
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
                                                        EdgeInsets.symmetric(
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
                                                        SizedBox(width: 4),
                                                        Text(
                                                          'Protected',
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
                                                padding: EdgeInsets.all(16),
                                                child: Row(
                                                  children: [
                                                    CircleAvatar(
                                                      radius: 30,
                                                      backgroundColor:
                                                          Color(0xFF00B4D8),
                                                      child: Text(
                                                        admin['name'][0]
                                                            .toUpperCase(),
                                                        style: TextStyle(
                                                          fontSize: 24,
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    SizedBox(width: 16),
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
                                                                  style: const TextStyle(
                                                                    fontSize: 17,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
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
                                                                  child: const Row(
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Icon(
                                                                          Icons
                                                                              .star_rounded,
                                                                          color:
                                                                              Colors.amber,
                                                                          size:
                                                                              12),
                                                                      SizedBox(
                                                                          width:
                                                                              3),
                                                                      Text(
                                                                        'Super',
                                                                        style: TextStyle(
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
                                                              color: Colors.grey
                                                                  .shade600,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                          Text(
                                                            '@${admin['username']}',
                                                            style: TextStyle(
                                                              color: Colors.grey
                                                                  .shade500,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                          if (admin['isSuperAdmin'] !=
                                                              true) ...[
                                                            const SizedBox(
                                                                height: 6),
                                                            _buildPermissionIcons(
                                                                admin),
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
                                                              'Edit Permissions',
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
                                                      color: Colors.white
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
                                                          SizedBox(
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
                                                          SizedBox(height: 8),
                                                          Text(
                                                            'Removing admin...',
                                                            style: TextStyle(
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
                                          backgroundColor: Color(0xFF00B4D8),
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 30, vertical: 15),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(30),
                                          ),
                                        ),
                                        child: Text(
                                          'View All Admins',
                                          style: TextStyle(
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
            backgroundColor: Color(0xFF48CAE4),
            child: Icon(Icons.people_outline),
            mini: true,
          ),
          SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'addAdmin',
            onPressed: addAdmin,
            icon: Icon(Icons.person_add),
            label: Text('Add Admin'),
            backgroundColor: Color(0xFF00B4D8),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(dynamic admin) {
    showGeneralDialog(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) => Container(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
                padding: EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                        Icon(
                          Icons.warning_rounded,
                          color: Colors.red,
                          size: 40,
                        ),
                      ],
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Remove Admin Access',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Are you sure you want to remove',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      admin['name'],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      'as admin?',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            removeAdmin(admin['_id']);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            'Remove Access',
                            style: TextStyle(fontSize: 16),
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
      transitionDuration: Duration(milliseconds: 300),
    );
  }
}
