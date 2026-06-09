import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../session.dart';
import 'custom_warning_widget.dart';
import '../utils/api_client.dart';

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
  double _editableRating = 0.0;

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
      final session = Provider.of<SessionProvider>(context, listen: false);
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
          _editableRating = _rating;

          // Set controller values
          _nameController.text = _name;
          _phoneController.text = _phone;
          _addressController.text = _address;
        });
      }
    } catch (e) {
      if (mounted) {
        CustomWarningWidget.showAnimatedError(
            context, 'Error loading account information: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateAccountInformation() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      final response = await ApiClient.put(
        '/api/users/account-information',
        body: {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'gender': _gender,
          'birthday': _birthday?.toIso8601String(),
          'rating': _editableRating,
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          CustomWarningWidget.showAnimatedSuccess(
              context, 'Account information updated successfully!');
          // Update session data
          await session.refreshUserProfile();
        }
      } else {
        final errorData = json.decode(response.body);
        if (mounted) {
          CustomWarningWidget.showAnimatedError(context,
              errorData['message'] ?? 'Failed to update account information');
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6FA),
      appBar: AppBar(
        title: const Text(
          'Account Information',
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
              onPressed: _isSaving ? null : _updateAccountInformation,
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
                                color: Color(0xFF00B4D8),
                              ),
                        const SizedBox(height: 16),
                        const Text(
                          'Account Information',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Manage your personal account details',
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

                  // Account Information Section
                  _buildSettingsSection(
                    'Personal Information',
                    [
                      _buildReadOnlyTileWithAvatar(
                        'Username',
                        _username,
                        Icons.person_outline,
                      ),
                      _buildReadOnlyTileWithAvatar(
                        'Email',
                        _email,
                        Icons.email_outlined,
                      ),
                      _buildEditableTile(
                        'Full Name',
                        'Enter your full name',
                        Icons.badge_outlined,
                        _nameController,
                        TextInputType.name,
                      ),
                      _buildEditableTile(
                        'Phone Number',
                        'Enter your phone number',
                        Icons.phone_outlined,
                        _phoneController,
                        TextInputType.phone,
                      ),
                      _buildEditableTile(
                        'Address',
                        'Enter your address',
                        Icons.location_on_outlined,
                        _addressController,
                        TextInputType.streetAddress,
                        maxLines: 3,
                      ),
                      _buildDropdownTile(
                        'Gender',
                        'Select your gender',
                        Icons.person_outline,
                        _gender,
                        {
                          'Male': 'Male',
                          'Female': 'Female',
                          'Other': 'Other',
                        },
                        (value) => setState(() => _gender = value!),
                      ),
                      _buildDateTile(
                        'Birthday',
                        'Select your birthday',
                        Icons.cake_outlined,
                        _birthday,
                        () => _selectDate(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Account Status Section
                  _buildSettingsSection(
                    'Account Status',
                    [
                      _buildStatusTile(
                        'Account Status',
                        'Active',
                        Icons.check_circle_outline,
                        Colors.green,
                      ),
                      _buildStatusTile(
                        'Email Verification',
                        'Verified',
                        Icons.verified_outlined,
                        Colors.green,
                      ),
                      _buildStatusTile(
                        'Member Since',
                        _memberSince != null
                            ? _formatDate(_memberSince!)
                            : 'Not available',
                        Icons.calendar_today_outlined,
                        Colors.blue,
                      ),
                      _buildRatingTile(
                        'User Rating',
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
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Account Information Tips:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Keep your information up to date for better service\n• Your username and email cannot be changed\n• Accurate information helps with account security\n• We use this information to personalize your experience',
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

  Widget _buildReadOnlyTile(
    String title,
    String value,
    IconData icon,
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
        value,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.grey,
        ),
      ),
      trailing: const Icon(
        Icons.lock_outline,
        color: Colors.grey,
        size: 16,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildReadOnlyTileWithAvatar(
    String title,
    String value,
    IconData icon,
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
        value,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.grey,
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
          const Icon(
            Icons.lock_outline,
            color: Colors.grey,
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
      leading: Icon(icon, color: const Color(0xFF00B4D8)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
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
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
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
        value: value.isNotEmpty ? value : null,
        onChanged: onChanged,
        underline: Container(),
        hint: const Text('Select'),
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
      trailing: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF00B4D8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            date != null ? _formatDate(date) : 'Select Date',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF00B4D8),
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
      leading: Icon(icon, color: const Color(0xFF00B4D8)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
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
